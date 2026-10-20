import { createClient } from "@supabase/supabase-js";
import {
  loadCallerKeys,
  resolveServerCredentials,
} from "../owner-register/http.ts";
import { handleR2Media, type R2MediaPorts } from "./handler.ts";
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

  const ports: R2MediaPorts = {
    async ownedShop(token) {
      const caller = createClient(credentials.url, keys.publishable[0], {
        ...options,
        global: {
          ...options.global,
          headers: { Authorization: `Bearer ${token}` },
        },
      });
      const { data, error } = await caller.rpc("list_my_shop_accounts");
      if (error || !Array.isArray(data) || data.length === 0) return null;
      const owner = data.find((row) =>
        row && typeof row === "object" && row.member_role === "owner"
      ) as { shop_id?: unknown } | undefined;
      return owner && typeof owner.shop_id === "string" ? owner.shop_id : null;
    },
    presign({ method, objectKey, mime, expiresSeconds }) {
      return presign({
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
    },
  };

  return handleR2Media(request, ports);
});
