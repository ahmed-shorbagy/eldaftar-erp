// ISO 3166-2:EG. The registration RPC must accept this same set.
export const egyptianGovernorateCodes = [
  "EG-ALX",
  "EG-ASN",
  "EG-AST",
  "EG-BA",
  "EG-BH",
  "EG-BNS",
  "EG-C",
  "EG-DK",
  "EG-DT",
  "EG-FYM",
  "EG-GH",
  "EG-GZ",
  "EG-IS",
  "EG-JS",
  "EG-KB",
  "EG-KFS",
  "EG-KN",
  "EG-LX",
  "EG-MN",
  "EG-MNF",
  "EG-MT",
  "EG-PTS",
  "EG-SHG",
  "EG-SHR",
  "EG-SIN",
  "EG-SUZ",
  "EG-WAD",
] as const;

const governorateSet = new Set<string>(egyptianGovernorateCodes);

const uuidV4 =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

const nameMaxCodePoints = 120;

export type RegistrationInput = {
  idempotencyKey: string;
  ownerName: string;
  businessName: string;
  email: string;
  phone: string;
  governorateCode: string;
  password: string;
};

export type ProfileInput = Omit<RegistrationInput, "password">;

export function validateRegistration(body: unknown): RegistrationInput | null {
  if (body === null || typeof body !== "object" || Array.isArray(body)) {
    return null;
  }
  const record = body as Record<string, unknown>;
  const idempotencyKey = uuidV4Field(record.idempotency_key);
  const ownerName = personName(record.owner_name);
  const businessName = personName(record.business_name);
  const email = canonicalEmail(record.email);
  const phone = canonicalEgyptianPhone(record.phone);
  const governorateCode = governorate(record.governorate_code);
  const password = passwordField(record.password);
  if (
    idempotencyKey === null || ownerName === null || businessName === null ||
    email === null || phone === null || governorateCode === null ||
    password === null
  ) {
    return null;
  }
  return {
    idempotencyKey,
    ownerName,
    businessName,
    email,
    phone,
    governorateCode,
    password,
  };
}

export function profileOf(input: RegistrationInput): ProfileInput {
  return {
    idempotencyKey: input.idempotencyKey,
    ownerName: input.ownerName,
    businessName: input.businessName,
    email: input.email,
    phone: input.phone,
    governorateCode: input.governorateCode,
  };
}

function uuidV4Field(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const id = value.trim().toLowerCase();
  return uuidV4.test(id) ? id : null;
}

function personName(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const name = value.trim();
  if (name.length === 0 || [...name].length > nameMaxCodePoints) return null;
  if (hasControlCharacter(name)) return null;
  return name;
}

function hasControlCharacter(value: string): boolean {
  for (const character of value) {
    const code = character.codePointAt(0) ?? 0;
    if (code <= 31 || code === 127) return true;
  }
  return false;
}

function governorate(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const code = value.trim().toUpperCase();
  return governorateSet.has(code) ? code : null;
}

export function canonicalEmail(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const email = value.trim().toLowerCase();
  if (email.length === 0 || email.length > 320) return null;
  const parts = email.split("@");
  if (parts.length !== 2) return null;
  const [local, domain] = parts;
  if (local.length === 0 || local.length > 64 || domain.length > 255) {
    return null;
  }
  if (local.includes("..") || domain.includes("..")) return null;
  if (!/^[a-z0-9](?:[a-z0-9._%+-]*[a-z0-9])?$/.test(local)) return null;
  const labels = domain.split(".");
  if (labels.length < 2) return null;
  for (const label of labels) {
    if (!/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(label)) return null;
  }
  if (!/^[a-z]{2,63}$/.test(labels[labels.length - 1])) return null;
  return email;
}

// Strips ASCII spaces, hyphens, and parentheses only. Any other character
// rejects the value. Canonical form is +20 plus the 10 national digits.
export function canonicalEgyptianPhone(value: unknown): string | null {
  if (typeof value !== "string") return null;
  if (/[^0-9+ \-()]/.test(value)) return null;
  const stripped = value.replace(/[ \-()]/g, "");
  let national: string | null = null;
  if (/^01[0125]\d{8}$/.test(stripped)) national = stripped.slice(1);
  else if (/^\+201[0125]\d{8}$/.test(stripped)) national = stripped.slice(3);
  else if (/^00201[0125]\d{8}$/.test(stripped)) national = stripped.slice(4);
  if (national === null) return null;
  return `+20${national}`;
}

// Supabase Auth may return the same phone without a leading plus.
// Auth may omit "+" or include spaces. Compare digits to the canonical +20 form.
export function phonesMatch(stored: string | null, canonical: string): boolean {
  if (stored === null || stored === undefined) return false;
  const digits = stored.replace(/[^0-9]/g, "");
  const expected = canonical.startsWith("+") ? canonical.slice(1) : canonical;
  return expected.length > 0 && digits === expected;
}

export function emailsMatch(stored: string | null, canonical: string): boolean {
  if (stored === null || stored === undefined) return false;
  return stored.trim().toLowerCase() === canonical;
}

function passwordField(value: unknown): string | null {
  if (typeof value !== "string") return null;
  if (value.trim().length === 0) return null;
  const bytes = new TextEncoder().encode(value).length;
  if (bytes < 8 || bytes > 72) return null;
  return value;
}
