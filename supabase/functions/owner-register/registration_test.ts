import { registrationContract } from "./boundary.ts";
import { statusFor } from "./errors.ts";
import type {
  AuthAdminPort,
  AuthLookup,
  CreateUserResult,
  PasswordProof,
  PasswordProofPort,
  RegistrationPorts,
  RegistrationSqlPort,
  Reservation,
  SqlOutcome,
} from "./flow.ts";
import { type CallerKeys, handleOwnerRegister } from "./http.ts";
import {
  canonicalEgyptianPhone,
  egyptianGovernorateCodes,
  type ProfileInput,
} from "./validate.ts";

const publishableKey = "sb_publishable_owner_register_test";
const serviceKey = "sb_secret_owner_register_test";
const password = "horse-battery";

type Shop = {
  id: string;
  userId: string;
  ownerName: string;
  businessName: string;
  email: string;
  phone: string;
  governorateCode: string;
  timeZone: "Africa/Cairo";
  activation: "pending";
  entitlement: null;
  trial: null;
  memberships: { userId: string; role: "owner" }[];
  audit: { action: "owner_registered" }[];
};

type AuthUser = {
  id: string;
  email: string;
  phone: string;
  password: string;
};

type ReservationRow = ProfileInput & {
  userId: string;
  status: "reserved" | "completed";
  shopId: string | null;
};

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function same(actual: unknown, expected: unknown, message: string) {
  const left = JSON.stringify(actual);
  const right = JSON.stringify(expected);
  if (left !== right) {
    throw new Error(`${message}\nexpected ${right}\nactual   ${left}`);
  }
}

function uuid(n: number): string {
  return `00000000-0000-4000-8000-${n.toString(16).padStart(12, "0")}`;
}

function registrationBody(overrides: Record<string, unknown> = {}) {
  return {
    idempotency_key: uuid(1),
    owner_name: "منى أحمد",
    business_name: "محل الذهب",
    email: "Owner@Example.com",
    phone: "01012345678",
    governorate_code: "eg-gz",
    password,
    ...overrides,
  };
}

class ExternalBoundary {
  users: AuthUser[] = [];
  shops: Shop[] = [];
  reservations: ReservationRow[] = [];
  calls: string[] = [];
  sqlPayloads: unknown[] = [];
  createKeys: string[][] = [];
  logs: string[] = [];
  lookup: "normal" | "unknown" = "normal";
  create: "normal" | "unknown" | "duplicate" | "insert_then_unknown" = "normal";
  complete: "normal" | "fail" | "commit_then_lose" = "normal";
  enforceIdentifierUnique = true;
  fixedUserId: string | null = null;
  proof: "normal" | "other_user" = "normal";
  holdCreates = 0;
  private arrived = 0;
  private releaseCreates = () => {};
  private createGate = Promise.resolve();
  private sqlChain: Promise<unknown> = Promise.resolve();
  private authChain: Promise<unknown> = Promise.resolve();

  ports(): RegistrationPorts {
    const sql: RegistrationSqlPort = {
      begin: (profile) => this.lockSql(() => this.begin(profile)),
      complete: (input) => this.lockSql(() => this.completeReservation(input)),
    };
    const auth: AuthAdminPort = {
      getUserById: (userId) => this.getUserById(userId),
      createUser: (input) => this.createUser(input),
    };
    const passwords: PasswordProofPort = {
      verifyBoth: (input) => this.verifyBoth(input),
    };
    return { sql, auth, passwords };
  }

  keys(): CallerKeys {
    return { publishable: [publishableKey], secret: [serviceKey] };
  }

  private lockSql<T>(fn: () => T): Promise<T> {
    const run = this.sqlChain.then(fn, fn);
    this.sqlChain = run.then(() => undefined, () => undefined);
    return run;
  }

  private lockAuth<T>(fn: () => T): Promise<T> {
    const run = this.authChain.then(fn, fn);
    this.authChain = run.then(() => undefined, () => undefined);
    return run;
  }

  private begin(profile: ProfileInput): SqlOutcome<Reservation> {
    this.calls.push("begin");
    this.sqlPayloads.push({ ...profile });
    const existing = this.reservations.find((row) =>
      row.idempotencyKey === profile.idempotencyKey
    );
    if (existing) {
      if (!samePayload(existing, profile)) {
        return { ok: false, error: "request_key_reused" };
      }
      return { ok: true, value: this.reservationView(existing) };
    }
    if (this.enforceIdentifierUnique) {
      const emailTaken = this.reservations.some((row) =>
        row.email === profile.email
      );
      const phoneTaken = this.reservations.some((row) =>
        row.phone === profile.phone
      );
      if (emailTaken || phoneTaken) {
        return { ok: false, error: "identifier_taken" };
      }
    }
    const row: ReservationRow = {
      ...profile,
      userId: this.fixedUserId ?? crypto.randomUUID(),
      status: "reserved",
      shopId: null,
    };
    this.reservations.push(row);
    return { ok: true, value: this.reservationView(row) };
  }

  private completeReservation(input: {
    idempotencyKey: string;
  }): SqlOutcome<{ shopId: string }> {
    this.calls.push("complete");
    this.sqlPayloads.push({ ...input });
    const row = this.reservations.find((item) =>
      item.idempotencyKey === input.idempotencyKey
    );
    if (!row) return { ok: false, error: "unavailable" };
    if (row.status === "completed" && row.shopId) {
      return { ok: true, value: { shopId: row.shopId } };
    }
    if (this.complete === "fail") return { ok: false, error: "unavailable" };
    const shopId = crypto.randomUUID();
    this.shops.push({
      id: shopId,
      userId: row.userId,
      ownerName: row.ownerName,
      businessName: row.businessName,
      email: row.email,
      phone: row.phone,
      governorateCode: row.governorateCode,
      timeZone: "Africa/Cairo",
      activation: "pending",
      entitlement: null,
      trial: null,
      memberships: [{ userId: row.userId, role: "owner" }],
      audit: [{ action: "owner_registered" }],
    });
    row.status = "completed";
    row.shopId = shopId;
    if (this.complete === "commit_then_lose") {
      throw new Error("completion response lost");
    }
    return { ok: true, value: { shopId } };
  }

  private reservationView(row: ReservationRow): Reservation {
    return {
      status: row.status,
      userId: row.userId,
      shopId: row.shopId,
      ownerName: row.ownerName,
      businessName: row.businessName,
      email: row.email,
      phone: row.phone,
      authPhone: row.phone.startsWith("+") ? row.phone.slice(1) : row.phone,
      governorateCode: row.governorateCode,
    };
  }

  private getUserById(userId: string): Promise<AuthLookup> {
    this.calls.push("getUserById");
    if (this.lookup === "unknown") {
      return Promise.resolve({ outcome: "unknown" });
    }
    const user = this.users.find((item) => item.id === userId);
    if (!user) return Promise.resolve({ outcome: "absent" });
    return Promise.resolve({
      outcome: "found",
      user: { id: user.id, email: user.email, phone: user.phone },
    });
  }

  private async createUser(input: {
    id: string;
    email: string;
    phone: string;
    password: string;
    emailConfirm: true;
    phoneConfirm: true;
  }): Promise<CreateUserResult> {
    this.calls.push("createUser");
    this.createKeys.push(Object.keys(input).sort());
    if (this.holdCreates > 0) {
      this.arrived += 1;
      if (this.arrived >= this.holdCreates) this.releaseCreates();
      await this.createGate;
    }
    return await this.lockAuth(() => {
      const byId = this.users.find((user) => user.id === input.id);
      const emailOwner = this.users.find((user) => user.email === input.email);
      const phoneOwner = this.users.find((user) => user.phone === input.phone);
      if (this.create === "duplicate" || emailOwner || phoneOwner) {
        if (emailOwner?.id !== input.id || phoneOwner?.id !== input.id) {
          return { outcome: "duplicate_identifier" as const };
        }
      }
      if (byId) return { outcome: "unknown" as const };
      if (this.create === "unknown") return { outcome: "unknown" as const };
      this.users.push({
        id: input.id,
        email: input.email,
        phone: input.phone,
        password: input.password,
      });
      if (!input.emailConfirm || !input.phoneConfirm) {
        throw new Error("confirmation flags were not set");
      }
      if (this.create === "insert_then_unknown") return { outcome: "unknown" };
      return { outcome: "created" };
    });
  }

  private verifyBoth(input: {
    email: string;
    phone: string;
    password: string;
    expectedUserId: string;
  }): Promise<PasswordProof> {
    const byEmail = this.users.find((user) =>
      user.email.toLowerCase() === input.email.toLowerCase() &&
      user.password === input.password
    );
    const byPhone = this.users.find((user) =>
      user.phone.replace(/^\+/, "") === input.phone.replace(/^\+/, "") &&
      user.password === input.password
    );
    this.calls.push("signInEmail");
    this.calls.push("signInPhone");
    if (this.proof === "other_user") {
      return Promise.resolve("identity_mismatch");
    }
    if (!byEmail || !byPhone) return Promise.resolve("invalid");
    if (
      byEmail.id !== input.expectedUserId || byPhone.id !== input.expectedUserId
    ) {
      return Promise.resolve("identity_mismatch");
    }
    if (byEmail.id !== byPhone.id) return Promise.resolve("identity_mismatch");
    return Promise.resolve("match");
  }

  armCreateBarrier(parties: number) {
    this.holdCreates = parties;
    this.createGate = new Promise((resolve) => {
      this.releaseCreates = resolve;
    });
  }

  authenticate(kind: "email" | "phone", identifier: string, secret: string) {
    const user = this.users.find((item) => {
      const contact = kind === "email"
        ? item.email.toLowerCase()
        : item.phone.replace(/^\+/, "");
      const presented = kind === "email"
        ? identifier.toLowerCase()
        : identifier.replace(/^\+/, "");
      return contact === presented && item.password === secret;
    });
    return user?.id ?? null;
  }
}

function samePayload(row: ReservationRow, profile: ProfileInput): boolean {
  return row.ownerName === profile.ownerName &&
    row.businessName === profile.businessName &&
    row.email === profile.email &&
    row.phone === profile.phone &&
    row.governorateCode === profile.governorateCode;
}

async function post(
  boundary: ExternalBoundary,
  body: unknown,
  options: {
    method?: string;
    key?: string | null;
    contentType?: string | null;
    raw?: BodyInit;
  } = {},
) {
  const headers = new Headers();
  if (options.key !== null) {
    headers.set("apikey", options.key ?? publishableKey);
  }
  if (options.contentType !== null) {
    headers.set("content-type", options.contentType ?? "application/json");
  }
  const method = options.method ?? "POST";
  const hasBody = method !== "GET" && method !== "OPTIONS";
  const response = await handleOwnerRegister(
    new Request("http://registration.local/owner-register", {
      method,
      headers,
      body: hasBody ? options.raw ?? JSON.stringify(body) : undefined,
    }),
    {
      ports: boundary.ports(),
      keys: boundary.keys(),
      log: (code) => boundary.logs.push(code),
    },
  );
  const text = await response.text();
  return {
    status: response.status,
    text,
    json: text.length === 0
      ? null
      : JSON.parse(text) as Record<string, unknown>,
    headers: response.headers,
  };
}

function assertNoEffects(boundary: ExternalBoundary, responseText: string) {
  same(boundary.users, [], "auth users");
  same(boundary.shops, [], "shops");
  same(boundary.reservations, [], "reservations");
  assert(!boundary.calls.includes("begin"), "begin was called");
  assert(!boundary.calls.includes("createUser"), "createUser was called");
  assert(!responseText.includes(password), "password echoed");
  assert(!responseText.includes(serviceKey), "service key echoed");
}

function assertClosedSuccess(
  boundary: ExternalBoundary,
  payload: { text: string },
) {
  assert(boundary.users.length === 1, "one auth user");
  assert(boundary.shops.length === 1, "one shop");
  const shop = boundary.shops[0];
  const user = boundary.users[0];
  same(shop.activation, "pending", "activation");
  same(shop.timeZone, "Africa/Cairo", "time zone");
  same(shop.entitlement, null, "entitlement");
  same(shop.trial, null, "trial");
  same(shop.memberships, [{ userId: user.id, role: "owner" }], "membership");
  same(shop.audit, [{ action: "owner_registered" }], "audit");
  same(user.password, password, "password");
  same(
    boundary.authenticate("email", user.email, password),
    user.id,
    "email login",
  );
  same(
    boundary.authenticate("phone", user.phone, password),
    user.id,
    "phone login",
  );
  assert(
    boundary.authenticate("email", user.email, "wrong-password") === null,
    "wrong email password",
  );
  assert(!payload.text.includes(password), "password in response");
  assert(!payload.text.includes(user.email), "email in response");
  assert(!payload.text.includes(user.phone), "phone in response");
  assert(!payload.text.includes(serviceKey), "service key in response");
  assert(
    boundary.logs.every((line) => !line.includes(password)),
    "password in log",
  );
  assert(
    boundary.sqlPayloads.every((item) =>
      !JSON.stringify(item).includes(password)
    ),
    "password in sql",
  );
  assert(
    boundary.sqlPayloads.every((item) =>
      !JSON.stringify(item).includes("password")
    ),
    "password field in sql",
  );
  const allowed = new Set([
    "begin",
    "complete",
    "getUserById",
    "createUser",
    "signInEmail",
    "signInPhone",
  ]);
  assert(
    boundary.calls.every((call) => allowed.has(call)),
    `unexpected call ${boundary.calls}`,
  );
  assert(
    boundary.calls.includes("signInEmail") &&
      boundary.calls.includes("signInPhone"),
    "both identifiers",
  );
  assert(
    boundary.createKeys.every((keys) => !keys.includes("password_hash")),
    "password hash stored",
  );
  assert(
    boundary.createKeys.every((keys) => !keys.includes("user_metadata")),
    "user metadata",
  );
}

Deno.test("full registration returns one pending shop and both identifiers", async () => {
  const boundary = new ExternalBoundary();
  const response = await post(boundary, registrationBody());
  same(response.status, 200, "status");
  same(Object.keys(response.json ?? {}).sort(), [
    "shop_id",
    "status",
    "user_id",
  ], "response keys");
  same(response.json?.status, "completed", "completed");
  same(response.json?.user_id, boundary.users[0].id, "user id");
  same(response.json?.shop_id, boundary.shops[0].id, "shop id");
  same(boundary.users[0].email, "owner@example.com", "canonical email");
  same(boundary.users[0].phone, "201012345678", "auth phone");
  same(boundary.shops[0].phone, "+201012345678", "profile phone");
  same(boundary.shops[0].governorateCode, "EG-GZ", "governorate");
  same(boundary.shops[0].ownerName, "منى أحمد", "owner");
  same(boundary.shops[0].businessName, "محل الذهب", "business");
  assertClosedSuccess(boundary, response);
  same(response.headers.get("access-control-allow-origin"), "*", "cors");
  same(response.headers.get("cache-control"), "no-store", "cache");
});

Deno.test("missing or blank required fields do not reserve or create", async () => {
  const fields = [
    "idempotency_key",
    "owner_name",
    "business_name",
    "email",
    "phone",
    "governorate_code",
    "password",
  ];
  for (const field of fields) {
    for (const value of [undefined, null, "", "   "]) {
      const boundary = new ExternalBoundary();
      const body = registrationBody();
      if (value === undefined) delete body[field as keyof typeof body];
      else body[field as keyof typeof body] = value as never;
      const response = await post(boundary, body);
      same(response.status, 400, field);
      same(response.json, { error: "invalid_input" }, field);
      assertNoEffects(boundary, response.text);
    }
  }
});

Deno.test("phones, emails, and governorates are canonical or rejected with no effects", async () => {
  const acceptedPhones = [
    "01012345678",
    "01112345678",
    "01212345678",
    "01512345678",
    "+201012345678",
    "00201012345678",
    "(010) 1234-5678",
    "+20 10 1234 5678",
    "0020 10 1234 5678",
  ];
  for (const [index, phone] of acceptedPhones.entries()) {
    const boundary = new ExternalBoundary();
    const response = await post(
      boundary,
      registrationBody({
        idempotency_key: uuid(100 + index),
        email: `phone${index}@shop.example`,
        phone,
      }),
    );
    same(response.status, 200, phone);
    const canonical = canonicalEgyptianPhone(phone);
    same(boundary.shops[0].phone, canonical, phone);
    same(boundary.users[0].phone, canonical?.slice(1) ?? "", phone);
    same(boundary.shops.length, 1, phone);
  }

  const rejectedPhones = [
    "01312345678",
    "01412345678",
    "01612345678",
    "01712345678",
    "01812345678",
    "01912345678",
    "0101234567",
    "010123456789",
    "+201312345678",
    "+2001012345678",
    "02012345678",
    "01012a45678",
    "010.1234.5678",
    "+9661012345678",
    "1012345678",
  ];
  for (const phone of rejectedPhones) {
    const boundary = new ExternalBoundary();
    const response = await post(boundary, registrationBody({ phone }));
    same(response.status, 400, phone);
    assertNoEffects(boundary, response.text);
  }

  const boundary = new ExternalBoundary();
  const emailResponse = await post(
    boundary,
    registrationBody({
      idempotency_key: uuid(80),
      email: "  Owner.Name+tag@Example.com ",
      phone: "01000000001",
    }),
  );
  same(emailResponse.status, 200, "email");
  same(
    boundary.users[0].email,
    "owner.name+tag@example.com",
    "email canonical",
  );

  for (
    const email of [
      "a@b",
      "a@b.c",
      "not-an-email",
      "a..b@example.com",
      "owner@example",
      "own er@example.com",
      `${"a".repeat(64)}@${"b".repeat(250)}.com`,
    ]
  ) {
    const rejected = new ExternalBoundary();
    const response = await post(rejected, registrationBody({ email }));
    same(response.status, 400, email);
    assertNoEffects(rejected, response.text);
  }

  for (const [index, code] of egyptianGovernorateCodes.entries()) {
    const world = new ExternalBoundary();
    const response = await post(
      world,
      registrationBody({
        idempotency_key: uuid(200 + index),
        email: `gov${index}@shop.example`,
        phone: `010${index.toString().padStart(8, "0")}`,
        governorate_code: ` ${code.toLowerCase()} `,
      }),
    );
    same(response.status, 200, code);
    same(world.shops[0].governorateCode, code, code);
    same(world.shops[0].activation, "pending", code);
    same(world.shops[0].entitlement, null, code);
  }
  same(egyptianGovernorateCodes.length, 27, "governorate count");
  for (const code of ["Giza", "Cairo", "EG-XX", "US-NY", ""]) {
    const rejected = new ExternalBoundary();
    const response = await post(
      rejected,
      registrationBody({ governorate_code: code }),
    );
    same(response.status, 400, code);
    assertNoEffects(rejected, response.text);
  }
});

Deno.test("duplicate email or phone does not attach a second user or shop", async () => {
  const boundary = new ExternalBoundary();
  const first = await post(boundary, registrationBody());
  same(first.status, 200, "first");
  const emailDup = await post(
    boundary,
    registrationBody({
      idempotency_key: uuid(2),
      phone: "01112345678",
      business_name: "محل آخر",
    }),
  );
  same(emailDup.status, 409, "email");
  same(emailDup.json, { error: "identifier_taken" }, "email error");
  const phoneDup = await post(
    boundary,
    registrationBody({
      idempotency_key: uuid(3),
      email: "other@example.com",
      phone: "+20 10 1234 5678",
    }),
  );
  same(phoneDup.status, 409, "phone");
  same(phoneDup.json, { error: "identifier_taken" }, "phone error");
  same(boundary.users.length, 1, "users");
  same(boundary.shops.length, 1, "shops");
  assert(
    !emailDup.text.includes(password) && !phoneDup.text.includes(password),
    "echo",
  );

  const raced = new ExternalBoundary();
  raced.enforceIdentifierUnique = false;
  const original = await post(
    raced,
    registrationBody({ idempotency_key: uuid(4) }),
  );
  same(original.status, 200, "original");
  raced.create = "duplicate";
  const second = await post(
    raced,
    registrationBody({
      idempotency_key: uuid(5),
      business_name: "محل آخر",
    }),
  );
  same(second.status, 409, "auth duplicate");
  same(second.json, { error: "identifier_taken" }, "auth duplicate error");
  same(raced.users.length, 1, "raced users");
  same(raced.shops.length, 1, "raced shops");
  same(raced.users[0].id, original.json?.user_id, "original user kept");
});

Deno.test("replay uses the same user and shop; a wrong password changes nothing", async () => {
  const boundary = new ExternalBoundary();
  const created = await post(
    boundary,
    registrationBody({
      idempotency_key: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
    }),
  );
  const replay = await post(
    boundary,
    registrationBody({
      idempotency_key: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    }),
  );
  same(replay.status, 200, "replay");
  same(replay.json, created.json, "same result");
  same(boundary.users.length, 1, "users");
  same(boundary.shops.length, 1, "shops");
  same(
    boundary.calls.filter((call) => call === "createUser").length,
    1,
    "single create",
  );

  const wrong = await post(
    boundary,
    registrationBody({
      idempotency_key: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      password: "other-password",
    }),
  );
  same(wrong.status, 401, "wrong");
  same(wrong.json, { error: "invalid_credentials" }, "wrong error");
  same(statusFor("invalid_credentials"), 401, "status map");
  same(boundary.users[0].password, password, "password unchanged");
  same(boundary.shops.length, 1, "shops unchanged");
  same(
    boundary.authenticate("email", "owner@example.com", password),
    boundary.users[0].id,
    "email still works",
  );
  same(
    boundary.authenticate("phone", "+201012345678", password),
    boundary.users[0].id,
    "phone still works",
  );
});

Deno.test("invalid passwords, keys, and bodies have no effects", async () => {
  const tooShort = "1234567";
  const bytes72 = "é".repeat(36);
  const bytes74 = "é".repeat(37);
  const cases: Record<string, unknown>[] = [
    registrationBody({ password: tooShort }),
    registrationBody({ password: "        " }),
    registrationBody({ password: bytes74 }),
    registrationBody({ password: "a".repeat(73) }),
    registrationBody({
      idempotency_key: "aaaaaaaa-aaaa-1aaa-8aaa-aaaaaaaaaaaa",
    }),
    registrationBody({ idempotency_key: "not-a-uuid" }),
    registrationBody({ owner_name: "x".repeat(121) }),
  ];
  for (const body of cases) {
    const boundary = new ExternalBoundary();
    const response = await post(boundary, body);
    same(
      response.status,
      400,
      JSON.stringify(body.password ?? body.idempotency_key),
    );
    assertNoEffects(boundary, response.text);
  }

  const boundary = new ExternalBoundary();
  const response = await post(
    boundary,
    registrationBody({
      idempotency_key: uuid(9),
      email: "longpass@shop.example",
      phone: "01000000009",
      password: bytes72,
    }),
  );
  same(response.status, 200, "72 bytes");
  same(boundary.users.length, 1, "user");
  same(boundary.users[0].password, bytes72, "stored password");
  assert(!response.text.includes(bytes72), "echo");
  same(new TextEncoder().encode(bytes72).length, 72, "byte length");
});

Deno.test("an unknown user lookup never creates an auth user", async () => {
  const boundary = new ExternalBoundary();
  boundary.lookup = "unknown";
  const response = await post(boundary, registrationBody());
  same(response.status, 503, "status");
  same(response.json, { error: "unavailable" }, "error");
  same(boundary.users, [], "users");
  same(boundary.shops, [], "shops");
  assert(boundary.calls.includes("begin"), "reservation may exist");
  assert(!boundary.calls.includes("createUser"), "create was attempted");
  assert(!boundary.calls.includes("complete"), "complete was attempted");

  boundary.lookup = "normal";
  const retry = await post(boundary, registrationBody());
  same(retry.status, 200, "retry");
  same(boundary.users.length, 1, "one user after retry");
  same(boundary.shops.length, 1, "one shop after retry");
});

Deno.test("a lost auth create response reconciles the reserved user", async () => {
  const boundary = new ExternalBoundary();
  boundary.create = "insert_then_unknown";
  const response = await post(boundary, registrationBody());
  same(response.status, 200, "status");
  same(boundary.users.length, 1, "users");
  same(boundary.shops.length, 1, "shops");
  same(
    boundary.calls.filter((call) => call === "createUser").length,
    1,
    "one create",
  );
  same(
    boundary.calls.filter((call) => call === "getUserById").length,
    2,
    "reconcile lookup",
  );
  assertClosedSuccess(boundary, response);
});

Deno.test("a lost completion response retries onto the same shop", async () => {
  const boundary = new ExternalBoundary();
  boundary.complete = "commit_then_lose";
  const lost = await post(boundary, registrationBody());
  same(lost.status, 503, "lost status");
  same(lost.json, { error: "unavailable" }, "lost error");
  same(boundary.users.length, 1, "user");
  same(boundary.shops.length, 1, "shop committed");
  same(boundary.shops[0].memberships.length, 1, "membership committed");
  const shopId = boundary.shops[0].id;

  boundary.complete = "normal";
  const replay = await post(boundary, registrationBody());
  same(replay.status, 200, "replay");
  same(replay.json?.shop_id, shopId, "same shop");
  same(replay.json?.user_id, boundary.users[0].id, "same user");
  same(boundary.users.length, 1, "still one user");
  same(boundary.shops.length, 1, "still one shop");
  same(boundary.users[0].password, password, "password");
});

Deno.test("partial completion failure replays one shop and rejects a wrong password", async () => {
  const boundary = new ExternalBoundary();
  boundary.complete = "fail";
  const failed = await post(boundary, registrationBody());
  same(failed.status, 503, "failed");
  same(boundary.users.length, 1, "auth user kept");
  same(boundary.shops, [], "no shop yet");
  same(boundary.users[0].password, password, "password");

  const wrong = await post(
    boundary,
    registrationBody({ password: "not-the-password" }),
  );
  same(wrong.status, 401, "wrong retry");
  same(boundary.shops, [], "still no shop");
  same(boundary.users[0].password, password, "password unchanged");
  same(
    boundary.calls.filter((call) => call === "createUser").length,
    1,
    "no second user",
  );

  boundary.complete = "normal";
  const replay = await post(boundary, registrationBody());
  same(replay.status, 200, "replay");
  same(boundary.shops.length, 1, "one shop");
  same(boundary.shops[0].activation, "pending", "pending");
  same(boundary.shops[0].entitlement, null, "no entitlement");
  same(boundary.users.length, 1, "one user");
  same(boundary.users[0].password, password, "same password");
});

Deno.test("concurrent same-key registrations create one user and one shop", async () => {
  const boundary = new ExternalBoundary();
  boundary.armCreateBarrier(2);
  const responses = await Promise.race([
    Promise.all([
      post(boundary, registrationBody()),
      post(boundary, registrationBody()),
    ]),
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error("concurrent registration hung")), 2000)
    ),
  ]);
  same(responses[0].status, 200, "first status");
  same(responses[1].status, 200, "second status");
  same(responses[0].json, responses[1].json, "same response");
  same(boundary.users.length, 1, "users");
  same(boundary.shops.length, 1, "shops");
  same(boundary.shops[0].memberships.length, 1, "memberships");
  same(boundary.users[0].password, password, "password");
});

Deno.test("concurrent different keys with the same email keep one shop", async () => {
  const boundary = new ExternalBoundary();
  const responses = await Promise.all([
    post(boundary, registrationBody({ idempotency_key: uuid(1) })),
    post(
      boundary,
      registrationBody({
        idempotency_key: uuid(2),
        business_name: "محل آخر",
      }),
    ),
  ]);
  const statuses = responses.map((response) => response.status).sort();
  same(statuses, [200, 409], "one success and one conflict");
  same(boundary.users.length, 1, "users");
  same(boundary.shops.length, 1, "shops");
  assert(
    responses.some((response) => response.json?.error === "identifier_taken"),
    "conflict",
  );
});

Deno.test("a reserved id that already belongs to other contacts fails closed", async () => {
  const boundary = new ExternalBoundary();
  const reservedId = uuid(50);
  boundary.fixedUserId = reservedId;
  boundary.users.push({
    id: reservedId,
    email: "someone@example.com",
    phone: "+201112345678",
    password: "existing-password",
  });
  const response = await post(boundary, registrationBody());
  same(response.status, 422, "status");
  same(response.json, { error: "registration_identity_mismatch" }, "error");
  same(statusFor("registration_identity_mismatch"), 422, "status map");
  same(boundary.shops, [], "no shop");
  same(boundary.users.length, 1, "no new user");
  same(boundary.users[0].password, "existing-password", "password unchanged");
  assert(!boundary.calls.includes("createUser"), "did not create");
  assert(!boundary.calls.includes("complete"), "did not complete");
  assert(!boundary.calls.includes("signInEmail"), "did not sign in");
});

Deno.test("an auth phone without a plus sign still matches the reserved user", async () => {
  const boundary = new ExternalBoundary();
  const reservedId = uuid(51);
  boundary.fixedUserId = reservedId;
  boundary.users.push({
    id: reservedId,
    email: "Owner@Example.com",
    phone: "201012345678",
    password,
  });
  const response = await post(boundary, registrationBody());
  same(response.status, 200, "status");
  same(boundary.users.length, 1, "users");
  same(boundary.shops.length, 1, "shops");
  same(boundary.shops[0].phone, "+201012345678", "profile phone");
  assert(
    !boundary.calls.includes("createUser"),
    "did not create a second user",
  );
});

Deno.test("a password proof for a different user does not complete", async () => {
  const boundary = new ExternalBoundary();
  boundary.proof = "other_user";
  const response = await post(boundary, registrationBody());
  same(response.status, 422, "status");
  same(response.json, { error: "registration_identity_mismatch" }, "error");
  same(boundary.shops, [], "no shop");
  same(boundary.users.length, 1, "auth user remains without membership");
  same(boundary.users[0].password, password, "password unchanged");
});

Deno.test("the same key with a different profile is rejected", async () => {
  const boundary = new ExternalBoundary();
  const created = await post(boundary, registrationBody());
  same(created.status, 200, "created");
  const reused = await post(
    boundary,
    registrationBody({ business_name: "اسم مختلف" }),
  );
  same(reused.status, 409, "status");
  same(reused.json, { error: "request_key_reused" }, "error");
  same(statusFor("request_key_reused"), 409, "status map");
  same(boundary.shops.length, 1, "shops");
  same(boundary.users.length, 1, "users");
  same(boundary.shops[0].businessName, "محل الذهب", "original business");
});

Deno.test("http method, content type, body size, and caller key are enforced", async () => {
  const boundary = new ExternalBoundary();
  const options = await post(boundary, undefined, {
    method: "OPTIONS",
    key: null,
    contentType: null,
  });
  same(options.status, 204, "options");
  same(options.text, "", "options body");
  same(options.headers.get("access-control-allow-origin"), "*", "options cors");
  assert(
    options.headers.get("access-control-allow-headers")?.includes("apikey"),
    "apikey header",
  );
  assertNoEffects(boundary, options.text);

  for (const method of ["GET", "PUT", "DELETE", "PATCH"]) {
    const response = await post(new ExternalBoundary(), undefined, {
      method,
      contentType: null,
    });
    same(response.status, 405, method);
    same(response.json, { error: "invalid_input" }, method);
  }

  const textBody = await post(boundary, registrationBody(), {
    contentType: "text/plain",
  });
  same(textBody.status, 400, "content type");
  const huge = await post(boundary, undefined, {
    raw: `{"owner_name":"${"x".repeat(maxPadding())}"}`,
  });
  same(huge.status, 400, "body size");
  same(huge.json, { error: "invalid_input" }, "body error");
  const malformed = await post(boundary, undefined, { raw: "{" });
  same(malformed.status, 400, "json");
  assert(
    boundary.users.length === 0 && boundary.shops.length === 0,
    "http failures created state",
  );

  const missingKey = await post(new ExternalBoundary(), registrationBody(), {
    key: null,
  });
  same(missingKey.status, 401, "missing key");
  same(missingKey.json, { error: "invalid_credentials" }, "missing key error");
  const secret = await post(new ExternalBoundary(), registrationBody(), {
    key: serviceKey,
  });
  same(secret.status, 401, "secret key");
  assert(!secret.text.includes(serviceKey), "secret echoed");
  same(secret.json, { error: "invalid_credentials" }, "secret error");

  const misconfigured = await handleOwnerRegister(
    new Request("http://registration.local/owner-register", {
      method: "POST",
      headers: { apikey: publishableKey, "content-type": "application/json" },
      body: JSON.stringify(registrationBody()),
    }),
    {
      ports: new ExternalBoundary().ports(),
      keys: { publishable: [], secret: [] },
    },
  );
  same(misconfigured.status, 503, "misconfigured");
});

function maxPadding(): number {
  return 16 * 1024;
}

Deno.test("oversized streamed body is cancelled before registration", async () => {
  const boundary = new ExternalBoundary();
  let cancelled = false;
  const body = new ReadableStream<Uint8Array>({
    pull(controller) {
      controller.enqueue(new Uint8Array(17 * 1024));
    },
    cancel() {
      cancelled = true;
    },
  });
  const response = await handleOwnerRegister(
    new Request("http://registration.local/owner-register", {
      method: "POST",
      headers: { apikey: publishableKey, "content-type": "application/json" },
      body,
    }),
    {
      ports: boundary.ports(),
      keys: { publishable: [publishableKey], secret: [serviceKey] },
    },
  );
  same(response.status, 400, "oversized body rejected");
  assert(cancelled, "unbounded stream was not cancelled");
  same(boundary.calls, [], "oversized input reached Auth or SQL");
});

Deno.test("registration rpc contract carries no password", () => {
  same(registrationContract.beginRpc, "begin_owner_registration", "begin rpc");
  same(
    registrationContract.completeRpc,
    "complete_owner_registration",
    "complete rpc",
  );
  same(Object.values(registrationContract.beginArgs).sort(), [
    "p_business_name",
    "p_email",
    "p_governorate_code",
    "p_owner_display_name",
    "p_phone",
    "p_request_key",
  ], "begin args");
  same(Object.values(registrationContract.completeArgs), [
    "p_request_key",
  ], "complete args");
  assert(
    !JSON.stringify(registrationContract).includes("password"),
    "password arg",
  );
  same(statusFor("invalid_input"), 400, "400");
  same(statusFor("identifier_taken"), 409, "409");
  same(statusFor("unavailable"), 503, "503");
});
