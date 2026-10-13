// Two real local connections. Synthetic rows stay in the disposable debt cluster.
import { spawn } from 'node:child_process'

const connection = process.env.SUPABASE_TEST_DATABASE_URL
const url = new URL(connection ?? 'http://invalid')
if (
  url.protocol !== 'postgresql:' ||
  url.hostname !== '127.0.0.1' ||
  url.port !== '55447' ||
  url.pathname !== '/eldaftar_debts'
) {
  throw new Error('dedicated_local_database_required')
}

const executable = process.env.PSQL ?? 'psql'
const owner = 'd8d8d8d8-d8d8-48d8-88d8-d8d8d8d8d8d8'
const shop = 'd9d9d9d9-d9d9-49d9-89d9-d9d9d9d9d9d9'

function run(sql, allowFailure = false) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      executable,
      [connection, '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1'],
      { stdio: ['pipe', 'pipe', 'pipe'] },
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

const auth = `set local role authenticated; select set_config('request.jwt.claim.sub','${owner}',true); select set_config('request.jwt.claims','{"sub":"${owner}","role":"authenticated","is_anonymous":false}',true);`
const setup = await run(`begin;
do $guard$ begin
  if exists(select 1 from auth.users where id='${owner}')
    or exists(select 1 from public.shops where id='${shop}') then
    raise exception 'fixture_collision';
  end if;
end; $guard$;
insert into auth.users(id,instance_id,aud,role,email,is_anonymous,created_at,updated_at)
values('${owner}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','debt-race@example.test',false,now(),now());
insert into public.shops(id,name,owner_display_name,time_zone)
values('${shop}','متجر سباق الديون','مالك السباق','Africa/Cairo');
insert into public.shop_memberships(shop_id,user_id,role) values('${shop}','${owner}','owner');
insert into public.shop_entitlements(shop_id,starts_at,expires_at)
values('${shop}',now()-interval '1 day',now()+interval '1 day');
${auth}
select public.confirm_opening_balances('d3000000-0000-4000-8000-000000000101','{"version":1,"cash":{"cash":"500000","wallet":"100000"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"5000","count":"1"}],"scrap":[{"karat":21,"milligrams":"3000"}]}');
select public.post_debt_declare_v1('d3000000-0000-4000-8000-000000000102','{"version":1,"kind":"debt_declare","direction":"shop_owes","unit":"money","karat":null,"amount":"10000","party_name":"سباق","contact_phone":"","reason":"رصيد السباق","external_reference":null}');
select public.post_debt_declare_v1('d3000000-0000-4000-8000-000000000103','{"version":1,"kind":"debt_declare","direction":"shop_owes","unit":"money","karat":null,"amount":"4000","party_name":"إعادة","contact_phone":"","reason":"نفس المفتاح","external_reference":null}');
commit;`)
const lines = setup.output.split('\n').filter((line) => line.startsWith('{'))
const firstDebt = JSON.parse(lines[lines.length - 2])
const secondDebt = JSON.parse(lines[lines.length - 1])
const dayResult = await run(`begin;${auth}select public.get_daily_ledger_day_state();rollback;`)
let day = JSON.parse(dayResult.output.split('\n').filter((line) => line.startsWith('{')).at(-1))

function settle(key, sourceId, amount, remaining, reference) {
  const payload = {
    version: 1,
    kind: 'debt_settle',
    source_kind: 'standalone',
    source_id: sourceId,
    direction: 'shop_owes',
    unit: 'money',
    karat: null,
    amount: String(amount),
    expected_remaining: String(remaining),
    expected_version: '1',
    ledger_effect: 'move',
    reason: 'سداد متزامن',
    settlement_reference: reference,
    expected_day_id: day.business_day_id,
    expected_day_version: String(day.day_version),
    tenders: [{ method: 'cash', piastres: String(amount) }],
    deliveries: null,
    receipt: null,
  }
  return run(
    `begin;${auth}select public.post_debt_settle_v1('${key}','${JSON.stringify(payload)}');commit;`,
    true,
  )
}

const raced = await Promise.all([
  settle(
    'd3000000-0000-4000-8000-000000000111',
    firstDebt.source_id,
    6000,
    10000,
    'd3000000-0000-4000-8000-000000000111',
  ),
  settle(
    'd3000000-0000-4000-8000-000000000112',
    firstDebt.source_id,
    6000,
    10000,
    'd3000000-0000-4000-8000-000000000112',
  ),
])
const messages = raced.map((item) => `${item.output}\n${item.error}`)
const successes = raced.filter((item) => !item.code && item.output.includes('"ok": true'))
const stale = messages.filter((item) => item.includes('stale_debt'))
if (successes.length !== 1 || stale.length !== 1) {
  throw new Error(`race_shape ${JSON.stringify(raced)}`)
}

const refreshed = await run(`begin;${auth}
select day.day_version::text || ' ' || day.id::text
from public.business_days as day
where day.shop_id = '${shop}' and day.status = 'open'
order by day.opened_at desc
limit 1;
rollback;`)
const versionLine = refreshed.output
  .split('\n')
  .map((line) => line.trim())
  .filter((line) => /^\d+ /.test(line))
  .at(-1)
if (!versionLine) throw new Error(`day_refresh ${JSON.stringify(refreshed)}`)
const [version, id] = versionLine.split(' ')
day = { business_day_id: id, day_version: version }
const sameKey = 'd3000000-0000-4000-8000-000000000121'
const same = await Promise.all([
  settle(sameKey, secondDebt.source_id, 1000, 4000, sameKey),
  settle(sameKey, secondDebt.source_id, 1000, 4000, sameKey),
])
if (same.some((item) => item.code)) {
  throw new Error(JSON.stringify({ day, same }))
}
const parsed = same.map((item) =>
  JSON.parse(item.output.split('\n').filter((line) => line.startsWith('{')).at(-1)),
)
if (parsed.filter((item) => item.replayed === true).length !== 1) {
  throw new Error(`same_key_replay ${JSON.stringify(parsed)}`)
}
if (parsed.some((item) => item.remaining_amount !== '3000')) {
  throw new Error(`same_key_remaining ${JSON.stringify(parsed)}`)
}

const check = await run(`begin;${auth}
select remaining_amount::text from public.shop_debts where id='${firstDebt.source_id}';
select remaining_amount::text from public.shop_debts where id='${secondDebt.source_id}';
rollback;`)
const remainings = check.output
  .split('\n')
  .map((line) => line.trim())
  .filter((line) => /^\d+$/.test(line))
if (remainings.at(-2) !== '4000' || remainings.at(-1) !== '3000') {
  throw new Error(`balances ${remainings.join(',')}`)
}
console.log(JSON.stringify({ partialRace: 'one_settlement_one_stale', sameKey: 'replayed' }))
