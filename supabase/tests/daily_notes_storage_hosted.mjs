// Synthetic hosted HTTP checks. Keys/passwords/tokens remain in memory only.
// Caller must explicitly authorize setup, fixtures and cleanup. No CLI autorun.
import { randomBytes, randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';

const PROJECT = 'xchapwvmvoefriqcxtvn';
const ORIGIN = `https://${PROJECT}.supabase.co`;
const BUCKET = 'eldafttar-private-notes';
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aS1sAAAAASUVORK5CYII=', 'base64');

export function createStorageValidation({ projectId, anonKey, serviceKey }) {
  assert.equal(projectId, PROJECT, 'wrong target project');
  for (const [key, role] of [[anonKey, 'anon'], [serviceKey, 'service_role']]) {
    const claims = JSON.parse(Buffer.from(key.split('.')[1], 'base64url'));
    assert.equal(claims.ref, PROJECT, 'credential belongs to another project');
    assert.equal(claims.role, role, 'wrong credential role');
  }
  const fixture = { shop: randomUUID(), day: randomUUID(), object: randomUUID(), users: [] };
  const results = [];
  const attemptedPaths = new Set();
  const path = `${fixture.shop}/${fixture.day}/${fixture.object}.png`;
  const objectRoute = `/storage/v1/object/${BUCKET}/${path}`;
  async function request(method, route, body, token = serviceKey, headers = {}, key = anonKey) {
    assert.ok(route.startsWith('/') && !route.startsWith('//'), 'target-relative path required');
    const response = await fetch(ORIGIN + route, {
      method, redirect: 'error', signal: AbortSignal.timeout(30000),
      headers: { apikey: key, Authorization: `Bearer ${token}`, ...headers }, body,
    });
    const bytes = Buffer.from(await response.arrayBuffer());
    return { status: response.status, bytes, json: () => JSON.parse(bytes.toString()) };
  }
  const jsonHeaders = { 'Content-Type': 'application/json' };
  function pass(name, status) { results.push({ name, status, passed: true }); }
  function denied(name, response) {
    assert.ok(response.status >= 400 && response.status < 500, `${name}: HTTP ${response.status}`);
    pass(name, response.status);
  }
  function publicManifest() {
    return { projectId: PROJECT, shop: fixture.shop, day: fixture.day, path,
      users: fixture.users.map(({ id, email }) => ({ id, email })) };
  }
  return {
    manifest: publicManifest,
    results: () => [...results],
    async createUsers() {
      for (let i = 0; i < 2; i++) {
        const email = `notes-storage-${randomUUID()}@example.test`;
        const password = randomBytes(32).toString('base64url');
        const response = await request('POST', '/auth/v1/admin/users',
          JSON.stringify({ email, password, email_confirm: true }), serviceKey, jsonHeaders, serviceKey);
        assert.equal(response.status, 200, `synthetic admin user creation: HTTP ${response.status}`);
        const user = response.json();
        fixture.users.push({ id: user.id, email, password });
        pass('synthetic auth user created', response.status);
      }
      return publicManifest();
    },
    async run() {
      assert.equal(fixture.users.length, 2);
      for (const user of fixture.users) {
        const response = await request('POST', '/auth/v1/token?grant_type=password',
          JSON.stringify({ email: user.email, password: user.password }), anonKey, jsonHeaders);
        assert.equal(response.status, 200, `synthetic password sign-in: HTTP ${response.status}`);
        user.token = response.json().access_token;
        assert.equal(response.json().user.id, user.id);
        pass('synthetic password sign-in', response.status);
      }
      const [owner, foreign] = fixture.users;
      const uploadHeaders = { 'Content-Type': 'image/png', 'x-upsert': 'false', 'Cache-Control': 'no-cache' };
      attemptedPaths.add(path);
      let response = await request('POST', objectRoute, PNG, owner.token, uploadHeaders);
      assert.equal(response.status, 200, `owner upload: HTTP ${response.status}; ${response.bytes.toString().slice(0,200)}`);
      pass('owner upload', response.status);
      const read = async (token) => request('GET', `/storage/v1/object/authenticated/${BUCKET}/${path}`, undefined, token,
        { 'Cache-Control': 'no-cache' });
      response = await read(owner.token);
      assert.equal(response.status, 200); assert.deepEqual(response.bytes, PNG);
      pass('owner authenticated read exact bytes', response.status);
      denied('foreign owner read', await read(foreign.token));
      denied('anonymous read', await read(anonKey));
      denied('private public-URL read', await request('GET', `/storage/v1/object/public/${BUCKET}/${path}`, undefined, anonKey));
      denied('duplicate non-upsert upload', await request('POST', objectRoute, PNG, owner.token, uploadHeaders));
      const changedBytes = Buffer.concat([PNG, Buffer.from('replacement')]);
      denied('owner upsert replacement', await request('POST', objectRoute, changedBytes, owner.token,
        { ...uploadHeaders, 'x-upsert': 'true' }));
      denied('owner PUT replacement', await request('PUT', objectRoute, changedBytes, owner.token, uploadHeaders));
      // DELETE can return HTTP 200 with [] when RLS hides every candidate.
      response = await request('DELETE', `/storage/v1/object/${BUCKET}`,
        JSON.stringify({ prefixes: [path] }), owner.token, jsonHeaders);
      if (response.status === 200) assert.deepEqual(response.json(), []);
      else denied('owner delete rejected', response);
      pass('owner delete removed no objects', response.status);
      response = await read(owner.token);
      assert.equal(response.status, 200); assert.deepEqual(response.bytes, PNG);
      pass('bytes unchanged after replacement and delete attempts', response.status);
      const invalid = [
        ['foreign owner upload into owner shop', path.replace(fixture.object, randomUUID()), foreign.token, uploadHeaders, PNG],
        ['malformed path upload', `${fixture.shop}/${fixture.day}/invalid.png`, owner.token, uploadHeaders, PNG],
        ['MIME mismatch upload', path.replace(fixture.object, randomUUID()), owner.token,
          { ...uploadHeaders, 'Content-Type': 'text/plain' }, PNG],
        ['oversize upload', path.replace(fixture.object, randomUUID()), owner.token, uploadHeaders, Buffer.alloc(5242881)],
      ];
      for (const [name, candidate, token, headers, bytes] of invalid) {
        attemptedPaths.add(candidate);
        denied(name, await request('POST', `/storage/v1/object/${BUCKET}/${candidate}`, bytes, token, headers));
      }
      // Creation/read only: no claim that waiting for expiry has been tested.
      response = await request('POST', `/storage/v1/object/sign/${BUCKET}/${path}`,
        JSON.stringify({ expiresIn: 300 }), owner.token, jsonHeaders);
      assert.equal(response.status, 200);
      const signedPath = response.json().signedURL;
      const signed = new URL(signedPath.startsWith('/object/') ? '/storage/v1' + signedPath : signedPath, ORIGIN);
      assert.equal(signed.origin, ORIGIN);
      assert.equal(signed.pathname, `/storage/v1/object/sign/${BUCKET}/${path}`);
      response = await request('GET', signed.pathname + signed.search, undefined, anonKey);
      assert.equal(response.status, 200); assert.deepEqual(response.bytes, PNG);
      pass('signed URL creation/read (expiry untested)', response.status);
      return [...results];
    },
    async cleanupObjects() {
      if (!attemptedPaths.size) return;
      const response = await request('DELETE', `/storage/v1/object/${BUCKET}`,
        JSON.stringify({ prefixes: [...attemptedPaths] }), serviceKey, jsonHeaders, serviceKey);
      assert.equal(response.status, 200, `privileged Storage cleanup: HTTP ${response.status}`);
      const removed = response.json();
      assert.ok(removed.every(object => attemptedPaths.has(object.name)), 'cleanup escaped exact synthetic paths');
      pass('privileged API object cleanup', response.status);
      return { removed: removed.length };
    },
    async cleanupUsers() {
      // Call only after scoped application fixture SQL cleanup has succeeded.
      for (const user of fixture.users) {
        if (user.token) {
          const logout = await request('POST', '/auth/v1/logout?scope=global', undefined, user.token);
          assert.equal(logout.status, 204, 'synthetic global sign-out failed');
        }
        const response = await request('DELETE', `/auth/v1/admin/users/${user.id}`,
          JSON.stringify({ should_soft_delete: false }), serviceKey, jsonHeaders, serviceKey);
        assert.equal(response.status, 200, `synthetic Auth cleanup: HTTP ${response.status}`);
        user.password = null; user.token = null;
        pass('synthetic global sign-out and Auth API deletion', response.status);
      }
      return [...results];
    },
  };
}
