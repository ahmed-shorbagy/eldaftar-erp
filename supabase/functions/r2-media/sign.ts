// Minimal AWS Signature Version 4 query presigner for S3-compatible stores
// (Cloudflare R2). No external dependencies: Web Crypto only. The R2 secret
// access key stays inside the Edge Function environment and is never returned
// to any client. Only short-lived presigned URLs leave this module.

const encoder = new TextEncoder();

export type PresignInput = {
  method: "GET" | "PUT";
  host: string;
  // Already path-style, e.g. "/bucket/shop-image/<shop>/<sha>.jpg".
  canonicalUri: string;
  region: string;
  service: string;
  accessKeyId: string;
  secretAccessKey: string;
  amzDate: string; // YYYYMMDDTHHMMSSZ
  expiresSeconds: number;
  // Extra signed-by-query parameters (not headers), e.g. content type hints.
  extraQuery?: Record<string, string>;
};

/// RFC 3986 encoding. S3 canonical requests require the unreserved set to stay
/// literal and everything else percent-encoded with uppercase hex.
export function rfc3986(value: string): string {
  return [...encoder.encode(value)]
    .map((byte) => {
      const char = String.fromCharCode(byte);
      if (/[A-Za-z0-9\-_.~]/.test(char)) return char;
      return "%" + byte.toString(16).toUpperCase().padStart(2, "0");
    })
    .join("");
}

/// Encode a path while preserving "/" between segments.
export function encodePath(path: string): string {
  return path
    .split("/")
    .map((segment) => rfc3986(segment))
    .join("/");
}

// Copy into a fresh ArrayBuffer so Web Crypto's BufferSource typing is exact.
function toBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(copy).set(bytes);
  return copy;
}

async function sha256Hex(message: Uint8Array | string): Promise<string> {
  const bytes = typeof message === "string" ? encoder.encode(message) : message;
  const digest = await crypto.subtle.digest("SHA-256", toBuffer(bytes));
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function hmac(key: Uint8Array, message: string): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    toBuffer(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    cryptoKey,
    toBuffer(encoder.encode(message)),
  );
  return new Uint8Array(signature);
}

async function signingKey(
  secret: string,
  dateStamp: string,
  region: string,
  service: string,
): Promise<Uint8Array> {
  const kDate = await hmac(encoder.encode("AWS4" + secret), dateStamp);
  const kRegion = await hmac(kDate, region);
  const kService = await hmac(kRegion, service);
  return hmac(kService, "aws4_request");
}

function canonicalQuery(params: Record<string, string>): string {
  return Object.keys(params)
    .sort()
    .map((key) => `${rfc3986(key)}=${rfc3986(params[key])}`)
    .join("&");
}

/// Returns a fully signed presigned URL for the given method and object path.
export async function presign(input: PresignInput): Promise<string> {
  const dateStamp = input.amzDate.slice(0, 8);
  const credentialScope =
    `${dateStamp}/${input.region}/${input.service}/aws4_request`;
  const params: Record<string, string> = {
    "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
    "X-Amz-Credential": `${input.accessKeyId}/${credentialScope}`,
    "X-Amz-Date": input.amzDate,
    "X-Amz-Expires": String(input.expiresSeconds),
    "X-Amz-SignedHeaders": "host",
    ...(input.extraQuery ?? {}),
  };
  const query = canonicalQuery(params);
  const canonicalHeaders = `host:${input.host}\n`;
  const canonicalRequest = [
    input.method,
    encodePath(input.canonicalUri),
    query,
    canonicalHeaders,
    "host",
    "UNSIGNED-PAYLOAD",
  ].join("\n");
  const stringToSign = [
    "AWS4-HMAC-SHA256",
    input.amzDate,
    credentialScope,
    await sha256Hex(canonicalRequest),
  ].join("\n");
  const key = await signingKey(
    input.secretAccessKey,
    dateStamp,
    input.region,
    input.service,
  );
  const signatureBytes = await hmac(key, stringToSign);
  const signature = [...signatureBytes]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  return `https://${input.host}${encodePath(input.canonicalUri)}?${query}` +
    `&X-Amz-Signature=${signature}`;
}

export function amzDateNow(now: Date): string {
  return now.toISOString().replace(/[:-]|\.\d{3}/g, "");
}
