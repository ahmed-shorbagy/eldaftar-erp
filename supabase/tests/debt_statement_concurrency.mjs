// Disposable local connections only. Existing debt races stay independently
// executable; add a forced mid-read settlement/archive interleave here.
import {spawn} from 'node:child_process'
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs'
import {tmpdir} from 'node:os'
import {join} from 'node:path'
import {randomUUID} from 'node:crypto'
const connection=process.env.SUPABASE_TEST_DATABASE_URL
const u=new URL(connection??'http://invalid')
if(u.protocol!=='postgresql:'||u.hostname!=='127.0.0.1'||u.port!=='55453'||u.pathname!=='/eldaftar_debt_statement') throw Error('dedicated_local_database_required')
const executable=process.env.PSQL??'psql'
function run(sql) {return new Promise((resolve,reject)=>{
  const p=spawn(executable,[connection,'-X','-q','-t','-A','-v','ON_ERROR_STOP=1'],{stdio:['pipe','pipe','pipe']})
  let out='',err='';p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>err+=b)
  p.on('error',reject);p.on('close',c=>c?reject(Error(err)):resolve(out.trim()));p.stdin.end(sql)
})}
const folder=join(tmpdir(),'eldaftar-statement-'+randomUUID());mkdirSync(folder)
const old=readFileSync(new URL('./debts_concurrency.mjs',import.meta.url),'utf8').replace("url.port !== '55447'","url.port !== '55453'").replace("url.pathname !== '/eldaftar_debts'","url.pathname !== '/eldaftar_debt_statement'")
const file=join(folder,'debt-races.mjs');writeFileSync(file,old)
await new Promise((resolve,reject)=>{const p=spawn(process.execPath,[file],{stdio:'inherit'});p.on('close',c=>c?reject(Error('debt_races')):resolve());p.on('error',reject)})
const owner='d8d8d8d8-d8d8-48d8-88d8-d8d8d8d8d8d8'
const shop='d9d9d9d9-d9d9-49d9-89d9-d9d9d9d9d9d9'
const auth=`set local role authenticated;select set_config('request.jwt.claim.sub','${owner}',true);select set_config('request.jwt.claims','{"sub":"${owner}","role":"authenticated","is_anonymous":false}',true);`
const rows=await run(`begin;${auth}select id from public.shop_debts where shop_id='${shop}' and remaining_amount=4000;rollback;`)
const source=rows.split('\n').filter(x=>/^[a-f0-9-]{36}$/.test(x)).at(-1)
if(!source) throw Error('statement_fixture_missing')
const originalDef=await run("select pg_get_functiondef('private.debt_statement_content_v1(uuid,text,uuid)'::regprocedure)")
await run(originalDef.replace('v_history :=','perform pg_catalog.pg_sleep(2); v_history :='))
try {
  for(const kind of ['settlement','archive']) {
    const before=JSON.parse((await run(`begin;${auth}select public.get_debt_statement_v1('standalone','${source}');rollback;`)).split('\n').filter(x=>x.startsWith('{')).at(-1))
    const reading=run(`begin;set local application_name='statement-snapshot-probe';${auth}select public.get_debt_statement_v1('standalone','${source}');rollback;`)
    await run("do $$begin for i in 1..250 loop perform pg_stat_clear_snapshot(); if exists(select 1 from pg_stat_activity where application_name='statement-snapshot-probe' and wait_event='PgSleep') then return;end if;perform pg_sleep(.02);end loop;raise exception 'reader_not_interleaved';end$$;")
    const key=randomUUID()
    const payload=kind==='archive'?{version:1,kind:'debt_archive',source_kind:'standalone',source_id:source,expected_remaining:before.remaining_amount,expected_version:kind==='archive'?'3':'2',reason:'أرشفة متزامنة'}:
      {version:1,kind:'debt_settle',source_kind:'standalone',source_id:source,direction:'shop_owes',unit:'money',karat:null,amount:'1000',expected_remaining:before.remaining_amount,expected_version:'2',ledger_effect:'none',reason:'سداد متزامن',settlement_reference:randomUUID(),expected_day_id:null,expected_day_version:null,tenders:null,deliveries:null,receipt:null}
    await run(`begin;${auth}select public.${kind==='archive'?'post_debt_archive_v1':'post_debt_settle_v1'}('${key}','${JSON.stringify(payload)}');commit;`)
    const mid=JSON.parse((await reading).split('\n').filter(x=>x.startsWith('{')).at(-1))
    const after=JSON.parse((await run(`begin;${auth}select public.get_debt_statement_v1('standalone','${source}');rollback;`)).split('\n').filter(x=>x.startsWith('{')).at(-1))
    if(mid.freshness!==before.freshness||after.freshness===before.freshness) throw Error('mixed_statement_snapshot_'+kind)
    console.log(JSON.stringify({snapshot:kind,result:'old complete snapshot during write; new complete snapshot afterward'}))
  }
  const purchase={version:1,kind:'purchase',total_piastres:'8000',tenders:[],items:[{category:'worked_jewelry',karat:21,milligrams:'1000',count:'1',item_name:'خاتم آجل',line_price_piastres:null}],description:'',customer_name:'تاجر متزامن',customer_phone:'',note:'',purchase_obligation_piastres:'8000'}
  const acquired=JSON.parse((await run(`begin;${auth}select public.post_daily_ledger_trade('${randomUUID()}','${JSON.stringify(purchase)}');commit;`)).split('\n').filter(x=>x.startsWith('{')).at(-1))
  const payable=acquired.operation_id
  const before=JSON.parse((await run(`begin;${auth}select public.get_debt_statement_v1('purchase_cash_payable','${payable}');rollback;`)).split('\n').filter(x=>x.startsWith('{')).at(-1))
  const day=JSON.parse((await run(`begin;${auth}select public.get_daily_ledger_day_state();rollback;`)).split('\n').filter(x=>x.startsWith('{')).at(-1))
  const reading=run(`begin;set local application_name='statement-snapshot-probe';${auth}select public.get_debt_statement_v1('purchase_cash_payable','${payable}');rollback;`)
  await run("do $$begin for i in 1..250 loop perform pg_stat_clear_snapshot(); if exists(select 1 from pg_stat_activity where application_name='statement-snapshot-probe' and wait_event='PgSleep') then return;end if;perform pg_sleep(.02);end loop;raise exception 'reader_not_interleaved';end$$;")
  const returned={version:1,kind:'purchase_return',original_operation_id:payable,expected_day_id:day.business_day_id,expected_day_version:String(day.day_version),note:'مرتجع متزامن',items:[{item_index:'0',milligrams:'1000',count:'1'}],consideration_piastres:'8000',tenders:[]}
  await run(`begin;${auth}select public.post_linked_return_v1('${randomUUID()}','${JSON.stringify(returned)}');commit;`)
  const mid=JSON.parse((await reading).split('\n').filter(x=>x.startsWith('{')).at(-1))
  const after=JSON.parse((await run(`begin;${auth}select public.get_debt_statement_v1('purchase_cash_payable','${payable}');rollback;`)).split('\n').filter(x=>x.startsWith('{')).at(-1))
  if(mid.freshness!==before.freshness || mid.remaining_amount!=='8000' || after.remaining_amount!=='0' || after.cancelled_amount!=='8000' || after.settled_amount!=='0') throw Error('mixed_purchase_return_snapshot')
  console.log(JSON.stringify({snapshot:'purchase return',result:'old complete source during return; new cancellation separated from payment afterward'}))
} finally {await run(originalDef)}
