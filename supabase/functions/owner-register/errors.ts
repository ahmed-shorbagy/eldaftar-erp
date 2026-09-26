export const registrationErrors = [
  "invalid_input",
  "identifier_taken",
  "request_key_reused",
  "registration_identity_mismatch",
  "invalid_credentials",
  "unavailable",
] as const;

export type RegistrationErrorCode = (typeof registrationErrors)[number];

export type SqlFailureCode = Exclude<
  RegistrationErrorCode,
  "invalid_credentials"
>;

export type RegistrationFailure = {
  ok: false;
  error: RegistrationErrorCode;
};

export type RegistrationSuccess = {
  ok: true;
  userId: string;
  shopId: string;
};

export type RegistrationResult = RegistrationSuccess | RegistrationFailure;

export function failure(error: RegistrationErrorCode): RegistrationFailure {
  return { ok: false, error };
}

// 409 is the idempotency / uniqueness conflict. 422 is a reserved Auth row
// whose contacts do not match this registration. 401 is the password proof.
export function statusFor(error: RegistrationErrorCode): number {
  switch (error) {
    case "invalid_input":
      return 400;
    case "identifier_taken":
      return 409;
    case "request_key_reused":
      return 409;
    case "registration_identity_mismatch":
      return 422;
    case "invalid_credentials":
      return 401;
    case "unavailable":
      return 503;
  }
}
