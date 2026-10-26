import assert from "node:assert/strict";
import { handleShopStaffCreation, type ShopStaffPorts } from "./handler.ts";

const owner = "a1900000-0000-4000-8000-000000000001";
const reserved = "a1900000-0000-4000-8000-000000000002";
const member = "a1900000-0000-4000-8000-000000000003";
const key = "a1900000-0000-4000-8000-000000000004";
const input = {
  idempotency_key: key,
  name: "موظف تجريبي",
  phone: "201000000001",
  password: "test-password",
  role: "employee",
  grants: ["sale", "purchase"],
};
const request = (body: unknown = input, token = "owner-token") =>
  new Request("https://example.test/shop-staff-create", {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  });

function fixture() {
  let exists = false, created = 0, completed = 0, prepared = 0;
  const ports: ShopStaffPorts = {
    user: async (token) => (token === "owner-token" ? owner : null),
    proof: async () => "a".repeat(64),
    prepare: async () => {
      prepared++;
      return {
        shop_id: member,
        owner_user_id: owner,
        reserved_user_id: reserved,
        phone: input.phone,
        member_user_id: completed ? member : null,
      };
    },
    identity: async (id) => (exists ? { id, phone: input.phone } : null),
    create: async (id, phone, password) => {
      assert.equal(id, reserved);
      assert.equal(phone, input.phone);
      assert.equal(password, input.password);
      created++;
      exists = true;
    },
    complete: async (actor, idempotency) => {
      assert.equal(actor, owner);
      assert.equal(idempotency, key);
      completed++;
      return { ok: true, user_id: member, replayed: completed > 1 };
    },
  };
  return { ports, state: () => ({ created, completed, prepared }) };
}

Deno.test("creates staff and completes", async () => {
  const f = fixture();
  const response = await handleShopStaffCreation(request(), f.ports);
  assert.equal(response.status, 200);
  assert.deepEqual(f.state(), { created: 1, completed: 1, prepared: 1 });
});

Deno.test("rejects bad grants", async () => {
  const f = fixture();
  const response = await handleShopStaffCreation(
    request({ ...input, grants: ["sale", "close_day"] }),
    f.ports,
  );
  assert.equal(response.status, 400);
});
