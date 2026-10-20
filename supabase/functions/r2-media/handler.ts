// Authenticated presigned-URL broker for Cloudflare R2. The owner's bearer is
// verified and their shop resolved through RLS before any URL is issued. Object
// keys are content-addressed and scoped to the shop, so an owner can neither
// read another shop's object nor overwrite an existing hash with new bytes.

export type MediaKind = "shop_image" | "invoice_logo" | "note_image";

export type R2MediaPorts = {
  // Returns the caller's owned shop id, or null when unauthenticated/none.
  ownedShop(token: string): Promise<string | null>;
  // Issues a presigned URL for the already-derived object key.
  presign(args: {
    method: "GET" | "PUT";
    objectKey: string;
    mime?: string;
    expiresSeconds: number;
  }): Promise<string>;
};

const headers: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-client-info",
  "cache-control": "no-store",
  "content-type": "application/json; charset=utf-8",
};

const uuid =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const sha256 = /^[0-9a-f]{64}$/;

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

const uploadExpirySeconds = 120;
const readExpirySeconds = 300;
const maxBodyBytes = 4096;

const reply = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers });

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

  const kind = body.kind;
  const op = body.op;
  if (
    typeof kind !== "string" ||
    !(kind in prefixes) ||
    (op !== "upload" && op !== "read")
  ) {
    return reply(400, { code: "invalid_input" });
  }
  const prefix = prefixes[kind as MediaKind];

  let shop: string | null;
  try {
    shop = await ports.ownedShop(token);
  } catch {
    return reply(503, { code: "unavailable" });
  }
  if (shop === null || !uuid.test(shop)) {
    return reply(401, { code: "unauthenticated" });
  }

  try {
    if (op === "upload") {
      const sha = body.sha256;
      const mime = body.mime;
      if (
        typeof sha !== "string" ||
        !sha256.test(sha) ||
        typeof mime !== "string" ||
        !(mime in extensions)
      ) {
        return reply(400, { code: "invalid_input" });
      }
      const objectKey = `${prefix}/${shop}/${sha}.${extensions[mime]}`;
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

    // op === "read"
    const objectKey = body.object_key;
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
  } catch {
    return reply(503, { code: "unavailable" });
  }
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
