import { type RegistrationErrorCode, statusFor } from "./errors.ts";
import { registerOwner, type RegistrationPorts } from "./flow.ts";

export const maxBodyBytes = 16 * 1024;

const corsHeaders: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers":
    "authorization, apikey, content-type, x-client-info",
  "access-control-max-age": "86400",
  "cache-control": "no-store",
};

export type CallerKeys = {
  publishable: readonly string[];
  secret: readonly string[];
};

export type OwnerRegisterDeps = {
  ports: RegistrationPorts;
  keys: CallerKeys;
  log?: (code: RegistrationErrorCode) => void;
};

export async function handleOwnerRegister(
  request: Request,
  deps: OwnerRegisterDeps,
): Promise<Response> {
  const method = request.method.toUpperCase();
  if (method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (method !== "POST") {
    return jsonError("invalid_input", 405, deps.log);
  }

  const gate = authorizeCaller(request, deps.keys);
  if (gate === "misconfigured") return jsonError("unavailable", 503, deps.log);
  if (gate === "reject") return jsonError("invalid_credentials", 401, deps.log);

  const contentLength = request.headers.get("content-length");
  if (contentLength !== null && Number(contentLength) > maxBodyBytes) {
    return jsonError("invalid_input", 400, deps.log);
  }
  const media = (request.headers.get("content-type") ?? "").split(";")[0]
    .trim()
    .toLowerCase();
  if (media !== "application/json") {
    return jsonError("invalid_input", 400, deps.log);
  }

  let bytes: Uint8Array;
  try {
    bytes = await readBoundedBody(request);
  } catch {
    return jsonError("invalid_input", 400, deps.log);
  }
  if (bytes.byteLength > maxBodyBytes) {
    return jsonError("invalid_input", 400, deps.log);
  }

  let body: unknown;
  try {
    body = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } catch {
    return jsonError("invalid_input", 400, deps.log);
  }

  try {
    const result = await registerOwner(body, deps.ports);
    if (!result.ok) {
      return jsonError(result.error, statusFor(result.error), deps.log);
    }
    return json(200, {
      status: "completed",
      user_id: result.userId,
      shop_id: result.shopId,
    });
  } catch {
    return jsonError("unavailable", 503, deps.log);
  }
}

async function readBoundedBody(request: Request): Promise<Uint8Array> {
  if (request.body === null) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBodyBytes) {
        await reader.cancel();
        throw new Error("body_too_large");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const body = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    body.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return body;
}

export function authorizeCaller(
  request: Request,
  keys: CallerKeys,
): "ok" | "reject" | "misconfigured" {
  const publishable = keys.publishable.filter((key) =>
    key.length > 0 && !keys.secret.some((secret) => safeEqual(secret, key))
  );
  if (publishable.length === 0) return "misconfigured";
  const presented = request.headers.get("apikey") ?? "";
  if (presented.length === 0) return "reject";
  if (keys.secret.some((secret) => safeEqual(secret, presented))) {
    return "reject";
  }
  return publishable.some((key) => safeEqual(key, presented)) ? "ok" : "reject";
}

export function loadCallerKeys(
  env: Record<string, string | undefined>,
): CallerKeys | null {
  try {
    const publishable = [
      env.SUPABASE_ANON_KEY,
      env.SUPABASE_PUBLISHABLE_KEY,
      ...namedKeys(env.SUPABASE_PUBLISHABLE_KEYS),
    ].filter((key): key is string => typeof key === "string" && key.length > 0);
    const secret = [
      env.SUPABASE_SERVICE_ROLE_KEY,
      env.SUPABASE_SECRET_KEY,
      ...namedKeys(env.SUPABASE_SECRET_KEYS),
    ].filter((key): key is string => typeof key === "string" && key.length > 0);
    return { publishable, secret };
  } catch {
    return null;
  }
}

export function resolveServerCredentials(
  env: Record<string, string | undefined>,
): {
  url: string;
  serviceKey: string;
  publishableKey: string;
} | null {
  const keys = loadCallerKeys(env);
  if (
    keys === null || env.SUPABASE_URL === undefined ||
    env.SUPABASE_URL.length === 0
  ) {
    return null;
  }
  const publishable = keys.publishable.find((key) =>
    !keys.secret.some((secret) => secret === key)
  );
  const serviceKey = keys.secret[0];
  if (publishable === undefined || serviceKey === undefined) return null;
  return { url: env.SUPABASE_URL, serviceKey, publishableKey: publishable };
}

function namedKeys(raw: string | undefined): string[] {
  if (raw === undefined || raw.trim().length === 0) return [];
  const parsed = JSON.parse(raw) as unknown;
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("invalid key set");
  }
  return Object.values(parsed).filter((value): value is string =>
    typeof value === "string" && value.length > 0
  );
}

function safeEqual(left: string, right: string): boolean {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  const length = Math.max(a.length, b.length);
  let diff = a.length ^ b.length;
  for (let i = 0; i < length; i++) diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return diff === 0;
}

function jsonError(
  error: RegistrationErrorCode,
  status: number,
  log?: (code: RegistrationErrorCode) => void,
): Response {
  log?.(error);
  return json(status, { error });
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "content-type": "application/json; charset=utf-8",
    },
  });
}
