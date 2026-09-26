import {
  failure,
  type RegistrationResult,
  type SqlFailureCode,
} from "./errors.ts";
import {
  emailsMatch,
  phonesMatch,
  type ProfileInput,
  profileOf,
  validateRegistration,
} from "./validate.ts";

export type AuthUserRecord = {
  id: string;
  email: string | null;
  phone: string | null;
};

export type AuthLookup =
  | { outcome: "absent" }
  | { outcome: "found"; user: AuthUserRecord }
  | { outcome: "unknown" };

export type CreateUserResult =
  | { outcome: "created" }
  | { outcome: "duplicate_identifier" }
  | { outcome: "unknown" };

export type PasswordProof =
  | "match"
  | "invalid"
  | "identity_mismatch"
  | "unknown";

export type Reservation = {
  status: "reserved" | "completed";
  userId: string;
  shopId: string | null;
  ownerName: string;
  businessName: string;
  email: string;
  phone: string;
  authPhone: string;
  governorateCode: string;
};

export type SqlOutcome<T> =
  | { ok: true; value: T }
  | { ok: false; error: SqlFailureCode };

export interface AuthAdminPort {
  getUserById(userId: string): Promise<AuthLookup>;
  createUser(input: {
    id: string;
    email: string;
    phone: string;
    password: string;
    emailConfirm: true;
    phoneConfirm: true;
  }): Promise<CreateUserResult>;
}

export interface PasswordProofPort {
  verifyBoth(input: {
    email: string;
    phone: string;
    password: string;
    expectedUserId: string;
  }): Promise<PasswordProof>;
}

export interface RegistrationSqlPort {
  begin(profile: ProfileInput): Promise<SqlOutcome<Reservation>>;
  complete(input: {
    idempotencyKey: string;
  }): Promise<SqlOutcome<{ shopId: string }>>;
}

export type RegistrationPorts = {
  auth: AuthAdminPort;
  passwords: PasswordProofPort;
  sql: RegistrationSqlPort;
};

export async function registerOwner(
  body: unknown,
  ports: RegistrationPorts,
): Promise<RegistrationResult> {
  const input = validateRegistration(body);
  if (input === null) return failure("invalid_input");
  const profile = profileOf(input);

  let begun: SqlOutcome<Reservation>;
  try {
    begun = await ports.sql.begin(profile);
  } catch {
    return failure("unavailable");
  }
  if (!begun.ok) return failure(begun.error);
  const reservation = begun.value;
  if (!sameProfile(reservation, profile)) {
    return failure("registration_identity_mismatch");
  }

  let lookup: AuthLookup;
  try {
    lookup = await ports.auth.getUserById(reservation.userId);
  } catch {
    return failure("unavailable");
  }
  if (lookup.outcome === "unknown") return failure("unavailable");

  if (lookup.outcome === "absent") {
    const created = await createOrReconcile(ports, reservation, input.password);
    if (created !== "ready") return failure(created);
  } else if (!contactsMatch(lookup.user, reservation)) {
    return failure("registration_identity_mismatch");
  }

  let proof: PasswordProof;
  try {
    proof = await ports.passwords.verifyBoth({
      email: reservation.email,
      phone: reservation.authPhone,
      password: input.password,
      expectedUserId: reservation.userId,
    });
  } catch {
    return failure("unavailable");
  }
  if (proof === "invalid") return failure("invalid_credentials");
  if (proof === "identity_mismatch") {
    return failure("registration_identity_mismatch");
  }
  if (proof === "unknown") return failure("unavailable");

  if (reservation.status === "completed") {
    if (reservation.shopId === null) return failure("unavailable");
    return {
      ok: true,
      userId: reservation.userId,
      shopId: reservation.shopId,
    };
  }

  let completed: SqlOutcome<{ shopId: string }>;
  try {
    completed = await ports.sql.complete({
      idempotencyKey: profile.idempotencyKey,
    });
  } catch {
    return failure("unavailable");
  }
  if (!completed.ok) return failure(completed.error);
  return {
    ok: true,
    userId: reservation.userId,
    shopId: completed.value.shopId,
  };
}

async function createOrReconcile(
  ports: RegistrationPorts,
  reservation: Reservation,
  password: string,
): Promise<
  | "ready"
  | "identifier_taken"
  | "unavailable"
  | "registration_identity_mismatch"
> {
  let created: CreateUserResult;
  try {
    created = await ports.auth.createUser({
      id: reservation.userId,
      email: reservation.email,
      phone: reservation.authPhone,
      password,
      emailConfirm: true,
      phoneConfirm: true,
    });
  } catch {
    created = { outcome: "unknown" };
  }
  if (created.outcome === "created") return "ready";

  let again: AuthLookup;
  try {
    again = await ports.auth.getUserById(reservation.userId);
  } catch {
    return "unavailable";
  }
  if (again.outcome === "unknown") return "unavailable";
  if (again.outcome === "found") {
    return contactsMatch(again.user, reservation)
      ? "ready"
      : "registration_identity_mismatch";
  }
  if (
    created.outcome === "duplicate_identifier" &&
    reservation.status !== "completed"
  ) {
    return "identifier_taken";
  }
  return "unavailable";
}

function sameProfile(reservation: Reservation, profile: ProfileInput): boolean {
  return reservation.ownerName === profile.ownerName &&
    reservation.businessName === profile.businessName &&
    reservation.email === profile.email &&
    reservation.phone === profile.phone &&
    reservation.governorateCode === profile.governorateCode &&
    reservation.userId.length > 0;
}

function contactsMatch(
  user: AuthUserRecord,
  reservation: Reservation,
): boolean {
  return user.id === reservation.userId &&
    emailsMatch(user.email, reservation.email) &&
    phonesMatch(user.phone, reservation.phone);
}
