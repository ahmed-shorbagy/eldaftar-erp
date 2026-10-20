import { createClient } from "@supabase/supabase-js";
import {
  loadCallerKeys,
  resolveServerCredentials,
} from "../owner-register/http.ts";
import {
  type FetchedObject,
  handleR2Media,
  type R2MediaPorts,
} from "./handler.ts";
import { amzDateNow, presign } from "./sign.ts";

const options = {
  auth: {
    persistSession: false,
    autoRefreshToken: false,
    detectSessionInUrl: false,
  },
  global: {
    fetch: (input: RequestInfo | URL, init?: RequestInit) =>
      fetch(input, {
        ...init,
        signal: init?.signal ?? AbortSignal.timeout(15000),
      }),
  },
};

type R2Config = {
  accountId: string;
  accessKeyId: string;
  secretAccessKey: string;
  bucket: string;
  host: string;
  region: string;
};

function resolveR2(env: Record<string, string | undefined>): R2Config | null {
  const accountId = env.R2_ACCOUNT_ID ?? "";
  const accessKeyId = env.R2_ACCESS_KEY_ID ?? "";
  const secretAccessKey = env.R2_SECRET_ACCESS_KEY ?? "";
  const bucket = env.R2_BUCKET ?? "";
  if (!accountId || !accessKeyId || !secretAccessKey || !bucket) return null;
  const host = env.R2_ENDPOINT_HOST ??
    `${accountId}.r2.cloudflarestorage.com`;
  return {
    accountId,
    accessKeyId,
    secretAccessKey,
    bucket,
    host,
    region: env.R2_REGION ?? "auto",
  };
}

async function readBounded(
  response: Response,
  maxBytes: number,
): Promise<FetchedObject> {
  const declared = Number(response.headers.get("content-length") ?? "0");
  if (declared > maxBytes) {
    await response.body?.cancel();
    return { status: "too_large" };
  }
  const reader = response.body?.getReader();
  if (!reader) return { status: "ok", bytes: new Uint8Array() };
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    const next = await reader.read();
    if (next.done) break;
    length += next.value.length;
    if (length > maxBytes) {
      await reader.cancel();
      return { status: "too_large" };
    }
    chunks.push(next.value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  return { status: "ok", bytes };
}

Deno.serve((request) => {
  const env = Deno.env.toObject();
  const credentials = resolveServerCredentials(env);
  const keys = loadCallerKeys(env);
  const r2 = resolveR2(env);
  if (!credentials || !keys || keys.publishable.length === 0 || !r2) {
    return new Response(JSON.stringify({ code: "unavailable" }), {
      status: 503,
      headers: {
        "cache-control": "no-store",
        "content-type": "application/json",
      },
    });
  }

  const sign = (
    method: "GET" | "PUT",
    objectKey: string,
    expiresSeconds: number,
    mime?: string,
  ) =>
    presign({
      method,
      host: r2.host,
      canonicalUri: `/${r2.bucket}/${objectKey}`,
      region: r2.region,
      service: "s3",
      accessKeyId: r2.accessKeyId,
      secretAccessKey: r2.secretAccessKey,
      amzDate: amzDateNow(new Date()),
      expiresSeconds,
      extraQuery: method === "PUT" && mime
        ? { "Content-Type": mime }
        : undefined,
    });

  const admin = createClient(credentials.url, credentials.serviceKey, options);

  const ports: R2MediaPorts = {
    async owner(token) {
      const caller = createClient(credentials.url, keys.publishable[0], {
        ...options,
        global: {
          ...options.global,
          headers: { Authorization: `Bearer ${token}` },
        },
      });
      const { data: user, error: userError } = await caller.auth.getUser(
        token,
      );
      if (userError || !user?.user?.id) return null;
      const { data, error } = await caller.rpc("list_my_shop_accounts");
      if (error || !Array.isArray(data) || data.length === 0) return null;
      const owner = data.find((row) =>
        row && typeof row === "object" && row.member_role === "owner"
      ) as { shop_id?: unknown } | undefined;
      return owner && typeof owner.shop_id === "string"
        ? { shopId: owner.shop_id, userId: user.user.id }
        : null;
    },
    presign({ method, objectKey, mime, expiresSeconds }) {
      return sign(method, objectKey, expiresSeconds, mime);
    },
    async fetchObject(objectKey, maxBytes) {
      const url = await sign("GET", objectKey, 60);
      const response = await fetch(url, {
        signal: AbortSignal.timeout(30000),
      });
      if (response.status === 404) {
        await response.body?.cancel();
        return { status: "missing" };
      }
      if (response.status !== 200) {
        await response.body?.cancel();
        throw new Error("r2_unavailable");
      }
      return await readBounded(response, maxBytes);
    },
    async recordObject(input) {
      const { data, error } = await admin.rpc("record_r2_media_object_v1", {
        p_actor: input.actor,
        p_shop: input.shopId,
        p_kind: input.kind,
        p_object_key: input.objectKey,
        p_byte_size: input.byteSize,
        p_sha256: input.sha256,
        p_image_base64: input.imageBase64,
      });
      if (error) return { ok: false, code: error.message };
      if (!data || typeof data !== "object") {
        return { ok: false, code: "unavailable" };
      }
      return { ok: true, facts: data as Record<string, unknown> };
    },
  };

  return handleR2Media(request, ports);
});
