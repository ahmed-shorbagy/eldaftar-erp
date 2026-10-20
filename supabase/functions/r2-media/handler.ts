// Authenticated presigned-URL broker for Cloudflare R2. The owner's bearer is
// verified and their shop resolved through RLS before any URL is issued. Object
// keys are scoped to the shop, so an owner cannot read another shop's object.
// After an upload, `confirm` reads the object back from R2, verifies size,
// type, and hash, and records the verified facts through a service-only RPC.
// Domain RPCs accept only objects present in that registry.

export type MediaKind = "shop_image" | "invoice_logo" | "note_image";

export type R2Caller = { shopId: string; userId: string };

export type FetchedObject =
  | { status: "ok"; bytes: Uint8Array }
  | { status: "missing" }
  | { status: "too_large" };

export type RecordInput = {
  actor: string;
  shopId: string;
  kind: MediaKind;
  objectKey: string;
  byteSize: number;
  sha256: string;
  // Present for content-addressed image kinds so the database's strict image
  // parser derives mime and dimensions; absent for note images.
  imageBase64: string | null;
};

export type RecordResult =
  | { ok: true; facts: Record<string, unknown> }
  | { ok: false; code: string };

export type R2MediaPorts = {
  // Returns the caller's owned shop and user id, or null when unauthenticated.
  owner(token: string): Promise<R2Caller | null>;
  // Issues a presigned URL for the already-derived object key.
  presign(args: {
    method: "GET" | "PUT";
    objectKey: string;
    mime?: string;
    expiresSeconds: number;
  }): Promise<string>;
  // Reads an object from R2 without buffering more than maxBytes.
  fetchObject(objectKey: string, maxBytes: number): Promise<FetchedObject>;
  // Records verified facts with the service role.
  recordObject(input: RecordInput): Promise<RecordResult>;
};

const headers: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-client-info",
  "cache-control": "no-store",
  "content-type": "application/json; charset=utf-8",
};

const uuidPattern =
  "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}";
const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const sha256Pattern = /^[0-9a-f]{64}$/;

const prefixes: Record<MediaKind, string> = {
  shop_image: "shop-image",
  invoice_logo: "invoice-logo",
  note_image: "note-image",
};

const extensions: Record<string, string> = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
};

const allowedMimes: Record<MediaKind, string[]> = {
  shop_image: ["image/jpeg", "image/png"],
  invoice_logo: ["image/jpeg", "image/png"],
  note_image: ["image/jpeg", "image/png", "image/webp"],
};

const maxObjectBytes: Record<MediaKind, number> = {
  shop_image: 2097152,
  invoice_logo: 2097152,
  note_image: 5242880,
};

const recordCodes = new Set([
  "forbidden",
  "shop_not_active",
  "media_rejected",
  "media_mismatch",
]);

const uploadExpirySeconds = 120;
const readExpirySeconds = 300;
const maxBodyBytes = 4096;

const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers });

export function keyPattern(kind: MediaKind, shop: string): RegExp {
  const prefix = prefixes[kind];
  if (kind === "note_image") {
    return new RegExp(
      `^${prefix}/${shop}/${uuidPattern}/${uuidPattern}\\.(jpg|png|webp)$`,
    );
  }
  return new RegExp(`^${prefix}/${shop}/([0-9a-f]{64})\\.(jpg|png)$`);
}

export function mimeMatches(bytes: Uint8Array, mime: string): boolean {
  const at = (i: number) => bytes[i];
  if (mime === "image/jpeg") {
    return bytes.length > 3 && at(0) === 0xff && at(1) === 0xd8 &&
      at(2) === 0xff;
  }
  if (mime === "image/png") {
    const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
    return bytes.length > 8 && signature.every((byte, i) => at(i) === byte);
  }
  if (mime === "image/webp") {
    const ascii = (from: number, text: string) =>
      [...text].every((char, i) => at(from + i) === char.charCodeAt(0));
    return bytes.length > 12 && ascii(0, "RIFF") && ascii(8, "WEBP");
  }
  return false;
}

export async function handleR2Media(
  request: Request,
  ports: R2MediaPorts,
): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers });
  }
  if (request.method !== "POST") return reply(405, { code: "invalid_input" });

  const bearer = request.headers.get("authorization");
  if (!bearer?.startsWith("Bearer ") || bearer.length > 16384) {
    return reply(401, { code: "unauthenticated" });
  }
  const token = bearer.slice(7);

  const body = await readJson(request);
  if (body === null) return reply(400, { code: "invalid_input" });

  const kindValue = body.kind;
  const op = body.op;
  if (
    typeof kindValue !== "string" ||
    !(kindValue in prefixes) ||
    (op !== "upload" && op !== "read" && op !== "confirm")
  ) {
    return reply(400, { code: "invalid_input" });
  }
  const kind = kindValue as MediaKind;
  const prefix = prefixes[kind];

  let caller: R2Caller | null;
  try {
    caller = await ports.owner(token);
  } catch {
    return reply(503, { code: "unavailable" });
  }
  if (
    caller === null || !uuid.test(caller.shopId) || !uuid.test(caller.userId)
  ) {
    return reply(401, { code: "unauthenticated" });
  }
  const shop = caller.shopId;

  try {
    if (op === "upload") {
      const mime = body.mime;
      if (typeof mime !== "string" || !allowedMimes[kind].includes(mime)) {
        return reply(400, { code: "invalid_input" });
      }
      let objectKey: string;
      if (kind === "note_image") {
        const name = body.object_name;
        objectKey = `${prefix}/${name}`;
        if (
          typeof name !== "string" ||
          !keyPattern(kind, shop).test(objectKey) ||
          !objectKey.endsWith(`.${extensions[mime]}`)
        ) {
          return reply(400, { code: "invalid_input" });
        }
      } else {
        const sha = body.sha256;
        if (typeof sha !== "string" || !sha256Pattern.test(sha)) {
          return reply(400, { code: "invalid_input" });
        }
        objectKey = `${prefix}/${shop}/${sha}.${extensions[mime]}`;
      }
      const url = await ports.presign({
        method: "PUT",
        objectKey,
        mime,
        expiresSeconds: uploadExpirySeconds,
      });
      return reply(200, {
        object_key: objectKey,
        url,
        method: "PUT",
        headers: { "content-type": mime },
        expires_in: uploadExpirySeconds,
      });
    }

    const objectKey = body.object_key;
    if (op === "read") {
      if (
        typeof objectKey !== "string" ||
        objectKey.length > 512 ||
        !objectKey.startsWith(`${prefix}/${shop}/`) ||
        objectKey.includes("..") ||
        objectKey.includes("//")
      ) {
        return reply(403, { code: "forbidden" });
      }
      const url = await ports.presign({
        method: "GET",
        objectKey,
        expiresSeconds: readExpirySeconds,
      });
      return reply(200, { url, expires_in: readExpirySeconds });
    }

    // op === "confirm"
    if (typeof objectKey !== "string" || objectKey.length > 512) {
      return reply(400, { code: "invalid_input" });
    }
    const match = keyPattern(kind, shop).exec(objectKey);
    if (match === null) return reply(403, { code: "forbidden" });
    const extension = objectKey.slice(objectKey.lastIndexOf(".") + 1);
    const mime = Object.keys(extensions).find((key) =>
      extensions[key] === extension
    )!;

    const fetched = await ports.fetchObject(objectKey, maxObjectBytes[kind]);
    if (fetched.status === "missing") {
      return reply(404, { code: "media_missing" });
    }
    if (fetched.status === "too_large") {
      return reply(400, { code: "media_rejected" });
    }
    const bytes = fetched.bytes;
    if (bytes.length === 0 || !mimeMatches(bytes, mime)) {
      return reply(400, { code: "media_rejected" });
    }
    const sha = await sha256Hex(bytes);
    if (kind !== "note_image" && match[1] !== sha) {
      return reply(400, { code: "media_rejected" });
    }

    const recorded = await ports.recordObject({
      actor: caller.userId,
      shopId: shop,
      kind,
      objectKey,
      byteSize: bytes.length,
      sha256: sha,
      imageBase64: kind === "note_image" ? null : toBase64(bytes),
    });
    if (!recorded.ok) {
      if (!recordCodes.has(recorded.code)) {
        return reply(503, { code: "unavailable" });
      }
      const status = recorded.code === "forbidden" ? 403 : 400;
      return reply(status, { code: recorded.code });
    }
    return reply(200, recorded.facts);
  } catch {
    return reply(503, { code: "unavailable" });
  }
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const copy = new Uint8Array(bytes.length);
  copy.set(bytes);
  const digest = await crypto.subtle.digest("SHA-256", copy.buffer);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunk) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunk));
  }
  return btoa(binary);
}

async function readJson(
  request: Request,
): Promise<Record<string, unknown> | null> {
  const reader = request.body?.getReader();
  if (!reader) return null;
  const chunks: Uint8Array[] = [];
  let length = 0;
  try {
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      length += next.value.length;
      if (length > maxBodyBytes) {
        await reader.cancel();
        return null;
      }
      chunks.push(next.value);
    }
  } catch {
    return null;
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  try {
    const parsed = JSON.parse(
      new TextDecoder("utf-8", { fatal: true }).decode(bytes),
    );
    if (
      parsed === null || typeof parsed !== "object" || Array.isArray(parsed)
    ) {
      return null;
    }
    return parsed as Record<string, unknown>;
  } catch {
    return null;
  }
}
