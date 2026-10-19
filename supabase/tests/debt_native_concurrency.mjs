// Dedicated disposable local database. Never accepts a hosted connection.
import {spawn} from 'node:child_process'
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {randomUUID} from 'node:crypto'
const connection=process.env.SUPABASE_TEST_DATABASE_URL
const u=new URL(connection??'http://invalid')
if(u.protocol!=='postgresql:'||u.hostname!=='127.0.0.1'||u.port!=='55454'||u.pathname!=='/eldaftar_debt_due')throw Error('dedicated_local_database_required')
const executable=process.env.PSQL??'psql'
function run(sql,allowFailure=false){return new Promise((resolve,reject)=>{
  const p=spawn(executable,[connection,'-X','-q','-t','-A','-v','ON_ERROR_STOP=1'],{stdio:['pipe','pipe','pipe']});let out='',err='';
  p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>err+=b);p.on('error',reject);p.on('close',code=>code&&!allowFailure?reject(Error(err)):resolve({code,out:out.trim(),err}));p.stdin.end(sql)
})}
function last(result){return JSON.parse(result.out.split('\n').filter(x=>x.startsWith('{')).at(-1))}
const folder=join(tmpdir(),'eldaftar-native-'+randomUUID());mkdirSync(folder)
const old=readFileSync(new URL('./debts_concurrency.mjs',import.meta.url),'utf8').replace("url.port !== '55447'","url.port !== '55454'").replace("url.pathname !== '/eldaftar_debts'","url.pathname !== '/eldaftar_debt_due'")
const file=join(folder,'old-debt-races.mjs');writeFileSync(file,old)
await new Promise((resolve,reject)=>{const p=spawn(process.execPath,[file],{stdio:'inherit'});p.on('error',reject);p.on('close',c=>c?reject(Error('legacy_debt_races')):resolve())})
const owner='d8d8d8d8-d8d8-48d8-88d8-d8d8d8d8d8d8',shop='d9d9d9d9-d9d9-49d9-89d9-d9d9d9d9d9d9'
const auth=`set local role authenticated;select set_config('request.jwt.claim.sub','${owner}',true);select set_config('request.jwt.claims','{"sub":"${owner}","role":"authenticated","is_anonymous":false}',true);`
const rpc=async(name,args)=>last(await run(`begin;${auth}select public.${name}(${args});commit;`))
const read=async(kind,id)=>{
 const due=await rpc('get_debt_due_v1',`'${kind}','${id}'`)
 if(!due.due_date) await rpc('post_debt_due_v1',`'${randomUUID()}','${JSON.stringify({version:1,kind:'debt_due',source_kind:kind,source_id:id,due_date:'2024-02-29',expected_due_version:due.due_version,expected_freshness:due.freshness})}'`)
 return rpc('get_debt_native_v1',`'${kind}','${id}'`)
}
const envelope=(r,time)=>({version:1,kind:'debt_native',source_kind:r.source_kind,source_id:r.source_id,reminder_time:time,expected_native_version:r.native_version,expected_freshness:r.native_freshness})
const send=(key,p,allowFailure=false)=>run(`begin;${auth}select public.post_debt_native_v1('${key}','${JSON.stringify(p)}');commit;`,allowFailure)
const declare=()=>rpc('post_debt_declare_v1',`'${randomUUID()}','{"version":1,"kind":"debt_declare","direction":"shop_owes","unit":"money","karat":null,"amount":"10000","party_name":"تزامن مواعيد ${randomUUID()}","contact_phone":"","reason":"اختبار","external_reference":null}'`)
const source=(await declare()).source_id
let row=await read('standalone',source),p=envelope(row,'16:00'),key=randomUUID()
const same=await Promise.all([send(key,p),send(key,p)])
if(same.map(last).filter(r=>r.replayed).length!==1)throw Error('duplicate_due_replay')
row=await read('standalone',source)
const competing=await Promise.all([send(randomUUID(),envelope(row,'17:00'),true),send(randomUUID(),envelope(row,'18:00'),true)])
if(competing.filter(r=>r.code===0).length!==1||!competing.find(r=>r.code)?.err.includes('stale_native'))throw Error('competing_due_versions')
const counts=last(await run(`select jsonb_build_object('events',(select count(*) from public.debt_native_events where source_id='${source}'),'requests',(select count(*) from public.debt_native_requests where result->>'source_id'='${source}'));`))
if(counts.events!==2||counts.requests!==2)throw Error('duplicate_due_effect')
const wait=async(name)=>run(`do $$begin for i in 1..250 loop perform pg_stat_clear_snapshot();if exists(select 1 from pg_stat_activity where application_name='${name}' and wait_event='PgSleep')then return;end if;perform pg_sleep(.02);end loop;raise exception 'interleave_missing';end$$;`)
const settlePayload=(r,amount)=>({version:1,kind:'debt_settle',source_kind:r.source_kind,source_id:r.source_id,direction:r.direction,unit:r.unit,karat:r.karat,amount:String(amount),expected_remaining:r.remaining_amount,expected_version:r.record_version,ledger_effect:'none',reason:'تزامن السداد',settlement_reference:randomUUID(),expected_day_id:null,expected_day_version:null,tenders:null,deliveries:null,receipt:null})
const archivePayload=r=>({version:1,kind:'debt_archive',source_kind:r.source_kind,source_id:r.source_id,expected_remaining:r.remaining_amount,expected_version:r.record_version,reason:'أرشفة متزامنة'})
async function sourceFirst(rpcName,payload,kind,id){
  const before=await read(kind,id),payloadDue=envelope(before,'19:00')
  const writer=run(`begin;set local application_name='due-source-writer';select 1 from public.shops where id='${shop}' for update;select pg_sleep(1);${auth}select public.${rpcName}('${randomUUID()}','${JSON.stringify(payload)}');commit;`)
  await wait('due-source-writer');const date=send(randomUUID(),payloadDue,true)
  await writer;const outcome=await date;if(outcome.code===0||!outcome.err.includes('stale_native'))throw Error('stale_source_review_'+rpcName)
  const after=await read(kind,id);if(after.reminder_time!==before.reminder_time || after.native_version!==before.native_version)throw Error('source_cleared_date_'+rpcName)
  return after
}
row=await read('standalone',source)
row=await sourceFirst('post_debt_settle_v1',settlePayload(row,1000),'standalone',source)
if(row.remaining_amount!=='9000'||row.due_state!=='overdue')throw Error('partial_due_remaining')
row=await sourceFirst('post_debt_archive_v1',archivePayload(row),'standalone',source)
if(row.due_state!=='inactive'||row.remaining_amount!=='9000')throw Error('archive_due_remaining')

await run(`-- Disposable-database fixture only. Restores return writes revoked by ledger trade edit/delete.
grant execute on function public.post_daily_ledger_return(uuid, uuid, text) to authenticated;
grant execute on function public.post_linked_return_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_exchange_v1(uuid, jsonb) to authenticated;`)
const purchase=await rpc('post_daily_ledger_trade',`'${randomUUID()}','{"version":1,"kind":"purchase","total_piastres":"8000","tenders":[],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"2000","count":"2","item_name":"رصيد اختبار","line_price_piastres":null}],"description":"","customer_name":"تاجر تزامن","customer_phone":"","note":"","purchase_obligation_piastres":"8000"}'`)
const payable=purchase.operation_id
await send(randomUUID(),envelope(await read('purchase_cash_payable',payable),'16:00'))
for(const amount of ['4000','4000']){
  const day=await rpc('get_daily_ledger_day_state','')
  const returned={version:1,kind:'purchase_return',original_operation_id:payable,expected_day_id:day.business_day_id,expected_day_version:String(day.day_version),note:'مرتجع متزامن',items:[{item_index:'0',milligrams:'1000',count:'1'}],consideration_piastres:amount,tenders:[]}
  row=await sourceFirst('post_linked_return_v1',returned,'purchase_cash_payable',payable)
}
if(row.remaining_amount!=='0'||row.reminder_time!=='16:00'||row.due_state!=='inactive'||row.cancelled_amount!=='8000'||row.settled_amount!=='0')throw Error('return_due_lifecycle')

let day=await rpc('get_daily_ledger_day_state','')
const gold=await rpc('post_gold_obligation_acquisition_v1',`'${randomUUID()}','${JSON.stringify({version:1,kind:'gold_obligation_acquisition',category:'worked_jewelry',karat:21,milligrams:'1000',count:'1',item_name:'ذهب تزامن',obligation_karat:21,obligation_milligrams:'800',counterparty_name:'تاجر تزامن ذهب',note:'',denomination_id:null,coin_type_id:null,expected_day_id:day.business_day_id,expected_day_version:String(day.day_version)})}'`)
const obligation=gold.operation_id
await send(randomUUID(),envelope(await read('gold_obligation',obligation),'16:00'))
const lots=(await run(`select id from public.inventory_lots where shop_id='${shop}' and category_code='scrap' and karat=21 and stock_class='owned_available';`)).out.split('\n').filter(x=>/^[a-f0-9-]{36}$/.test(x))
day=await rpc('get_daily_ledger_day_state','');row=await read('gold_obligation',obligation)
const goldSettle={...settlePayload(row,300),ledger_effect:'move',expected_day_id:day.business_day_id,expected_day_version:String(day.day_version),deliveries:[{lot_id:lots[0],milligrams:'300',count:null}]}
row=await sourceFirst('post_debt_settle_v1',goldSettle,'gold_obligation',obligation)
if(row.remaining_amount!=='500'||row.reminder_time!=='16:00')throw Error('partial_gold_date')
row=await sourceFirst('post_debt_archive_v1',archivePayload(row),'gold_obligation',obligation)
if(row.remaining_amount!=='500'||row.due_state!=='inactive')throw Error('archived_gold_date')

// A forced mid-read metadata commit must yield one complete old snapshot.
const stableSource=(await declare()).source_id
await send(randomUUID(),envelope(await read('standalone',stableSource),'16:00'))
const original=(await run("select pg_get_functiondef('public.get_debt_native_v1(text,uuid)'::regprocedure)")).out
await run(original.replace('select r into v_row','perform pg_sleep(1); select r into v_row'))
try{
  const before=await read('standalone',stableSource)
  const reading=run(`begin;set local application_name='due-snapshot-reader';${auth}select public.get_debt_native_v1('standalone','${stableSource}');rollback;`)
  await wait('due-snapshot-reader');await send(randomUUID(),envelope(before,'17:00'))
  const mid=last(await reading),after=await read('standalone',stableSource)
  if(mid.native_freshness!==before.native_freshness||mid.native_version!==before.native_version||after.native_freshness===before.native_freshness||after.reminder_time!=='17:00')throw Error('mixed_due_snapshot')
}finally{await run(original)}
const listDef=(await run("select pg_get_functiondef('public.get_debt_native_queue_v1(integer,text)'::regprocedure)")).out
const delayedList=listDef.replace('select coalesce(jsonb_agg(jsonb_build_object','perform pg_sleep(1); select coalesce(jsonb_agg(jsonb_build_object')
if(delayedList===listDef)throw Error('queue_snapshot_hook_missing')
await run(delayedList)
try{
  const before=await rpc('get_debt_native_queue_v1',"50, null")
  const reading=run(`begin;set local application_name='due-list-reader';${auth}select public.get_debt_native_queue_v1(50, null);rollback;`)
  await wait('due-list-reader');await send(randomUUID(),envelope(await read('standalone',stableSource),'18:00'))
  const mid=last(await reading),after=await rpc('get_debt_native_queue_v1',"50, null")
  if(mid.freshness!==before.freshness||JSON.stringify(mid.items)!==JSON.stringify(before.items)||after.freshness===before.freshness)throw Error('mixed_reminder_list_snapshot')
}finally{await run(listDef)}
console.log(JSON.stringify({passed:'legacy debt races; native same-key/competing versions; partial settlement/archive/partial-full purchase-return serialization; complete mid-read metadata snapshot',events:counts.events,requests:counts.requests}))
