// Two real local connections. Rows stay in the disposable customer cluster.
import { spawn } from 'node:child_process'

const connection = process.env.SUPABASE_TEST_DATABASE_URL
const url = new URL(connection ?? 'http://invalid')
if (
  url.protocol !== 'postgresql:' ||
  url.hostname !== '127.0.0.1' ||
  url.port !== '55448' ||
  url.pathname !== '/eldaftar_customers'
) {
  throw new Error('dedicated_local_database_required')
}

const executable = process.env.PSQL ?? 'psql'
const owner = 'c8c8c8c8-c8c8-48c8-88c8-c8c8c8c8c8c8'
const shop = 'c9c9c9c9-c9c9-49c9-89c9-c9c9c9c9c9c9'
const editCustomerKey = 'c3100000-0000-4000-8000-000000000001'
const sameKey = 'c3100000-0000-4000-8000-000000000011'
const editKeyA = 'c3100000-0000-4000-8000-000000000012'
const editKeyB = 'c3100000-0000-4000-8000-000000000013'
const phoneKeyA = 'c3100000-0000-4000-8000-000000000021'
const phoneKeyB = 'c3100000-0000-4000-8000-000000000022'

function run(sql, allowFailure = false) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      executable,
      [connection, '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1'],
      {
        stdio: ['pipe', 'pipe', 'pipe'],
        env: { ...process.env, PGCLIENTENCODING: 'UTF8' },
      },
    )
    let output = ''
    let error = ''
    child.stdout.on('data', (chunk) => {
      output += chunk
    })
    child.stderr.on('data', (chunk) => {
      error += chunk
    })
    child.on('error', reject)
    child.on('close', (code) => {
      if (code && !allowFailure) reject(new Error(error || output))
      else resolve({ code, output: output.trim(), error })
    })
    child.stdin.end(sql)
  })
}

function parseResult(output) {
  const lines = output.split('\n').map((line) => line.trim()).filter((line) => line.startsWith('{'))
  for (let index = lines.length - 1; index >= 0; index -= 1) {
    try {
      const value = JSON.parse(lines[index])
      if (value && typeof value === 'object' && Object.hasOwn(value, 'ok')) return value
    } catch {
      // A set_config claim line is JSON but not a command result.
    }
  }
  throw new Error(`no_result ${output}`)
}

const auth = `set local role authenticated; select set_config('request.jwt.claim.sub','${owner}',true); select set_config('request.jwt.claims','{"sub":"${owner}","role":"authenticated","is_anonymous":false}',true); set local statement_timeout = '15s';`

function createPayload(name, phone) {
  return JSON.stringify({
    version: 1,
    kind: 'customer_create',
    display_name: name,
    phones: phone ? [{ number: phone, is_primary: true }] : [],
    is_vip: false,
    has_open_request: false,
  })
}

function editPayload(customerId, name) {
  return JSON.stringify({
    version: 1,
    kind: 'customer_edit',
    customer_id: customerId,
    expected_version: '1',
    display_name: name,
    phones: [],
  })
}

function call(sql) {
  return run(`begin; ${auth} ${sql} commit;`, true)
}

const setup = await run(`begin;
do $guard$ begin
  if exists(select 1 from auth.users where id='${owner}')
    or exists(select 1 from public.shops where id='${shop}') then
    raise exception 'fixture_collision';
  end if;
end; $guard$;
insert into auth.users(id,instance_id,aud,role,email,is_anonymous,created_at,updated_at)
values('${owner}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','customer-race@example.test',false,now(),now());
insert into public.shops(id,name,owner_display_name,time_zone)
values('${shop}','متجر سباق العملاء','مالك السباق','Africa/Cairo');
insert into public.shop_memberships(shop_id,user_id,role) values('${shop}','${owner}','owner');
insert into public.shop_entitlements(shop_id,starts_at,expires_at)
values('${shop}',now()-interval '1 day',now()+interval '1 day');
${auth}
select public.post_customer_create_v1('${editCustomerKey}'::uuid, $json$${createPayload('أصل التعديل')}$json$::jsonb);
commit;`)
const base = parseResult(setup.output)
if (base.ok !== true || base.record_version !== '1' || !base.customer_id) {
  throw new Error(`base_customer ${JSON.stringify(base)}`)
}

const samePayload = createPayload('سباق متزامن')
const same = await Promise.all([
  call(`select public.post_customer_create_v1('${sameKey}'::uuid, $json$${samePayload}$json$::jsonb);`),
  call(`select public.post_customer_create_v1('${sameKey}'::uuid, $json$${samePayload}$json$::jsonb);`),
])
if (same.some((item) => item.code)) {
  throw new Error(`same_key_failed ${JSON.stringify(same)}`)
}
const sameParsed = same.map((item) => parseResult(item.output))
if (sameParsed.filter((item) => item.replayed === true).length !== 1) {
  throw new Error(`same_key_replay ${JSON.stringify(sameParsed)}`)
}
if (new Set(sameParsed.map((item) => item.customer_id)).size !== 1) {
  throw new Error(`same_key_identity ${JSON.stringify(sameParsed)}`)
}

const racedEdits = await Promise.all([
  call(`select public.post_customer_edit_v1('${editKeyA}'::uuid, $json$${editPayload(base.customer_id, 'تعديل أول')}$json$::jsonb);`),
  call(`select public.post_customer_edit_v1('${editKeyB}'::uuid, $json$${editPayload(base.customer_id, 'تعديل ثان')}$json$::jsonb);`),
])
const editMessages = racedEdits.map((item) => `${item.output}\n${item.error}`)
const editSuccesses = racedEdits.filter((item) => !item.code && item.output.includes('"ok": true'))
const stale = editMessages.filter((item) => item.includes('stale_customer'))
if (editSuccesses.length !== 1 || stale.length !== 1) {
  throw new Error(`stale_race ${JSON.stringify(racedEdits)}`)
}

const racedPhones = await Promise.all([
  call(`select public.post_customer_create_v1('${phoneKeyA}'::uuid, $json$${createPayload('هاتف أول', '01012345678')}$json$::jsonb);`),
  call(`select public.post_customer_create_v1('${phoneKeyB}'::uuid, $json$${createPayload('هاتف ثان', '٠١٠١٢٣٤٥٦٧٨')}$json$::jsonb);`),
])
const phoneMessages = racedPhones.map((item) => `${item.output}\n${item.error}`)
const phoneSuccesses = racedPhones.filter((item) => !item.code && item.output.includes('"ok": true'))
const conflicts = phoneMessages.filter((item) => item.includes('phone_conflict'))
if (phoneSuccesses.length !== 1 || conflicts.length !== 1) {
  throw new Error(`phone_race ${JSON.stringify(racedPhones)}`)
}

const check = await run(`begin;
select count(*) from public.customers where shop_id='${shop}' and display_name='سباق متزامن';
select count(*) from public.customer_command_requests where shop_id='${shop}' and idempotency_key='${sameKey}';
select record_version::text || ' ' || display_name from public.customers where id='${base.customer_id}';
select count(*) from public.customer_command_requests where shop_id='${shop}' and idempotency_key in ('${editKeyA}','${editKeyB}') and command_kind='customer_edit';
select count(*) from public.customer_phones where shop_id='${shop}' and normalized_number='+201012345678';
select count(*) from public.customer_command_requests where shop_id='${shop}' and idempotency_key in ('${phoneKeyA}','${phoneKeyB}');
select count(*) from public.financial_operations where shop_id='${shop}';
select count(*) from public.journal_postings where shop_id='${shop}';
select count(*) from public.shop_debts where shop_id='${shop}';
rollback;`)
const lines = check.output.split('\n').map((line) => line.trim()).filter((line) => line !== '')
const counts = lines.filter((line) => /^\d+$/.test(line))
const versionLine = lines.find((line) => /^\d+ /.test(line))
if (counts.length < 8 || !versionLine) {
  throw new Error(`check_shape ${JSON.stringify(check)}`)
}
const [sameCustomers, sameRequests, editRequests, phones, phoneRequests, operations, postings, debts] = counts.slice(-8)
if (
  sameCustomers !== '1' || sameRequests !== '1'
  || !versionLine.startsWith('2 ')
  || editRequests !== '1' || phones !== '1' || phoneRequests !== '1'
  || operations !== '0' || postings !== '0' || debts !== '0'
) {
  throw new Error(`race_effects ${JSON.stringify({ counts, versionLine })}`)
}
console.log(JSON.stringify({
  sameKey: 'replayed',
  staleVersion: 'one_edit_one_stale',
  phoneConflict: 'one_owner',
  financialOperations: 0,
}))
