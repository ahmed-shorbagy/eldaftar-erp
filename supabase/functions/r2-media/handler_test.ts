import { assertEquals } from "jsr:@std/assert";
import { handleR2Media, type R2MediaPorts } from "./handler.ts";

const shop = "a1222222-2222-4222-8222-222222222222";
const sha = "a".repeat(64);

function ports(overrides: Partial<R2MediaPorts> = {}): R2MediaPorts {
  return {
    ownedShop: () => Promise.resolve(shop),
    presign: (args) =>
      Promise.resolve(`https://r2.example/${args.objectKey}?signed=1`),
    ...overrides,
  };
}

function post(body: unknown, bearer = "Bearer token"): Request {
  return new Request("https://fn.example/r2-media", {
    method: "POST",
    headers: { authorization: bearer, "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

Deno.test("upload derives a content-addressed shop-scoped key", async () => {
  const response = await handleR2Media(
    post({ kind: "shop_image", op: "upload", sha256: sha, mime: "image/jpeg" }),
    ports(),
  );
  assertEquals(response.status, 200);
  const json = await response.json();
  assertEquals(json.object_key, `shop-image/${shop}/${sha}.jpg`);
  assertEquals(json.method, "PUT");
});

Deno.test("read refuses a key from another shop", async () => {
  const other = "b1222222-2222-4222-8222-222222222222";
  const response = await handleR2Media(
    post({
      kind: "shop_image",
      op: "read",
      object_key: `shop-image/${other}/${sha}.jpg`,
    }),
    ports(),
  );
  assertEquals(response.status, 403);
});

Deno.test("read signs an owned key", async () => {
  const response = await handleR2Media(
    post({
      kind: "shop_image",
      op: "read",
      object_key: `shop-image/${shop}/${sha}.jpg`,
    }),
    ports(),
  );
  assertEquals(response.status, 200);
  const json = await response.json();
  assertEquals(typeof json.url, "string");
});

Deno.test("missing bearer is unauthenticated", async () => {
  const response = await handleR2Media(
    post(
      { kind: "shop_image", op: "upload", sha256: sha, mime: "image/jpeg" },
      "",
    ),
    ports(),
  );
  assertEquals(response.status, 401);
});

Deno.test("unresolved shop is unauthenticated", async () => {
  const response = await handleR2Media(
    post({ kind: "shop_image", op: "upload", sha256: sha, mime: "image/jpeg" }),
    ports({ ownedShop: () => Promise.resolve(null) }),
  );
  assertEquals(response.status, 401);
});

Deno.test("bad mime is rejected", async () => {
  const response = await handleR2Media(
    post({ kind: "shop_image", op: "upload", sha256: sha, mime: "image/gif" }),
    ports(),
  );
  assertEquals(response.status, 400);
});
