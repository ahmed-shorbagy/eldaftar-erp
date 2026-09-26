import type { SqlFailureCode } from "./errors.ts";
import type {
  AuthLookup,
  CreateUserResult,
  PasswordProof,
  Reservation,
  SqlOutcome,
} from "./flow.ts";
import type { ProfileInput } from "./validate.ts";

export type BoundaryError = {
  message?: string;
  code?: string;
  status?: number;
  details?: string;
  hint?: string;
};

export type RawAuthUser = {
  id?: string;
  email?: string | null;
  phone?: string | null;
};

// Matches public.begin_owner_registration / complete_owner_registration.
// SQL raises its own exception names; this map is the HTTP vocabulary.
// Neither RPC accepts a password.
export const registrationContract = {
  beginRpc: "begin_owner_registration",
  completeRpc: "complete_owner_registration",
  beginArgs: {
    idempotencyKey: "p_request_key",
    ownerName: "p_owner_display_name",
    businessName: "p_business_name",
    email: "p_email",
    phone: "p_phone",
    governorateCode: "p_governorate_code",
  },
  completeArgs: {
    idempotencyKey: "p_request_key",
  },
} as const;

const sqlErrorMap: [string, SqlFailureCode][] = [
  ["request_key_reused", "request_key_reused"],
  ["identifier_already_registered", "identifier_taken"],
  ["registration_conflict", "identifier_taken"],
  ["identifier_taken", "identifier_taken"],
  ["auth_contact_mismatch", "registration_identity_mismatch"],
  ["registration_identity_mismatch", "registration_identity_mismatch"],
  ["invalid_registration", "invalid_input"],
  ["invalid_email", "invalid_input"],
  ["invalid_phone", "invalid_input"],
  ["invalid_governorate", "invalid_input"],
  ["invalid_input", "invalid_input"],
];

export function classifySqlError(error: BoundaryError): SqlFailureCode {
  const blob = `${error.message ?? ""}\n${error.details ?? ""}\n${
    error.hint ?? ""
  }\n${error.code ?? ""}`;
  for (const [name, code] of sqlErrorMap) {
    if (blob.includes(name)) return code;
  }
  return "unavailable";
}

export function classifyLookup(
  error: BoundaryError | null,
  user: RawAuthUser | null,
): AuthLookup {
  if (user?.id) {
    return {
      outcome: "found",
      user: {
        id: user.id,
        email: user.email ?? null,
        phone: user.phone ?? null,
      },
    };
  }
  if (error === null) return { outcome: "unknown" };
  if (
    error.status === 404 ||
    (error.code ?? "").toLowerCase() === "user_not_found"
  ) {
    return { outcome: "absent" };
  }
  return { outcome: "unknown" };
}

export function classifyCreateFailure(
  error: BoundaryError,
): "duplicate_identifier" | "unknown" {
  const code = (error.code ?? "").toLowerCase();
  if (code === "email_exists" || code === "phone_exists") {
    return "duplicate_identifier";
  }
  const message = (error.message ?? "").toLowerCase();
  if (message.includes("email address has already been registered")) {
    return "duplicate_identifier";
  }
  if (message.includes("phone") && message.includes("already")) {
    return "duplicate_identifier";
  }
  return "unknown";
}

export function isInvalidPassword(error: BoundaryError): boolean {
  const code = (error.code ?? "").toLowerCase();
  if (code === "invalid_credentials") return true;
  return (error.message ?? "").toLowerCase().includes(
    "invalid login credentials",
  );
}

const uuidV4 =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

export function parseReservation(data: unknown): SqlOutcome<Reservation> {
  const row = firstRow(data);
  if (row === null) return { ok: false, error: "unavailable" };
  const userId = uuidText(row.reserved_user_id);
  const ownerName = text(row.owner_display_name);
  const businessName = text(row.business_name);
  const email = text(row.email);
  const phone = text(row.phone);
  const authPhone = authDigits(phone, row.auth_phone);
  const governorateCode = text(row.governorate_code);
  const status = text(row.status);
  if (
    userId === null || ownerName === null || businessName === null ||
    email === null || phone === null || authPhone === null ||
    governorateCode === null
  ) {
    return { ok: false, error: "unavailable" };
  }
  const profile = {
    userId,
    ownerName,
    businessName,
    email,
    phone,
    authPhone,
    governorateCode,
  };
  if (status === "reserved") {
    return { ok: true, value: { status, shopId: null, ...profile } };
  }
  if (status === "completed") {
    const shopId = uuidText(row.shop_id);
    if (shopId === null) return { ok: false, error: "unavailable" };
    return { ok: true, value: { status, shopId, ...profile } };
  }
  return { ok: false, error: "unavailable" };
}

// complete_owner_registration returns the shop uuid, not a row.
export function parseShopId(
  data: unknown,
): SqlOutcome<{ shopId: string }> {
  const shopId = uuidText(data) ??
    (Array.isArray(data) ? uuidText(data[0]) : null);
  if (shopId === null) return { ok: false, error: "unavailable" };
  return { ok: true, value: { shopId } };
}

function authDigits(phone: string | null, raw: unknown): string | null {
  if (phone === null || !phone.startsWith("+")) return null;
  const expected = phone.slice(1);
  const source = text(raw) ?? expected;
  const digits = source.replace(/[^0-9]/g, "");
  return digits === expected ? digits : null;
}

function firstRow(data: unknown): Record<string, unknown> | null {
  let value = data;
  if (typeof value === "string") {
    try {
      value = JSON.parse(value);
    } catch {
      return null;
    }
  }
  if (Array.isArray(value)) value = value[0];
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return null;
  }
  return value as Record<string, unknown>;
}

function text(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function uuidText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const id = value.trim().toLowerCase();
  return uuidV4.test(id) ? id : null;
}

export interface RpcClient {
  rpc(
    fn: string,
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: BoundaryError | null }>;
}

export interface AdminAuthClient {
  auth: {
    admin: {
      getUserById(uid: string): Promise<{
        data: { user: RawAuthUser | null } | null;
        error: BoundaryError | null;
      }>;
      createUser(attributes: Record<string, unknown>): Promise<{
        data: { user: RawAuthUser | null } | null;
        error: BoundaryError | null;
      }>;
    };
  };
}

export interface PasswordAuthClient {
  auth: {
    signInWithPassword(
      credentials: { email: string; password: string } | {
        phone: string;
        password: string;
      },
    ): Promise<{
      data: { user: { id: string } | null } | null;
      error: BoundaryError | null;
    }>;
  };
}

export function createSqlPort(client: RpcClient): {
  begin(profile: ProfileInput): Promise<SqlOutcome<Reservation>>;
  complete(input: {
    idempotencyKey: string;
  }): Promise<SqlOutcome<{ shopId: string }>>;
} {
  return {
    async begin(profile: ProfileInput): Promise<SqlOutcome<Reservation>> {
      const { data, error } = await client.rpc(registrationContract.beginRpc, {
        [registrationContract.beginArgs.idempotencyKey]: profile.idempotencyKey,
        [registrationContract.beginArgs.ownerName]: profile.ownerName,
        [registrationContract.beginArgs.businessName]: profile.businessName,
        [registrationContract.beginArgs.email]: profile.email,
        [registrationContract.beginArgs.phone]: profile.phone,
        [registrationContract.beginArgs.governorateCode]:
          profile.governorateCode,
      });
      if (error) return { ok: false, error: classifySqlError(error) };
      return parseReservation(data);
    },
    async complete(input: { idempotencyKey: string }) {
      const { data, error } = await client.rpc(
        registrationContract.completeRpc,
        {
          [registrationContract.completeArgs.idempotencyKey]:
            input.idempotencyKey,
        },
      );
      if (error) return { ok: false, error: classifySqlError(error) };
      return parseShopId(data);
    },
  };
}

export function createAuthAdminPort(client: AdminAuthClient) {
  return {
    async getUserById(userId: string): Promise<AuthLookup> {
      const { data, error } = await client.auth.admin.getUserById(userId);
      return classifyLookup(error, data?.user ?? null);
    },
    async createUser(input: {
      id: string;
      email: string;
      phone: string;
      password: string;
      emailConfirm: true;
      phoneConfirm: true;
    }): Promise<CreateUserResult> {
      const { data, error } = await client.auth.admin.createUser({
        id: input.id,
        email: input.email,
        phone: input.phone,
        password: input.password,
        email_confirm: true,
        phone_confirm: true,
      });
      if (error) {
        if (data?.user?.id === input.id) return { outcome: "created" };
        return { outcome: classifyCreateFailure(error) };
      }
      if (data?.user?.id !== input.id) return { outcome: "unknown" };
      return { outcome: "created" };
    },
  };
}

export function createPasswordProofPort(
  createClient: () => PasswordAuthClient,
) {
  return {
    async verifyBoth(input: {
      email: string;
      phone: string;
      password: string;
      expectedUserId: string;
    }): Promise<PasswordProof> {
      const emailProof = await oneProof(
        createClient(),
        { email: input.email, password: input.password },
        input.expectedUserId,
      );
      if (emailProof !== "match") return emailProof;
      return await oneProof(
        createClient(),
        { phone: input.phone, password: input.password },
        input.expectedUserId,
      );
    },
  };
}

async function oneProof(
  client: PasswordAuthClient,
  credentials: { email: string; password: string } | {
    phone: string;
    password: string;
  },
  expectedUserId: string,
): Promise<PasswordProof> {
  const { data, error } = await client.auth.signInWithPassword(credentials);
  const userId = data?.user?.id ?? null;
  if (userId !== null) {
    return userId === expectedUserId ? "match" : "identity_mismatch";
  }
  if (error && isInvalidPassword(error)) return "invalid";
  return "unknown";
}
