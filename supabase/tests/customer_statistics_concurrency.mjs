// Two real connections in the disposable CRM-02 cluster; no remote database.
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { randomUUID } from 'node:crypto'

const connection = process.env.SUPABASE_TEST_DATABASE_URL
const url = new URL(connection ?? 'http://invalid')
if (url.hostname !== '127.0.0.1' || url.port !== '55449' ||
    url.pathname !== '/eldaftar_customer_statistics' || url.protocol !== 'postgresql:') {
  throw Error('dedicated_local_database_required')
}
const user = randomUUID(), shop = randomUUID(), session = randomUUID()
const psql = process.env.PSQL ?? 'psql'
const claims = JSON.stringify({ sub: user, role: 'authenticated', session_id: session, is_anonymous: false })
const owner = `begin; set local role authenticated; set local request.jwt.claim.sub='${user}'; set local request.jwt.claims='${claims}';`
function run(sql) {
  return new Promise((resolve, reject) => {
    const child = spawn(psql, [connection, '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1'],
      { stdio: ['pipe', 'pipe', 'pipe'], env: { ...process.env, PGCLIENTENCODING: 'UTF8' } })
    let output = '', errors = ''
    child.stdout.on('data', x => { output += x })
    child.stderr.on('data', x => { errors += x })
    child.on('error', reject)
    child.on('close', code => code ? reject(Error(errors)) : resolve(output.trim()))
    child.stdin.end(sql)
  })
}
await run(`insert into auth.users(id,instance_id,aud,role,email,is_anonymous,created_at,updated_at)
 values('${user}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','stats-${user}@example.test',false,now(),now());
 insert into public.shops(id,name,owner_display_name,time_zone) values('${shop}','متجر التزامن الاصطناعي','مالك اصطناعي','Africa/Cairo');
 insert into public.shop_memberships(shop_id,user_id,role) values('${shop}','${user}','owner');
 insert into public.shop_entitlements(shop_id,starts_at,expires_at) values('${shop}',now()-interval '1 day',now()+interval '1 day');
 insert into auth.sessions(id,user_id,created_at,updated_at,not_after) values('${session}','${user}',now(),now(),now()+interval '1 day');
 create function private.statistics_snapshot_probe(p_id uuid) returns jsonb language plpgsql stable security definer set search_path='' as $f$
 declare before jsonb; after jsonb;
 begin
 before:=public.get_customer_v2(p_id,20,null,20,null,20,null)->'statistics';
 perform pg_advisory_lock(902111); perform pg_sleep(2);
 after:=public.get_customer_v2(p_id,20,null,20,null,20,null)->'statistics';
 perform pg_advisory_unlock(902111);
 return jsonb_build_object('before',before,'after',after);
 end;$f$;
 revoke all on function private.statistics_snapshot_probe(uuid) from public,anon;
 grant execute on function private.statistics_snapshot_probe(uuid) to authenticated;`)
const fixture = JSON.parse(await run(`${owner}
 do $f$ begin perform public.confirm_opening_balances(gen_random_uuid(),'{"version":1,"cash":{"cash":"500000"},"stock":[],"scrap":[]}');end;$f$;
 create temporary table fixture(customer jsonb,operation uuid);
 insert into fixture values(public.post_customer_create_v1(gen_random_uuid(),'{"version":1,"kind":"customer_create","display_name":"عميل تزامن اصطناعي","phones":[],"is_vip":false,"has_open_request":false}'),
 (public.post_daily_ledger_trade(gen_random_uuid(),'{"version":1,"kind":"purchase","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"scrap","karat":21,"milligrams":"10001","count":null,"item_name":"كسر اصطناعي","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}')->>'operation_id')::uuid);
 update fixture set customer=public.post_customer_link_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','customer_link','customer_id',customer->>'customer_id','expected_version',customer->>'record_version','operation_id',operation));
 select jsonb_build_object('customer',customer,'operation',operation) from fixture;commit;`))
const id = fixture.customer.customer_id
const reading = run(`${owner}select private.statistics_snapshot_probe('${id}');commit;`)
const deadline = Date.now() + 10000
while ((await run('select count(*) from pg_locks where locktype=\'advisory\' and objid=902111 and granted;')) !== '1') {
  assert.ok(Date.now() < deadline, 'reader did not enter its snapshot')
  await new Promise(resolve => setTimeout(resolve, 50))
}
await run(`${owner}do $f$ begin perform public.post_customer_unlink_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','customer_unlink','customer_id','${id}','expected_version','${fixture.customer.record_version}','operation_id','${fixture.operation}'));end;$f$;commit;`)
const snapshot = JSON.parse(await reading)
assert.deepEqual(snapshot.before, snapshot.after)
assert.equal(snapshot.before.sold_count, '1')
assert.equal(snapshot.before.weights.find(w => w.karat === 21).sold_milligrams, '10001')
const fresh = JSON.parse(await run(`${owner}select public.get_customer_v2('${id}',20,null,20,null,20,null)->'statistics';commit;`))
assert.equal(fresh.sold_count, '0')
assert.equal(fresh.last_operation, null)
await run('drop function private.statistics_snapshot_probe(uuid);')
console.log(JSON.stringify({ passed: 'two-connection read snapshot stays consistent across committed unlink; next read refreshes', connections: 2 }))
