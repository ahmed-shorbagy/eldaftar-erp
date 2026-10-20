import { assertEquals, assertStringIncludes } from "@std/assert";
import { amzDateNow, encodePath, presign, rfc3986 } from "./sign.ts";

// AWS-documented SigV4 presigned GET example. Proves the signing chain matches
// the reference implementation independent of Cloudflare R2.
// https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html
Deno.test("matches the AWS presigned GET reference vector", async () => {
  const url = await presign({
    method: "GET",
    host: "examplebucket.s3.amazonaws.com",
    canonicalUri: "/test.txt",
    region: "us-east-1",
    service: "s3",
    accessKeyId: "AKIAIOSFODNN7EXAMPLE",
    secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    amzDate: "20130524T000000Z",
    expiresSeconds: 86400,
  });
  assertStringIncludes(
    url,
    "X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404",
  );
  assertStringIncludes(url, "X-Amz-Credential=AKIAIOSFODNN7EXAMPLE%2F20130524");
  assertStringIncludes(url, "X-Amz-SignedHeaders=host");
});

Deno.test("path encoding keeps slashes but escapes segments", () => {
  assertEquals(
    encodePath("/bucket/shop-image/a b/c.jpg"),
    "/bucket/shop-image/a%20b/c.jpg",
  );
  assertEquals(rfc3986("a/b c"), "a%2Fb%20c");
});

Deno.test("amz date formats to compact UTC", () => {
  assertEquals(
    amzDateNow(new Date("2026-10-20T12:34:56.789Z")),
    "20261020T123456Z",
  );
});
