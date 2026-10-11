import { countryDialCodes, validateRegistration } from "./validate.ts";

const base = {
  idempotency_key: "11111111-1111-4111-8111-111111111111",
  owner_name: "مالك تجريبي",
  business_name: "محل تجريبي",
  email: "owner@example.test",
  password: "test-password",
};
Deno.test("country and phone must agree, catalog Egypt codes canonicalize, and EG:text is rejected", () => {
  for (
    const [region, phone, expected, stored] of [
      ["SA:الرياض", "0501234567", "+966501234567", "SA:الرياض"],
      ["AE:دبي", "0501234567", "+971501234567", "AE:دبي"],
      ["MA:الرباط", "0612345678", "+212612345678", "MA:الرباط"],
      ["EG-C", "01012345678", "+201012345678", "EG-C"],
      [" eg-gz ", "01012345678", "+201012345678", "EG-GZ"],
    ] as const
  ) {
    const result = validateRegistration({
      ...base,
      governorate_code: region,
      phone,
    });
    if (result?.phone !== expected || result.governorateCode !== stored) {
      throw Error(`country normalization ${region}`);
    }
  }
  for (
    const [region, phone] of [
      ["SA:الرياض", "+971501234567"],
      ["SA: ", "0501234567"],
      ["ZZ:منطقة", "+123456789"],
      ["SA: الرياض", "0501234567"],
      ["SA:الرياض", "123"],
      ["EG:القاهرة", "01012345678"],
      ["EG:القاهرة", "+966501234567"],
    ]
  ) {
    if (
      validateRegistration({ ...base, governorate_code: region, phone }) !==
        null
    ) throw Error("invalid accepted");
  }
});

Deno.test("new registrations reject empty, malformed, and Egypt manual regions", () => {
  for (const [country, dial] of Object.entries(countryDialCodes)) {
    const phone = country === "EG" ? "01012345678" : `+${dial}501234567`;
    if (
      validateRegistration({
        ...base,
        governorate_code: `${country}:`,
        phone,
      }) !== null
    ) {
      throw Error(`empty region accepted: ${country}`);
    }
  }
  for (
    const region of [
      "ZZ:",
      "SA: ",
      "SA:\n",
      `SA:${"أ".repeat(121)}`,
      "EG-XXX",
      "الجيزة",
    ]
  ) {
    if (
      validateRegistration({
        ...base,
        governorate_code: region,
        phone: "0501234567",
      }) !== null
    ) {
      throw Error("invalid region accepted");
    }
  }
});
