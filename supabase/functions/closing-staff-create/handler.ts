export type StaffCreationPorts = {
  user(token: string): Promise<string | null>;
  proof(owner: string, key: string, password: string): Promise<string>;
  prepare(token: string, input: Record<string, unknown>): Promise<Record<string, unknown>>;
  identity(id: string): Promise<{ id: string; phone: string | null } | null>;
  create(id: string, phone: string, password: string): Promise<void>;
  complete(owner: string, key: string): Promise<Record<string, unknown>>;
};
const headers = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'POST, OPTIONS',
  'access-control-allow-headers': 'authorization, apikey, content-type, x-client-info',
  'cache-control': 'no-store', 'content-type': 'application/json; charset=utf-8',
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const reply = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers });

/** No messages, emails or SMS are sent. Service credentials stay in the adapter. */
export async function handleStaffCreation(request: Request, ports: StaffCreationPorts): Promise<Response> {
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (request.method !== 'POST') return reply(405, { code: 'invalid_input' });
  const bearer = request.headers.get('authorization');
  if (!bearer?.startsWith('Bearer ') || bearer.length > 16384) return reply(401, { code: 'unauthenticated' });
  const token = bearer.slice(7);
  try {
    const owner = await ports.user(token);
    if (owner === null) return reply(401, { code: 'unauthenticated' });
    const reader = request.body?.getReader();
    if (!reader) return reply(400, { code: 'invalid_input' });
    const chunks: Uint8Array[] = [];
    let length = 0;
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      length += next.value.length;
      if (length > 4096) { await reader.cancel(); return reply(400, { code: 'invalid_input' }); }
      chunks.push(next.value);
    }
    const bytes = new Uint8Array(length);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    const raw = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    let body: unknown;
    try { body = JSON.parse(raw); } catch { return reply(400, { code: 'invalid_input' }); }
    if (body === null || typeof body !== 'object' || Array.isArray(body)) return reply(400, { code: 'invalid_input' });
    const data = body as Record<string, unknown>;
    const key = data.idempotency_key, name = data.name, phone = data.phone, password = data.password;
    if (Object.keys(data).length !== 4 || typeof key !== 'string' || !uuid.test(key) ||
        typeof name !== 'string' || [...name.trim()].length < 1 || [...name.trim()].length > 120 || /[\u0000-\u001f\u007f]/u.test(name) ||
        typeof phone !== 'string' || !/^201[0125][0-9]{8}$/.test(phone) || typeof password !== 'string' ||
        password.trim().length === 0 || new TextEncoder().encode(password).length < 8 || new TextEncoder().encode(password).length > 72) {
      return reply(400, { code: 'invalid_input' });
    }
    const proof = await ports.proof(owner, key, password);
    const reservation = await ports.prepare(token, { p_key: key, p_name: name.trim(), p_phone: phone, p_password_proof: proof });
    if (reservation.owner_user_id !== owner || typeof reservation.reserved_user_id !== 'string' || reservation.phone !== phone) {
      return reply(502, { code: 'unavailable' });
    }
    if (reservation.staff_id == null) {
      const id = reservation.reserved_user_id;
      const existing = await ports.identity(id);
      if (existing === null) {
        await ports.create(id, phone, password);
        const created = await ports.identity(id);
        if (created === null || created.id !== id || created.phone?.replace(/^\+/, '') !== phone) return reply(503, { code: 'unavailable' });
      } else if (existing.id !== id || existing.phone?.replace(/^\+/, '') !== phone) {
        return reply(409, { code: 'identity_mismatch' });
      }
    }
    const result = await ports.complete(owner, key);
    if (result.ok !== true || typeof result.staff_id !== 'string' || typeof result.replayed !== 'boolean') return reply(503, { code: 'unavailable' });
    return reply(200, result);
  } catch (error) {
    const code = error instanceof Error ? error.message : '';
    const permitted = new Set(['forbidden', 'shop_not_active', 'identifier_taken', 'staff_limit', 'payload_mismatch', 'invalid_input']);
    return permitted.has(code) ? reply(code === 'forbidden' ? 403 : 409, { code }) : reply(503, { code: 'unavailable' });
  }
}
