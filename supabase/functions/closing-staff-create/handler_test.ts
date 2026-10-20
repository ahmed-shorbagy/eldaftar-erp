import assert from "node:assert/strict";
import { handleStaffCreation, type StaffCreationPorts } from "./handler.ts";
import { staffPasswordProof } from "./password_proof.ts";
const owner = "a1900000-0000-4000-8000-000000000001";
const reserved = "a1900000-0000-4000-8000-000000000002";
const staff = "a1900000-0000-4000-8000-000000000003";
const key = "a1900000-0000-4000-8000-000000000004";
const input = {
  idempotency_key: key,
  name: "موظف تجريبي",
  phone: "201000000001",
  password: "test-password",
};
const request = (body: unknown = input, token = "owner-token") =>
  new Request("https://example.test/closing-staff-create", {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });
function fixture() {
  let exists = false,
    created = 0,
    completed = 0,
    prepared = 0,
    failAfterCreate = false,
    storedProof: string | null = null;
  const ports: StaffCreationPorts = {
    user: async (token) => token === "owner-token" ? owner : null,
    proof: async (_owner, _key, password) =>
      password === input.password ? "a".repeat(64) : "b".repeat(64),
    prepare: async (_token, args) => {
      prepared++;
      if (storedProof !== null && storedProof !== args.p_password_proof) {
        throw new Error("payload_mismatch");
      }
      storedProof = args.p_password_proof as string;
      return {
        shop_id: staff,
        owner_user_id: owner,
        reserved_user_id: reserved,
        phone: input.phone,
        staff_id: completed ? staff : null,
      };
    },
    identity: async (id) => exists ? { id, phone: input.phone } : null,
    create: async (id, phone, password) => {
      assert.equal(id, reserved);
      assert.equal(phone, input.phone);
      assert.equal(password, input.password);
      created++;
      exists = true;
      if (failAfterCreate) {
        failAfterCreate = false;
        throw new Error("timeout");
      }
    },
    complete: async (actor, idempotency) => {
      assert.equal(actor, owner);
      assert.equal(idempotency, key);
      completed++;
      return { ok: true, staff_id: staff, replayed: completed > 1 };
    },
  };
  return {
    ports,
    state: () => ({ created, completed, prepared }),
    timeout: () => {
      failAfterCreate = true;
    },
  };
}
Deno.test("unknown Auth-create outcome resumes the reserved identity without a duplicate account", async () => {
  const f = fixture();
  f.timeout();
  assert.equal((await handleStaffCreation(request(), f.ports)).status, 503);
  assert.equal((await handleStaffCreation(request(), f.ports)).status, 200);
  assert.deepEqual(f.state(), { created: 1, completed: 1, prepared: 2 });
  assert.equal((await handleStaffCreation(request(), f.ports)).status, 200);
  assert.equal(f.state().created, 1);
});
Deno.test("a retry with another password cannot finalize the reserved account", async () => {
  const f = fixture();
  f.timeout();
  await handleStaffCreation(request(), f.ports);
  const response = await handleStaffCreation(
    request({ ...input, password: "another-password" }),
    f.ports,
  );
  assert.equal(response.status, 409);
  assert.equal((await response.json()).code, "payload_mismatch");
  assert.equal(f.state().completed, 0);
});
Deno.test("unauthenticated and forbidden callers never create Auth users", async () => {
  const f = fixture();
  assert.equal(
    (await handleStaffCreation(request(input, "wrong"), f.ports)).status,
    401,
  );
  f.ports.prepare = async () => {
    throw new Error("forbidden");
  };
  assert.equal((await handleStaffCreation(request(), f.ports)).status, 403);
  assert.equal(f.state().created, 0);
});
Deno.test("invalid and oversized bodies do not reach the reservation or Auth administrator", async () => {
  for (
    const invalid of [
      { ...input, role: "owner" },
      { ...input, password: "short" },
      { ...input, idempotency_key: "bad" },
      { ...input, name: "\u0000اسم" },
      { ...input, phone: "bad" },
      { ...input, name: "x".repeat(5000) },
    ]
  ) {
    const f = fixture();
    assert.equal(
      (await handleStaffCreation(request(invalid), f.ports)).status,
      400,
    );
    assert.equal(f.state().created, 0);
    assert.equal(f.state().prepared, 0);
  }
});
Deno.test("response contains only receipt fields, never credentials or request verifier", async () => {
  const f = fixture(), response = await handleStaffCreation(request(), f.ports);
  const text = await response.text();
  assert.equal(response.status, 200);
  assert.deepEqual(Object.keys(JSON.parse(text)).sort(), [
    "ok",
    "replayed",
    "staff_id",
  ]);
  assert(!text.includes(input.password));
  assert(!text.includes("a".repeat(64)));
  assert.equal(response.headers.get("cache-control"), "no-store");
});
Deno.test("retry verifier is stable and isolated by owner, key and exact password", async () => {
  const first = await staffPasswordProof(owner, key, "كلمة مرور تجريبية");
  assert.match(first, /^[a-f0-9]{64}$/);
  assert.equal(
    await staffPasswordProof(owner, key, "كلمة مرور تجريبية"),
    first,
  );
  assert.notEqual(
    await staffPasswordProof(reserved, key, "كلمة مرور تجريبية"),
    first,
  );
  assert.notEqual(
    await staffPasswordProof(owner, reserved, "كلمة مرور تجريبية"),
    first,
  );
  assert.notEqual(
    await staffPasswordProof(owner, key, "كلمة مرور تجريبية "),
    first,
  );
});
