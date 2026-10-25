// Separate connections in the disposable ADM-02 cluster; no remote database.
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { randomUUID } from 'node:crypto'

const connection = process.env.SUPABASE_TEST_DATABASE_URL
const url = new URL(connection ?? 'http://invalid')
if (url.hostname !== '127.0.0.1' || url.port !== '55475' ||
    !url.pathname.startsWith('/eldaftar_admin_subscription_codes_') ||
    url.protocol !== 'postgresql:') {
  throw Error('dedicated_local_database_required')
}

const admin = randomUUID()
const owner = randomUUID()
const shop = randomUUID()
const adminSession = randomUUID()
const ownerSessionA = randomUUID()
const ownerSessionB = randomUUID()
const issueKey = randomUUID()
const redeemKeyA = randomUUID()
const redeemKeyB = randomUUID()
const psql = process.env.PSQL ?? 'psql'

function run(sql) {
  return new Promise((resolve, reject) => {
    const child = spawn(psql, [connection, '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1'],
      { stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, PGCLIENTENCODING: 'UTF8' } })
    let output = '', errors = ''
    child.stdout.on('data', x => { output += x })
    child.stderr.on('data', x => { errors += x })
    child.on('error', reject)
    child.on('close', code => code ? reject(Error(errors || output)) : resolve(output.trim()))
    child.stdin.end(sql)
  })
}

function asUser(userId, sessionId, sql) {
  const claims = JSON.stringify({
    sub: userId,
    role: 'authenticated',
    session_id: sessionId,
    is_anonymous: false,
  }).replaceAll("'", "''")
  return `
begin;
do $auth$
begin
  perform set_config('request.jwt.claim.sub', '${userId}', true);
  perform set_config('request.jwt.claim.session_id', '${sessionId}', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claims', '${claims}', true);
end;
$auth$;
set local role authenticated;
${sql}
commit;
`
}

async function waitUntil(sql, expected, label, ms = 8000) {
  const deadline = Date.now() + ms
  while (true) {
    const value = await run(sql)
    if (value === expected) return
    assert.ok(Date.now() < deadline, `${label}: ${value}`)
    await new Promise(resolve => setTimeout(resolve, 50))
  }
}

async function waitUntilAtLeast(sql, min, label, ms = 8000) {
  const deadline = Date.now() + ms
  while (true) {
    const value = await run(sql)
    if (Number(value) >= min) return
    assert.ok(Date.now() < deadline, `${label}: ${value}`)
    await new Promise(resolve => setTimeout(resolve, 50))
  }
}

async function expectUnauthorized(promise, label) {
  try {
    const output = await promise
    throw Error(`${label} succeeded with status ${String(output).split(',')[0]}`)
  } catch (error) {
    assert.match(String(error.message), /unauthorized|permission denied/, label)
  }
}

function waiterXactStart(pattern) {
  return `(select a.xact_start from pg_stat_activity a
            where a.wait_event_type = 'Lock'
              and a.query ilike '%${pattern}%'
            order by a.xact_start desc
            limit 1)`
}

async function expireSessionAfterWaiterStart(sessionId, waiterPattern, label) {
  const relations = await run(`
update auth.sessions
   set not_after = clock_timestamp() + interval '1500 milliseconds'
 where id = '${sessionId}'::uuid
   and ${waiterXactStart(waiterPattern)} is not null
   and clock_timestamp() + interval '1500 milliseconds' > ${waiterXactStart(waiterPattern)};
select (select not_after from auth.sessions where id = '${sessionId}'::uuid)
         > ${waiterXactStart(waiterPattern)}
   and (select not_after from auth.sessions where id = '${sessionId}'::uuid)
         < clock_timestamp() + interval '8 seconds';
`)
  assert.equal(relations, 't', `${label}: not_after after waiter xact_start and before lock release`)
  await waitUntil(
    `select clock_timestamp() > (select not_after from auth.sessions where id = '${sessionId}'::uuid)`,
    't',
    `${label}: not_after elapsed`,
  )
}

await run(`
insert into auth.users(id,instance_id,aud,role,email,is_anonymous,created_at,updated_at,banned_until)
 values
 ('${admin}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','adm02-race-admin@example.test',false,now(),now(),null),
 ('${owner}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','adm02-race-owner@example.test',false,now(),now(),null);
insert into public.shops(id,name) values('${shop}','متجر تزامن الرمز');
insert into public.shop_memberships(shop_id,user_id,role) values('${shop}','${owner}','owner');
insert into public.shop_entitlements(shop_id,starts_at,expires_at)
 values('${shop}', now() - interval '1 day', now() + interval '10 days');
insert into public.platform_admins(user_id) values('${admin}');
insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values
 ('${adminSession}','${admin}',now(),now(),now()+interval '1 day'),
 ('${ownerSessionA}','${owner}',now(),now(),now()+interval '1 day'),
 ('${ownerSessionB}','${owner}',now(),now(),now()+interval '1 day');
`)

async function whileIssueBlocked(requestKey, duringWait, label) {
  const holder = run(`
    select pg_advisory_lock(840274, hashtext('${requestKey}'::text));
    select pg_sleep(8);
    select pg_advisory_unlock(840274, hashtext('${requestKey}'::text));
  `)
  await waitUntil(
    `select count(*)::text from pg_locks where locktype='advisory' and classid=840274 and granted`,
    '1',
    'issue holder lock',
  )
  const blocked = run(asUser(admin, adminSession, `
select t.status
from public.issue_subscription_code('${shop}'::uuid, 30, 30, '${requestKey}'::uuid) as t;
`))
  void blocked.catch(() => {})
  await waitUntil(
    `select count(*)::text from pg_stat_activity
      where wait_event_type='Lock' and query ilike '%issue_subscription_code%'`,
    '1',
    'issue waiter',
  )
  await duringWait()
  await holder
  await expectUnauthorized(blocked, label)
}

async function whileRedeemBlocked(requestKey, redeemCode, duringWait, label) {
  const holder = run(`
    select pg_advisory_lock(840272, hashtext('${requestKey}'::text));
    select pg_sleep(8);
    select pg_advisory_unlock(840272, hashtext('${requestKey}'::text));
  `)
  await waitUntil(
    `select count(*)::text from pg_locks where locktype='advisory' and classid=840272 and granted`,
    '1',
    'redeem holder lock',
  )
  const blocked = run(asUser(owner, ownerSessionA, `
select status
from public.redeem_subscription_code('${requestKey}'::uuid, '${redeemCode}');
`))
  void blocked.catch(() => {})
  await waitUntil(
    `select count(*)::text from pg_stat_activity
      where wait_event_type='Lock' and query ilike '%redeem_subscription_code%'`,
    '1',
    'redeem waiter',
  )
  await duringWait()
  await holder
  await expectUnauthorized(blocked, label)
}

const revokeKey = randomUUID()
await whileIssueBlocked(revokeKey, async () => {
  await run(`delete from public.platform_admins where user_id='${admin}'::uuid`)
}, 'admin revocation while issuance blocked')
await run(`insert into public.platform_admins(user_id) values('${admin}')`)
const revokeIssued = await run(`
select count(*)::text from private.subscription_codes
 where issue_request_key='${revokeKey}'::uuid
`)
assert.equal(revokeIssued, '0', 'revoked admin issued a row')

const deleteKey = randomUUID()
await whileIssueBlocked(deleteKey, async () => {
  await run(`delete from auth.sessions where id='${adminSession}'::uuid`)
}, 'session deletion while issuance blocked')
await run(`
insert into auth.sessions(id,user_id,created_at,updated_at,not_after)
 values('${adminSession}','${admin}',now(),now(),now()+interval '1 day')
`)
assert.equal(await run(`
select count(*)::text from private.subscription_codes
 where issue_request_key='${deleteKey}'::uuid
`), '0', 'deleted session issued a row')

const expireKey = randomUUID()
await whileIssueBlocked(expireKey, async () => {
  await expireSessionAfterWaiterStart(adminSession, 'issue_subscription_code', 'admin session expiry')
}, 'session expiring while issuance blocked')
await run(`
update auth.sessions
   set not_after = clock_timestamp() + interval '1 day'
 where id='${adminSession}'::uuid
`)
assert.equal(await run(`
select count(*)::text from private.subscription_codes
 where issue_request_key='${expireKey}'::uuid
`), '0', 'expired session issued a row')

const sameIssueKey = randomUUID()
function issueSame() {
  return run(asUser(admin, adminSession, `
select t.status || ',' || coalesce(t.code,'')
from public.issue_subscription_code('${shop}'::uuid, 30, 30, '${sameIssueKey}'::uuid) as t;
`))
}
const [issuedA, issuedB] = await Promise.all([issueSame(), issueSame()])
const issueParts = [issuedA, issuedB].map(row => row.split(','))
const issueStatuses = issueParts.map(part => part[0]).sort()
assert.deepEqual(issueStatuses, ['issued', 'replayed'], 'same-key issue statuses')
const issuedCodes = issueParts.filter(part => part[0] === 'issued').map(part => part[1])
assert.equal(issuedCodes.length, 1, 'same-key issue produced multiple secrets')
assert.equal(issuedCodes[0].length, 32, 'issued code length')
assert.equal(await run(`
select count(*)::text from private.subscription_codes
 where issue_request_key='${sameIssueKey}'::uuid
`), '1', 'same-key issue row count')
assert.equal(await run(`
select count(*)::text from private.subscription_code_events
 where correlation_id='${sameIssueKey}'::uuid
   and action='subscription_code_issued'
`), '1', 'same-key issue event count')

const beforeExpiry = await run(`
select expires_at::text
from public.shop_entitlements where shop_id='${shop}'::uuid;
`)

const issued = await run(asUser(admin, adminSession, `
select t.status || ',' || coalesce(t.code,'')
from public.issue_subscription_code('${shop}'::uuid, 30, 30, '${issueKey}'::uuid) as t;
`))
const [issueStatus, code] = issued.split(',')
assert.equal(issueStatus, 'issued', 'issue status')
assert.equal(code.length, 32, 'issued code length')

const ownerExpireKey = randomUUID()
await whileRedeemBlocked(ownerExpireKey, code, async () => {
  await expireSessionAfterWaiterStart(ownerSessionA, 'redeem_subscription_code', 'owner session expiry')
}, 'owner session expiry while redemption blocked')
await run(`
update auth.sessions
   set not_after = clock_timestamp() + interval '1 day'
 where id='${ownerSessionA}'::uuid
`)

const ownerRevokeKey = randomUUID()
await whileRedeemBlocked(ownerRevokeKey, code, async () => {
  await run(`delete from auth.sessions where id='${ownerSessionA}'::uuid`)
}, 'owner session revocation while redemption blocked')
await run(`
insert into auth.sessions(id,user_id,created_at,updated_at,not_after)
 values('${ownerSessionA}','${owner}',now(),now(),now()+interval '1 day')
`)
assert.equal(await run(`
select count(*)::text from private.subscription_redemption_requests
 where request_key in ('${ownerExpireKey}'::uuid, '${ownerRevokeKey}'::uuid)
`), '0', 'blocked owner redemption wrote a request')

const sameRedeemKey = randomUUID()
function redeemSame() {
  return run(asUser(owner, ownerSessionA, `
select status
from public.redeem_subscription_code('${sameRedeemKey}'::uuid, '${code}');
`))
}
const [sameFirst, sameSecond] = await Promise.all([redeemSame(), redeemSame()])
const sameStatuses = [sameFirst, sameSecond].sort()
assert.deepEqual(sameStatuses, ['activated', 'replayed'], `same-key redeem: ${sameFirst} / ${sameSecond}`)
assert.equal(await run(`
select count(*)::text from private.subscription_redemption_requests
 where request_key='${sameRedeemKey}'::uuid
`), '1', 'same-key redeem request count')

const secondCodeIssued = await run(asUser(admin, adminSession, `
select t.status || ',' || coalesce(t.code,'')
from public.issue_subscription_code('${shop}'::uuid, 30, 30, '${randomUUID()}'::uuid) as t;
`))
const [secondStatus, secondCode] = secondCodeIssued.split(',')
assert.equal(secondStatus, 'issued')
assert.equal(secondCode.length, 32)

function redeem(session, key, redeemCode = secondCode) {
  return run(asUser(owner, session, `
select status
from public.redeem_subscription_code('${key}'::uuid, '${redeemCode}');
`))
}

const [first, second] = await Promise.all([
  redeem(ownerSessionA, redeemKeyA),
  redeem(ownerSessionB, redeemKeyB),
])
const statuses = [first, second].sort()
assert.deepEqual(statuses, ['activated', 'reused_code'])

const extendedOnce = await run(`
select expires_at = timestamptz '${beforeExpiry}' + interval '60 days'
from public.shop_entitlements where shop_id='${shop}'::uuid;
`)
assert.equal(extendedOnce, 't', `entitlement not extended twice: before=${beforeExpiry} result=${extendedOnce}`)

const throttleShop = randomUUID()
const throttleOwner = randomUUID()
const throttleSession = randomUUID()
const throttleAdminKey = randomUUID()
const throttleRedeemKey = randomUUID()
await run(`
insert into auth.users(id,instance_id,aud,role,email,is_anonymous,created_at,updated_at,banned_until)
 values('${throttleOwner}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','adm02-throttle-owner@example.test',false,now(),now(),null);
insert into public.shops(id,name) values('${throttleShop}','متجر حد المحاولات');
insert into public.shop_memberships(shop_id,user_id,role) values('${throttleShop}','${throttleOwner}','owner');
insert into public.shop_entitlements(shop_id,starts_at,expires_at)
 values('${throttleShop}', now() - interval '1 day', now() + interval '10 days');
insert into auth.sessions(id,user_id,created_at,updated_at,not_after)
 values('${throttleSession}','${throttleOwner}',now(),now(),now()+interval '1 day');
`)
const throttleIssued = await run(asUser(admin, adminSession, `
select t.status || ',' || coalesce(t.code,'')
from public.issue_subscription_code('${throttleShop}'::uuid, 30, 30, '${throttleAdminKey}'::uuid) as t;
`))
const [throttleIssueStatus, throttleCode] = throttleIssued.split(',')
assert.equal(throttleIssueStatus, 'issued')
const throttleActivated = await run(asUser(throttleOwner, throttleSession, `
select status
from public.redeem_subscription_code('${throttleRedeemKey}'::uuid, '${throttleCode}');
`))
assert.equal(throttleActivated, 'activated')

const invalidKeys = Array.from({ length: 8 }, () => randomUUID())
const invalidBatchA = invalidKeys.slice(0, 4).map(key =>
  run(asUser(throttleOwner, throttleSession, `
select status from public.redeem_subscription_code('${key}'::uuid, '00000000000000000000000000000000');
`)))
await Promise.all(invalidBatchA)
const invalidBatchB = invalidKeys.slice(4).map(key =>
  run(asUser(throttleOwner, throttleSession, `
select status from public.redeem_subscription_code('${key}'::uuid, '11111111111111111111111111111111');
`)))
const invalidResults = await Promise.all(invalidBatchB)
assert.ok(invalidResults.every(status => status === 'invalid_code'), `invalid attempts: ${invalidResults}`)
assert.equal(await run(`
select count(*)::text from private.subscription_code_attempts
 where user_id='${throttleOwner}'::uuid and accepted=false
`), '8', 'committed invalid attempts')

const throttled = await run(asUser(throttleOwner, throttleSession, `
select status
from public.redeem_subscription_code('${randomUUID()}'::uuid, '22222222222222222222222222222222');
`))
assert.equal(throttled, 'rate_limited', 'throttle did not persist across requests')

const replayAfterThrottle = await run(asUser(throttleOwner, throttleSession, `
select status
from public.redeem_subscription_code('${throttleRedeemKey}'::uuid, '${throttleCode}');
`))
assert.equal(replayAfterThrottle, 'replayed', 'successful replay did not precede throttle')

async function seedLockedShop(tag) {
  const user = randomUUID()
  const shopId = randomUUID()
  const session = randomUUID()
  await run(`
insert into auth.users(id,instance_id,aud,role,email,is_anonymous,created_at,updated_at,banned_until)
 values('${user}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','adm02-${tag}@example.test',false,now(),now(),null);
insert into public.shops(id,name) values('${shopId}','متجر قفل الاستحقاق');
insert into public.shop_memberships(shop_id,user_id,role) values('${shopId}','${user}','owner');
insert into public.shop_entitlements(shop_id,starts_at,expires_at)
 values('${shopId}', now() - interval '1 day', now() + interval '10 days');
insert into auth.sessions(id,user_id,created_at,updated_at,not_after)
 values('${session}','${user}',now(),now(),now()+interval '1 day');
`)
  const adminKey = randomUUID()
  const issuedRow = await run(asUser(admin, adminSession, `
select t.status || ',' || coalesce(t.code,'')
from public.issue_subscription_code('${shopId}'::uuid, 30, 30, '${adminKey}'::uuid) as t;
`))
  const [status, redeemCode] = issuedRow.split(',')
  assert.equal(status, 'issued', `${tag} issue status`)
  assert.equal(redeemCode.length, 32, `${tag} issued code length`)
  const term = await run(`
select starts_at::text || ',' || expires_at::text
from public.shop_entitlements where shop_id='${shopId}'::uuid
`)
  const [startsAt, expiresAt] = term.split(',')
  return { user, shopId, session, redeemCode, startsAt, expiresAt }
}

function holdEntitlement(shopId, innerSql = 'perform pg_sleep(12);') {
  return run(`
do $hold$
begin
  perform 1 from public.shop_entitlements where shop_id = '${shopId}'::uuid for update;
  ${innerSql}
end;
$hold$;
`)
}

async function waitEntitlementHolder() {
  await waitUntilAtLeast(
    `select count(*)::text from pg_stat_activity
      where pid <> pg_backend_pid()
        and wait_event = 'PgSleep'
        and query ilike '%$hold$%'
        and state = 'active'`,
    1,
    'entitlement holder',
  )
}

async function startRedeemOnLockedEntitlement(shop, requestKey, beforeWaiter, duringWait, innerSql) {
  const holder = holdEntitlement(shop.shopId, innerSql)
  await waitEntitlementHolder()
  if (beforeWaiter) await beforeWaiter()
  const blocked = run(asUser(shop.user, shop.session, `
select status
from public.redeem_subscription_code('${requestKey}'::uuid, '${shop.redeemCode}');
`))
  void blocked.catch(() => {})
  try {
    await waitUntilAtLeast(
      `select count(*)::text from pg_locks where not granted`,
      1,
      'entitlement redeem waiter',
      10000,
    )
  } catch (error) {
    const diag = await run(`
select coalesce(string_agg(
  pid::text || ':' || coalesce(wait_event_type, '-') || ':' || coalesce(wait_event, '-')
  || ':' || coalesce(state, '-') || ':' || case
    when query ilike '%redeem_subscription_code%' then 'redeem'
    when query ilike '%$hold$%' then 'holder'
    when query ilike '%pg_sleep%' then 'sleep'
    else 'other'
  end,
  ' || '), 'none')
from pg_stat_activity
where datname = current_database()
  and pid <> pg_backend_pid()
  and query is not null
`)
    throw Error(`${error.message}; diag=${diag}`)
  }
  if (duringWait) await duringWait()
  return { holder, blocked }
}

async function entitlementUnchanged(shop, requestKey, label) {
  assert.equal(await run(`
select starts_at = timestamptz '${shop.startsAt}' and expires_at = timestamptz '${shop.expiresAt}'
from public.shop_entitlements where shop_id='${shop.shopId}'::uuid
`), 't', `${label}: entitlement changed`)
  assert.equal(await run(`
select count(*)::text from private.subscription_redemption_requests
 where request_key='${requestKey}'::uuid
`), '0', `${label}: wrote a redemption request`)
}

const sessionLockShop = await seedLockedShop('ent-session')
const sessionLockKey = randomUUID()
{
  const { holder, blocked } = await startRedeemOnLockedEntitlement(sessionLockShop, sessionLockKey, null, async () => {
    await expireSessionAfterWaiterStart(sessionLockShop.session, 'redeem_subscription_code', 'entitlement session expiry')
  })
  await holder
  await expectUnauthorized(blocked, 'owner session expiry while entitlement locked')
}
await run(`
update auth.sessions
   set not_after = clock_timestamp() + interval '1 day'
 where id='${sessionLockShop.session}'::uuid
`)
await entitlementUnchanged(sessionLockShop, sessionLockKey, 'session expiry during entitlement wait')

const revokeLockShop = await seedLockedShop('ent-revoke')
const revokeLockKey = randomUUID()
{
  const { holder, blocked } = await startRedeemOnLockedEntitlement(revokeLockShop, revokeLockKey, null, async () => {
    await run(`
update public.shop_memberships
   set revoked_at = clock_timestamp()
 where shop_id='${revokeLockShop.shopId}'::uuid
   and user_id='${revokeLockShop.user}'::uuid
`)
  })
  await holder
  await expectUnauthorized(blocked, 'membership revocation while entitlement locked')
}
await entitlementUnchanged(revokeLockShop, revokeLockKey, 'membership revocation during entitlement wait')

const codeLockShop = await seedLockedShop('ent-code')
const codeLockKey = randomUUID()
{
  const { holder, blocked } = await startRedeemOnLockedEntitlement(codeLockShop, codeLockKey, async () => {
    await run(`
update private.subscription_codes
   set code_expires_at = clock_timestamp() + interval '1500 milliseconds'
 where shop_id='${codeLockShop.shopId}'::uuid
   and redeemed_at is null
`)
  }, async () => {
    const relations = await run(`
select (select code_expires_at from private.subscription_codes
         where shop_id='${codeLockShop.shopId}'::uuid and redeemed_at is null)
         > ${waiterXactStart('redeem_subscription_code')}
   and (select code_expires_at from private.subscription_codes
         where shop_id='${codeLockShop.shopId}'::uuid and redeemed_at is null)
         < clock_timestamp() + interval '8 seconds';
`)
    assert.equal(relations, 't', 'code expiry after waiter xact_start and before lock release')
    await waitUntil(
      `select clock_timestamp() > (select code_expires_at from private.subscription_codes
         where shop_id='${codeLockShop.shopId}'::uuid and redeemed_at is null)`,
      't',
      'code expiry elapsed during entitlement wait',
    )
  })
  await holder
  assert.equal(await blocked, 'expired_code', 'code expiry during entitlement wait')
}
await entitlementUnchanged(codeLockShop, codeLockKey, 'code expiry during entitlement wait')
assert.equal(await run(`
select count(*)::text from private.subscription_code_attempts
 where user_id='${codeLockShop.user}'::uuid and accepted=false
`), '1', 'expired-during-wait attempt count')

const termLockShop = await seedLockedShop('ent-term')
const termLockKey = randomUUID()
const holder = holdEntitlement(termLockShop.shopId, `
perform pg_sleep(1);
update public.shop_entitlements
   set expires_at = clock_timestamp() + interval '1500 milliseconds'
 where shop_id='${termLockShop.shopId}'::uuid;
perform pg_sleep(6);
`)
await waitEntitlementHolder()
const termBlocked = run(asUser(termLockShop.user, termLockShop.session, `
select status
from public.redeem_subscription_code('${termLockKey}'::uuid, '${termLockShop.redeemCode}');
`))
void termBlocked.catch(() => {})
await waitUntilAtLeast(
  `select count(*)::text from pg_locks where not granted`,
  1,
  'entitlement term waiter',
  10000,
)
const termWaiterStart = await run(`select ${waiterXactStart('redeem_subscription_code')}::text`)
assert.ok(termWaiterStart.length > 0, 'entitlement term waiter xact_start')
await waitUntil(
  `select clock_timestamp() > timestamptz '${termWaiterStart}' + interval '3 seconds'`,
  't',
  'entitlement shortened expiry elapsed',
)
await holder
assert.equal(await termBlocked, 'activated', 'entitlement expiry during wait')
const termAfter = await run(`
select starts_at is distinct from timestamptz '${termLockShop.startsAt}'
   and starts_at > now() - interval '15 seconds'
   and expires_at = starts_at + interval '30 days'
from public.shop_entitlements where shop_id='${termLockShop.shopId}'::uuid
`)
assert.equal(termAfter, 't', 'entitlement wait used current clock for a new term')

console.log(JSON.stringify({
  passed: 'blocked session races, same-key issue/redeem, different-key extend once, committed throttle, entitlement row-lock races',
  connections: 2,
  issueStatuses,
  sameStatuses,
  statuses,
}))

