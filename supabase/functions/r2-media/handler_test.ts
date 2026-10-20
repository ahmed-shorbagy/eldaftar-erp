import { assertEquals } from "@std/assert";
import {
  type FetchedObject,
  handleR2Media,
  mimeMatches,
  type R2MediaPorts,
  type RecordInput,
  sha256Hex,
} from "./handler.ts";

const shop = "a1222222-2222-4222-8222-222222222222";
const user = "a1111111-1111-4111-8111-111111111111";
const day = "d1222222-2222-4222-8222-222222222222";
const client = "c1222222-2222-4222-8222-222222222222";
const sha = "a".repeat(64);
const png = new Uint8Array([
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  1,
  2,
  3,
]);
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);

function ports(overrides: Partial<R2MediaPorts> = {}): R2MediaPorts {
  return {
    owner: () => Promise.resolve({ shopId: shop, userId: user }),
    presign: (args) =>
      Promise.resolve(`https://r2.example/${args.objectKey}?signed=1`),
    fetchObject: () => Promise.resolve({ status: "missing" }),
    recordObject: (input) =>
      Promise.resolve({
        ok: true,
        facts: { object_key: input.objectKey, sha256: input.sha256 },
      }),
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

function serving(bytes: Uint8Array): Partial<R2MediaPorts> {
  return {
    fetchObject: (): Promise<FetchedObject> =>
      Promise.resolve({ status: "ok", bytes }),
  };
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

Deno.test("invoice logos refuse webp at upload", async () => {
  const response = await handleR2Media(
    post({
      kind: "invoice_logo",
      op: "upload",
      sha256: sha,
      mime: "image/webp",
    }),
    ports(),
  );
  assertEquals(response.status, 400);
});

Deno.test("note uploads keep the shop/day/object name", async () => {
  const response = await handleR2Media(
    post({
      kind: "note_image",
      op: "upload",
      object_name: `${shop}/${day}/${client}.webp`,
      mime: "image/webp",
    }),
    ports(),
  );
  assertEquals(response.status, 200);
  const json = await response.json();
  assertEquals(json.object_key, `note-image/${shop}/${day}/${client}.webp`);
});

Deno.test("note uploads refuse another shop or a wrong extension", async () => {
  const other = "b1222222-2222-4222-8222-222222222222";
  for (
    const [name, mime] of [
      [`${other}/${day}/${client}.jpg`, "image/jpeg"],
      [`${shop}/${day}/${client}.png`, "image/jpeg"],
      [`${shop}/${day}/../${client}.jpg`, "image/jpeg"],
    ]
  ) {
    const response = await handleR2Media(
      post({ kind: "note_image", op: "upload", object_name: name, mime }),
      ports(),
    );
    assertEquals(response.status, 400, name);
  }
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

Deno.test("confirm reports a missing object", async () => {
  const response = await handleR2Media(
    post({
      kind: "invoice_logo",
      op: "confirm",
      object_key: `invoice-logo/${shop}/${sha}.png`,
    }),
    ports(),
  );
  assertEquals(response.status, 404);
  assertEquals((await response.json()).code, "media_missing");
});

Deno.test("confirm rejects bytes whose hash differs from the key", async () => {
  let recorded = false;
  const response = await handleR2Media(
    post({
      kind: "invoice_logo",
      op: "confirm",
      object_key: `invoice-logo/${shop}/${sha}.png`,
    }),
    ports({
      ...serving(png),
      recordObject: () => {
        recorded = true;
        return Promise.resolve({ ok: true, facts: {} });
      },
    }),
  );
  assertEquals(response.status, 400);
  assertEquals((await response.json()).code, "media_rejected");
  assertEquals(recorded, false);
});

Deno.test("confirm rejects bytes that are not the declared type", async () => {
  const key = `invoice-logo/${shop}/${await sha256Hex(jpeg)}.png`;
  const response = await handleR2Media(
    post({ kind: "invoice_logo", op: "confirm", object_key: key }),
    ports(serving(jpeg)),
  );
  assertEquals(response.status, 400);
});

Deno.test("confirm records verified facts for the caller", async () => {
  const digest = await sha256Hex(png);
  const key = `invoice-logo/${shop}/${digest}.png`;
  let seen: RecordInput | null = null;
  const response = await handleR2Media(
    post({ kind: "invoice_logo", op: "confirm", object_key: key }),
    ports({
      ...serving(png),
      recordObject: (input) => {
        seen = input;
        return Promise.resolve({ ok: true, facts: { object_key: key } });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals((await response.json()).object_key, key);
  const input = seen as RecordInput | null;
  assertEquals(input?.actor, user);
  assertEquals(input?.shopId, shop);
  assertEquals(input?.byteSize, png.length);
  assertEquals(input?.sha256, digest);
  assertEquals(typeof input?.imageBase64, "string");
});

Deno.test("confirm sends note images without bytes", async () => {
  const key = `note-image/${shop}/${day}/${client}.jpg`;
  let seen: RecordInput | null = null;
  const response = await handleR2Media(
    post({ kind: "note_image", op: "confirm", object_key: key }),
    ports({
      ...serving(jpeg),
      recordObject: (input) => {
        seen = input;
        return Promise.resolve({ ok: true, facts: {} });
      },
    }),
  );
  assertEquals(response.status, 200);
  assertEquals((seen as RecordInput | null)?.imageBase64, null);
});

Deno.test("confirm refuses another shop's key", async () => {
  const other = "b1222222-2222-4222-8222-222222222222";
  const response = await handleR2Media(
    post({
      kind: "note_image",
      op: "confirm",
      object_key: `note-image/${other}/${day}/${client}.jpg`,
    }),
    ports(serving(jpeg)),
  );
  assertEquals(response.status, 403);
});

Deno.test("confirm maps registry refusals and hides unknown errors", async () => {
  const key = `note-image/${shop}/${day}/${client}.jpg`;
  const mismatch = await handleR2Media(
    post({ kind: "note_image", op: "confirm", object_key: key }),
    ports({
      ...serving(jpeg),
      recordObject: () =>
        Promise.resolve({ ok: false, code: "media_mismatch" }),
    }),
  );
  assertEquals(mismatch.status, 400);
  assertEquals((await mismatch.json()).code, "media_mismatch");
  const unknown = await handleR2Media(
    post({ kind: "note_image", op: "confirm", object_key: key }),
    ports({
      ...serving(jpeg),
      recordObject: () =>
        Promise.resolve({ ok: false, code: "relation does not exist" }),
    }),
  );
  assertEquals(unknown.status, 503);
});

Deno.test("confirm rejects oversized objects", async () => {
  const key = `note-image/${shop}/${day}/${client}.jpg`;
  const response = await handleR2Media(
    post({ kind: "note_image", op: "confirm", object_key: key }),
    ports({
      fetchObject: () => Promise.resolve({ status: "too_large" }),
    }),
  );
  assertEquals(response.status, 400);
});

Deno.test("magic bytes match only their declared type", () => {
  assertEquals(mimeMatches(png, "image/png"), true);
  assertEquals(mimeMatches(png, "image/jpeg"), false);
  assertEquals(mimeMatches(jpeg, "image/jpeg"), true);
  const webp = new TextEncoder().encode("RIFF\0\0\0\0WEBPVP8 ");
  assertEquals(mimeMatches(webp, "image/webp"), true);
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
    ports({ owner: () => Promise.resolve(null) }),
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
