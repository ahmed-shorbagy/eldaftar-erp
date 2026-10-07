// Real independent PostgreSQL connections. Synthetic local fixture rows are
// retained in the disposable cluster; no audit or financial records are deleted.
import { spawn } from 'node:child_process'
const connection = process.env.SUPABASE_TEST_DATABASE_URL
const url = new URL(connection ?? 'http://invalid')
if (url.protocol !== 'postgresql:' || url.hostname !== '127.0.0.1' || url.port !== '55439' || url.pathname !== '/eldafttar_compensation_final5') throw new Error('dedicated_local_database_required')
const executable = process.env.PSQL ?? 'psql'
function run(sql, allowFailure = false) { return new Promise((resolve,reject) => {
  const child = spawn(executable,[connection,'-X','-q','-t','-A','-v','ON_ERROR_STOP=1'],{stdio:['pipe','pipe','pipe']})
  let output='',error='';child.stdout.on('data',c=>output+=c);child.stderr.on('data',c=>error+=c)
  child.on('error',reject);child.on('close',code=>code && !allowFailure ? reject(new Error(error)) : resolve({code,output:output.trim(),error}))
  child.stdin.end(sql)
}) }
const owner='e3e3e3e3-e3e3-43e3-83e3-e3e3e3e3e3e3',shop='f3f3f3f3-f3f3-43f3-83f3-f3f3f3f3f3f3'
const auth = `set local role authenticated; select set_config('request.jwt.claim.sub','${owner}',true);`
const setup = await run(`begin;
do $guard$ begin if exists(select 1 from auth.users where id='${owner}') or exists(select 1 from public.shops where id='${shop}') then raise exception 'fixture_collision'; end if; end; $guard$;
insert into auth.users(id,instance_id,aud,role,email,is_anonymous,created_at,updated_at) values('${owner}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','comp-race@example.test',false,now(),now());
insert into public.shops(id,name,owner_display_name,time_zone) values('${shop}','متجر اختبار تزامن','مالك اختبار','Africa/Cairo');
insert into public.shop_memberships(shop_id,user_id,role) values('${shop}','${owner}','owner');
insert into public.shop_entitlements(shop_id,starts_at,expires_at) values('${shop}',now()-interval '1 day',now()+interval '1 day');
${auth}
select public.confirm_opening_balances('c3000000-0000-4000-8000-000000000001','{"version":1,"cash":{"cash":"500000"},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"10000","count":"4"}],"scrap":[]}');
select public.post_daily_ledger_trade('c3000000-0000-4000-8000-000000000002','{"version":1,"kind":"sale","total_piastres":"10000","tenders":[{"method":"cash","piastres":"10000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"5000","count":"2","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}');commit;`)
const sale=JSON.parse(setup.output.split('\n').filter(l=>l.startsWith('{')).at(-1)).operation_id
async function anchor() { const r=await run(`begin;${auth}select public.get_daily_ledger_day_state();rollback;`);return JSON.parse(r.output.split('\n').filter(l=>l.startsWith('{')).at(-1)) }
let day=await anchor()
const payload={version:1,kind:'sale_return',original_operation_id:sale,expected_day_id:day.business_day_id,expected_day_version:String(day.day_version),note:'مرتجع تزامن',items:[{item_index:'0',milligrams:'2001',count:'1'}],consideration_piastres:'3000',tenders:[{method:'cash',piastres:'3000'}]}
function post(key,body) { return run(`begin;${auth}select public.post_linked_return_v1('${key}','${JSON.stringify(body)}');commit;`,true) }
const key='c3000000-0000-4000-8000-000000000003'
const same=await Promise.all([post(key,payload),post(key,payload)])
if(same.some(r=>r.code)) throw new Error(JSON.stringify(same))
const results=same.map(r=>JSON.parse(r.output.split('\n').filter(l=>l.startsWith('{')).at(-1)))
if(results[0].operation_id!==results[1].operation_id || results.filter(r=>r.replayed).length!==1) throw new Error('same_key_duplicate')
const changed=await post(key,{...payload,note:'طلب مختلف'})
if(!changed.code || !changed.error.includes('payload_mismatch')) throw new Error('changed_payload_accepted')
day=await anchor()
const remaining={...payload,expected_day_version:String(day.day_version),items:[{item_index:'0',milligrams:'2999',count:'1'}],consideration_piastres:'7000',tenders:[{method:'cash',piastres:'7000'}]}
const competing=await Promise.all([post('c3000000-0000-4000-8000-000000000004',remaining),post('c3000000-0000-4000-8000-000000000005',remaining)])
if(competing.filter(r=>!r.code).length!==1 || !competing.find(r=>r.code)?.error.includes('stale_day')) throw new Error('competing_returns_duplicated')
day=await anchor()
const over=await post('c3000000-0000-4000-8000-000000000006',{...remaining,expected_day_version:String(day.day_version)})
if(!over.code || !over.error.includes('already_returned')) throw new Error('cumulative_return_accepted')
const check=await run(`begin;${auth}select jsonb_build_object('bounds',public.get_return_remainder_v1('${sale}'),'ops',(select count(*) from public.financial_operations where shop_id='${shop}'),'audits',(select count(*) from public.financial_audit_events where shop_id='${shop}'),'requests',(select count(*) from public.financial_command_requests where shop_id='${shop}'));rollback;`)
const state=JSON.parse(check.output.split('\n').filter(l=>l.startsWith('{')).at(-1))
if(!state.bounds.fully_returned || state.ops!==4 || state.audits!==4 || state.requests!==4) throw new Error('race_totals_mismatch')
console.log('PASS: two connections, same-key replay, changed payload rejection, competing stale return, cumulative bounds and exact operation/audit/request counts. Local fixture retained; no hosted creation.')
