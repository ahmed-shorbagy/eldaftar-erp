import {
  type AdminAuthClient,
  classifyCreateFailure,
  classifyLookup,
  classifySqlError,
  createAuthAdminPort,
  createPasswordProofPort,
  createSqlPort,
  parseReservation,
  type PasswordAuthClient,
  registrationContract,
  type RpcClient,
} from "./boundary.ts";
import { loadCallerKeys, resolveServerCredentials } from "./http.ts";

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

const userId = "11111111-1111-4111-8111-111111111111";
const shopId = "22222222-2222-4222-8222-222222222222";

Deno.test("auth and sql adapters map faults without forbidden calls", async () => {
  const calls: string[] = [];
  const captured: { value: Record<string, unknown> | null } = { value: null };
  const admin: AdminAuthClient & {
    auth: AdminAuthClient["auth"] & {
      signUp: () => void;
      signInWithOtp: () => void;
      verifyOtp: () => void;
      admin: AdminAuthClient["auth"]["admin"] & {
        listUsers: () => void;
        inviteUserByEmail: () => void;
        deleteUser: () => void;
      };
    };
  } = {
    auth: {
      admin: {
        getUserById: (id) => {
          calls.push(`getUserById:${id}`);
          return Promise.resolve({
            data: { user: null },
            error: {
              status: 404,
              code: "user_not_found",
              message: "User not found",
            },
          });
        },
        createUser: (attributes) => {
          calls.push("createUser");
          captured.value = attributes;
          return Promise.resolve({
            data: {
              user: {
                id: userId,
                email: "owner@example.com",
                phone: "+201012345678",
              },
            },
            error: null,
          });
        },
        listUsers: () => calls.push("listUsers"),
        inviteUserByEmail: () => calls.push("inviteUserByEmail"),
        deleteUser: () => calls.push("deleteUser"),
      },
      signUp: () => calls.push("signUp"),
      signInWithOtp: () => calls.push("signInWithOtp"),
      verifyOtp: () => calls.push("verifyOtp"),
    },
  };
  const auth = createAuthAdminPort(admin);
  same(await auth.getUserById(userId), { outcome: "absent" }, "absent");
  same(
    await auth.createUser({
      id: userId,
      email: "owner@example.com",
      phone: "+201012345678",
      password: "horse-battery",
      emailConfirm: true,
      phoneConfirm: true,
    }),
    { outcome: "created" },
    "created",
  );
  const created = captured.value;
  if (created === null) throw new Error("create payload");
  same(Object.keys(created).sort(), [
    "email",
    "email_confirm",
    "id",
    "password",
    "phone",
    "phone_confirm",
  ], "create attributes");
  same(created.email_confirm, true, "email confirm");
  same(created.phone_confirm, true, "phone confirm");
  same(created.id, userId, "custom id");
  assert(
    !calls.some((call) =>
      [
        "listUsers",
        "inviteUserByEmail",
        "deleteUser",
        "signUp",
        "signInWithOtp",
        "verifyOtp",
      ].includes(call)
    ),
    calls.join(","),
  );

  const serverError: AdminAuthClient = {
    auth: {
      admin: {
        getUserById: () =>
          Promise.resolve({
            data: { user: null },
            error: { status: 500, message: "boom" },
          }),
        createUser: () =>
          Promise.resolve({
            data: { user: null },
            error: { status: 500, message: "boom" },
          }),
      },
    },
  };
  const failing = createAuthAdminPort(serverError);
  same(
    await failing.getUserById(userId),
    { outcome: "unknown" },
    "unknown lookup",
  );
  same(
    await failing.createUser({
      id: userId,
      email: "owner@example.com",
      phone: "+201012345678",
      password: "horse-battery",
      emailConfirm: true,
      phoneConfirm: true,
    }),
    { outcome: "unknown" },
    "unknown create",
  );

  const duplicate: AdminAuthClient = {
    auth: {
      admin: {
        getUserById: () =>
          Promise.resolve({ data: { user: null }, error: null }),
        createUser: () =>
          Promise.resolve({
            data: { user: null },
            error: {
              status: 422,
              code: "email_exists",
              message:
                "A user with this email address has already been registered",
            },
          }),
      },
    },
  };
  same(
    await createAuthAdminPort(duplicate).createUser({
      id: userId,
      email: "owner@example.com",
      phone: "+201012345678",
      password: "horse-battery",
      emailConfirm: true,
      phoneConfirm: true,
    }),
    { outcome: "duplicate_identifier" },
    "duplicate",
  );

  const proofs: string[] = [];
  const token = "access-token-must-not-escape";
  const passwordClient = (): PasswordAuthClient => ({
    auth: {
      signInWithPassword: (credentials) => {
        proofs.push(
          "email" in credentials
            ? `email:${credentials.email}`
            : `phone:${credentials.phone}`,
        );
        return Promise.resolve({
          data: { user: { id: userId }, session: { access_token: token } } as {
            user: { id: string };
          },
          error: null,
        });
      },
    },
  });
  const proof = await createPasswordProofPort(passwordClient).verifyBoth({
    email: "owner@example.com",
    phone: "+201012345678",
    password: "horse-battery",
    expectedUserId: userId,
  });
  same(proof, "match", "proof");
  same(
    proofs,
    ["email:owner@example.com", "phone:+201012345678"],
    "both proofs",
  );
  assert(!JSON.stringify(proof).includes(token), "token returned");

  const wrongClient = (): PasswordAuthClient => ({
    auth: {
      signInWithPassword: () =>
        Promise.resolve({
          data: { user: null },
          error: {
            status: 400,
            code: "invalid_credentials",
            message: "Invalid login credentials",
          },
        }),
    },
  });
  same(
    await createPasswordProofPort(wrongClient).verifyBoth({
      email: "owner@example.com",
      phone: "+201012345678",
      password: "wrong-password",
      expectedUserId: userId,
    }),
    "invalid",
    "invalid password",
  );

  const rpcCalls: { fn: string; args: Record<string, unknown> }[] = [];
  const rpc: RpcClient = {
    rpc: (fn, args) => {
      rpcCalls.push({ fn, args });
      if (fn === registrationContract.beginRpc) {
        return Promise.resolve({
          data: [{
            status: "reserved",
            request_key: userId,
            reserved_user_id: userId,
            shop_id: null,
            owner_display_name: "منى",
            business_name: "محل",
            email: "owner@example.com",
            phone: "+201012345678",
            auth_phone: "201012345678",
            governorate_code: "EG-GZ",
          }],
          error: null,
        });
      }
      return Promise.resolve({ data: shopId, error: null });
    },
  };
  const sql = createSqlPort(rpc);
  const begun = await sql.begin({
    idempotencyKey: userId,
    ownerName: "منى",
    businessName: "محل",
    email: "owner@example.com",
    phone: "+201012345678",
    governorateCode: "EG-GZ",
  });
  assert(begun.ok, "begin ok");
  const completed = await sql.complete({ idempotencyKey: userId });
  assert(completed.ok && completed.value.shopId === shopId, "complete");
  same(rpcCalls[0].args, {
    p_request_key: userId,
    p_owner_display_name: "منى",
    p_business_name: "محل",
    p_email: "owner@example.com",
    p_phone: "+201012345678",
    p_governorate_code: "EG-GZ",
  }, "begin args");
  same(rpcCalls[1].args, { p_request_key: userId }, "complete args");
  assert(
    rpcCalls.every((call) => !JSON.stringify(call.args).includes("password")),
    "sql password",
  );
  same(rpcCalls.map((call) => call.fn), [
    "begin_owner_registration",
    "complete_owner_registration",
  ], "rpc names");

  const conflict: RpcClient = {
    rpc: () =>
      Promise.resolve({
        data: null,
        error: { code: "23505", message: "request_key_reused" },
      }),
  };
  const conflicted = await createSqlPort(conflict).begin({
    idempotencyKey: userId,
    ownerName: "منى",
    businessName: "محل",
    email: "owner@example.com",
    phone: "+201012345678",
    governorateCode: "EG-GZ",
  });
  same(conflicted, { ok: false, error: "request_key_reused" }, "sql conflict");
});

Deno.test("lookup and create classification fail closed", () => {
  same(classifyLookup({ status: 404, code: "user_not_found" }, null), {
    outcome: "absent",
  }, "404");
  same(classifyLookup({ status: 500, message: "unavailable" }, null), {
    outcome: "unknown",
  }, "500");
  same(classifyLookup(null, null), { outcome: "unknown" }, "empty");
  same(
    classifyLookup({ status: 404 }, {
      id: userId,
      email: "a@b.co",
      phone: "2010",
    }).outcome,
    "found",
    "user wins over 404",
  );
  same(
    classifyCreateFailure({
      code: "phone_exists",
      message: "Phone already registered",
    }),
    "duplicate_identifier",
    "phone",
  );
  same(
    classifyCreateFailure({
      code: "user_already_exists",
      message: "A user with this ID already exists",
    }),
    "unknown",
    "same id",
  );
  same(
    classifySqlError({
      message: "identifier_already_registered",
      code: "23505",
    }),
    "identifier_taken",
    "taken",
  );
  same(
    classifySqlError({ message: "auth_contact_mismatch", code: "42501" }),
    "registration_identity_mismatch",
    "contact mismatch",
  );
  same(
    classifySqlError({ message: "invalid_governorate", code: "22023" }),
    "invalid_input",
    "governorate",
  );
  same(
    classifySqlError({ message: "auth_user_not_ready", code: "P0001" }),
    "unavailable",
    "auth not ready",
  );
  same(
    classifySqlError({ code: "40001", message: "serialization_failure" }),
    "unavailable",
    "unknown sql",
  );
  same(parseReservation([{ status: "reserved" }]).ok, false, "incomplete row");
});

Deno.test("caller credentials accept publishable keys and reject secrets", () => {
  const env = {
    SUPABASE_URL: "http://127.0.0.1:54321",
    SUPABASE_ANON_KEY: "anon-key",
    SUPABASE_PUBLISHABLE_KEYS: JSON.stringify({
      default: "sb_publishable_default",
    }),
    SUPABASE_SERVICE_ROLE_KEY: "service-role-key",
    SUPABASE_SECRET_KEYS: JSON.stringify({ default: "sb_secret_default" }),
  };
  const keys = loadCallerKeys(env);
  assert(keys !== null, "keys");
  same(
    keys?.publishable,
    ["anon-key", "sb_publishable_default"],
    "publishable",
  );
  same(keys?.secret, ["service-role-key", "sb_secret_default"], "secret");
  const resolved = resolveServerCredentials(env);
  same(resolved?.serviceKey, "service-role-key", "admin key");
  same(resolved?.publishableKey, "anon-key", "password key");
  same(
    loadCallerKeys({ SUPABASE_PUBLISHABLE_KEYS: "not-json" }),
    null,
    "bad json",
  );
  same(
    resolveServerCredentials({
      SUPABASE_URL: "http://local",
      SUPABASE_ANON_KEY: "anon-key",
    }),
    null,
    "no service key",
  );
  same(
    resolveServerCredentials({
      SUPABASE_URL: "http://local",
      SUPABASE_ANON_KEY: "same-key",
      SUPABASE_SERVICE_ROLE_KEY: "same-key",
    }),
    null,
    "publishable must differ from service",
  );
});
