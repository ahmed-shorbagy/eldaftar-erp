// Two owner sessions on one disposable local database. Reviews commit because
// they do not write. Posts share the shop row lock, so one change commits and
// the other sees the change row.
import { spawn } from 'node:child_process'
import { randomUUID } from 'node:crypto'

const connection = process.env.SUPABASE_TEST_DATABASE_URL
const url = new URL(connection ?? 'http://invalid')
if (
  url.protocol !== 'postgresql:'
  || url.hostname !== '127.0.0.1'
  || url.port !== '55469'
  || !/^\/eldaftar_trade_change[a-z0-9_]*$/.test(url.pathname)
) {
  throw new Error('dedicated_local_database_required')
}
const executable = process.env.PSQL ?? 'psql'

function run(sql, allowFailure = false) {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, [connection, '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1'], {
      stdio: ['pipe', 'pipe', 'pipe']
    })
    let output = ''
    let error = ''
    child.stdout.on('data', (chunk) => { output += chunk })
    child.stderr.on('data', (chunk) => { error += chunk })
    child.on('error', reject)
    child.on('close', (code) => {
      if (code && !allowFailure) reject(new Error(error || output))
      else resolve({ code, output: output.trim(), error })
    })
    child.stdin.end(sql)
  })
}

function jsonLine(result) {
  const line = result.output.split('\n').filter((item) => item.startsWith('{')).at(-1)
  if (!line) throw new Error(result.error || result.output || 'missing_json')
  return JSON.parse(line)
}

const owner = randomUUID()
const shop = randomUUID()
const auth = `set local role authenticated; select set_config('request.jwt.claim.sub','${owner}',true); select set_config('request.jwt.claim.session_id','',true);`
const saleBody = {
  version: 1,
  kind: 'sale',
  total_piastres: '10000',
  tenders: [{ method: 'cash', piastres: '10000' }],
  items: [{
    category: 'worked_jewelry',
    karat: 21,
    milligrams: '2000',
    count: '1',
    item_name: 'خاتم',
    line_price_piastres: null
  }],
  description: '',
  customer_name: '',
  customer_phone: '',
  note: ''
}

const setup = await run(`begin;
insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values ('${owner}', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'trade-race@example.test', false, now(), now());
insert into public.shops (id, name, owner_display_name, time_zone)
values ('${shop}', 'متجر تزامن التعديل', 'مالك التزامن', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values ('${shop}', '${owner}', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at)
values ('${shop}', now() - interval '1 day', now() + interval '30 days');
${auth}
select public.confirm_opening_balances('${randomUUID()}', '{"version":1,"cash":{"cash":"500000","card":"100000"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"20000","count":"4"}],"scrap":[]}');
select public.post_daily_ledger_trade('${randomUUID()}', $sale$${JSON.stringify(saleBody)}$sale$);
commit;`)
const sale = jsonLine(setup).operation_id

function review(operation, action, replacement) {
  const replacementSql = replacement == null ? 'null' : `$repl$${JSON.stringify(replacement)}$repl$`
  return run(`begin; ${auth} select public.review_ledger_trade_change_v1('${operation}', '${action}', ${replacementSql}); commit;`)
}

const edited = { ...saleBody, note: 'تعديل متزامن' }
const [deleteReview, editReview] = await Promise.all([
  review(sale, 'delete', null).then(jsonLine),
  review(sale, 'edit', edited).then(jsonLine)
])

function post(operation, key, reviewRow, action, replacement) {
  const replacementSql = replacement == null ? 'null' : `$repl$${JSON.stringify(replacement)}$repl$`
  return run(`begin; ${auth}
    select public.post_ledger_trade_change_v1(
      '${key}'::uuid,
      '${operation}'::uuid,
      '${action}',
      ${replacementSql},
      '${reviewRow.expected_day_id}'::uuid,
      ${Number(reviewRow.expected_day_version)},
      '${reviewRow.source_sha256}',
      '${reviewRow.review_token}'
    );
  commit;`, true)
}

const deleteKey = randomUUID()
const editKey = randomUUID()
const raced = await Promise.all([
  post(sale, deleteKey, deleteReview, 'delete', null),
  post(sale, editKey, editReview, 'edit', edited)
])
const winners = raced.filter((row) => row.code === 0)
const losers = raced.filter((row) => row.code !== 0)
if (winners.length !== 1 || losers.length !== 1 || !losers[0].error.includes('operation_replaced')) {
  throw new Error(`race:${JSON.stringify(raced.map((row) => ({ code: row.code, output: row.output, error: row.error })))}`)
}
const winner = jsonLine(winners[0])
if (winner.replayed !== false || winner.ok !== true) throw new Error(`winner:${JSON.stringify(winner)}`)
const winnerIsEdit = raced[1].code === 0
const winnerKey = winnerIsEdit ? editKey : deleteKey
const winnerReview = winnerIsEdit ? editReview : deleteReview
const winnerAction = winnerIsEdit ? 'edit' : 'delete'
const winnerReplacement = winnerIsEdit ? edited : null
const replay = jsonLine(await post(sale, winnerKey, winnerReview, winnerAction, winnerReplacement))
if (replay.replayed !== true || replay.operation_id !== winner.operation_id) {
  throw new Error(`replay:${JSON.stringify(replay)}`)
}
const mismatch = await post(
  sale,
  winnerKey,
  { ...winnerReview, review_token: 'a'.repeat(64) },
  winnerAction,
  winnerReplacement
)
if (!mismatch.code || !mismatch.error.includes('payload_mismatch')) {
  throw new Error(`mismatch:${mismatch.error || mismatch.output}`)
}

const second = jsonLine(await run(`begin; ${auth} select public.post_daily_ledger_trade('${randomUUID()}', $sale$${JSON.stringify(saleBody)}$sale$); commit;`)).operation_id
const secondReview = jsonLine(await review(second, 'delete', null))
const sameKey = randomUUID()
const same = await Promise.all([
  post(second, sameKey, secondReview, 'delete', null),
  post(second, sameKey, secondReview, 'delete', null)
])
if (same.some((row) => row.code)) {
  throw new Error(`same_key:${JSON.stringify(same.map((row) => ({ code: row.code, output: row.output, error: row.error })))}`)
}
const sameResults = same.map(jsonLine)
if (
  sameResults.filter((row) => row.replayed).length !== 1
  || sameResults[0].operation_id !== sameResults[1].operation_id
) {
  throw new Error(`same_key_result:${JSON.stringify(sameResults)}`)
}
const changes = jsonLine(await run(`select jsonb_build_object(
  'changes', (select count(*) from public.ledger_trade_changes where shop_id = '${shop}'),
  'sources', (select count(distinct source_operation_id) from public.ledger_trade_changes where shop_id = '${shop}')
);`))
if (Number(changes.changes) !== 2 || Number(changes.sources) !== 2) {
  throw new Error(`change_count:${JSON.stringify(changes)}`)
}
const status = jsonLine(await run(`begin; ${auth} select public.get_opening_status('${winnerKey}'); rollback;`))
if (status.status !== 'completed' || status.operation_id !== winner.operation_id) {
  throw new Error(`opening_status:${JSON.stringify(status)}`)
}
console.log(`PASS trade change race: one ${winnerAction} committed, peer operation_replaced, replay true, payload_mismatch, same-key one replay. changes=${changes.changes}`)
