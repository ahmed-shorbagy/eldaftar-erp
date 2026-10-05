import { validateRegistration } from './validate.ts';

const base = {
  idempotency_key: '11111111-1111-4111-8111-111111111111',
  owner_name: 'مالك تجريبي', business_name: 'محل تجريبي',
  email: 'owner@example.test', password: 'test-password',
};
Deno.test('country and phone must agree, manual regions remain in the replay profile', () => {
  for (const [region, phone, expected] of [
    ['SA:الرياض', '0501234567', '+966501234567'],
    ['AE:دبي', '0501234567', '+971501234567'],
    ['MA:الرباط', '0612345678', '+212612345678'],
    ['EG:القاهرة', '01012345678', '+201012345678'],
  ]) {
    const result = validateRegistration({ ...base, governorate_code: region, phone });
    if (result?.phone !== expected || result.governorateCode !== region) throw Error('country normalization');
  }
  for (const [region, phone] of [
    ['SA:الرياض', '+971501234567'], ['SA:', '0501234567'],
    ['ZZ:منطقة', '+123456789'], ['SA: الرياض', '0501234567'],
    ['SA:الرياض', '123'], ['EG:القاهرة', '+966501234567'],
  ]) {
    if (validateRegistration({ ...base, governorate_code: region, phone }) !== null) throw Error('invalid accepted');
  }
});
