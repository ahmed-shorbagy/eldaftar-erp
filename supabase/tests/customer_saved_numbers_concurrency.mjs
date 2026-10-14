// Real independent connections in the disposable CRM-05 cluster only.
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const url=new URL(process.env.SUPABASE_TEST_DATABASE_URL??'http://invalid');
if(url.protocol!=='postgresql:'||url.hostname!=='127.0.0.1'||url.port!=='55452'||url.pathname!=='/eldaftar_customer_saved_numbers')throw Error('dedicated_local_database_required');
const owner=randomUUID(),shop=randomUUID();
const auth=`set local role authenticated;select set_config('request.jwt.claim.sub','${owner}',true);select set_config('request.jwt.claims','{"sub":"${owner}","role":"authenticated","is_anonymous":false}',true);set local statement_timeout='15s';`;
function run(sql){return new Promise((resolve,reject)=>{const p=spawn(process.env.PSQL??'psql',[url.href,'-X','-q','-t','-A','-v','ON_ERROR_STOP=1'],{stdio:['pipe','pipe','pipe'],env:{...process.env,PGCLIENTENCODING:'UTF8'}});let output='',error='';p.stdout.on('data',d=>output+=d);p.stderr.on('data',d=>error+=d);p.on('error',reject);p.on('close',code=>resolve({code,output:output.trim(),error}));p.stdin.end(sql);});}
function result(r){assert.equal(r.code,0,r.error);return r.output.split('\n').filter(x=>x.startsWith('{')).map(x=>JSON.parse(x)).findLast(x=>x.ok===true);}
function call(name,key,payload){return run(`begin;${auth}select public.${name}('${key}','${JSON.stringify(payload)}'::jsonb);commit;`);}
const fixture=await run(`begin;insert into auth.users(id,instance_id,aud,role,email,is_anonymous,created_at,updated_at)values('${owner}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','crm05-${owner}@example.test',false,now(),now());insert into public.shops(id,name,owner_display_name,time_zone)values('${shop}','محل سباق الإقرار','مالك السباق','Africa/Cairo');insert into public.shop_memberships(shop_id,user_id,role)values('${shop}','${owner}','owner');insert into public.shop_entitlements(shop_id,starts_at,expires_at)values('${shop}',now()-interval '1 day',now()+interval '1 day');commit;`);assert.equal(fixture.code,0,fixture.error);
const created=result(await call('post_customer_create_v1',randomUUID(),{version:1,kind:'customer_create',display_name:'عميل سباق',phones:[{number:'01012345678',is_primary:true}],is_vip:false,has_open_request:false}));
const current=await run(`begin;${auth}select public.get_customer_v3('${created.customer_id}',20,null,20,null,20,null);commit;`);assert.equal(current.code,0,current.error);
const customer=JSON.parse(current.output.split('\n').findLast(x=>x.includes('saved_number_policy')));
const base={version:1,kind:'customer_saved_number',customer_id:customer.customer_id,expected_version:'1',number_id:customer.phones[0].saved_number.number_id,normalized_number:customer.phones[0].normalized,state:'saved'};
const key=randomUUID();const duplicate=await Promise.all([call('post_customer_saved_number_v1',key,base),call('post_customer_saved_number_v1',key,base)]);
const receipts=duplicate.map(result);assert.deepEqual(receipts[0].phones,receipts[1].phones);assert.equal(receipts.filter(r=>r.replayed).length,1);
const stale=await Promise.all([call('post_customer_saved_number_v1',randomUUID(),{...base,expected_version:'2',state:'not_saved'}),call('post_customer_saved_number_v1',randomUUID(),{...base,expected_version:'2',state:'unknown'})]);
assert.equal(stale.filter(r=>r.code===0).length,1);assert.ok(stale.find(r=>r.code!==0).error.includes('stale_customer'));
const removed=await Promise.all([call('post_customer_saved_number_v1',randomUUID(),{...base,expected_version:'3'}),call('post_customer_edit_v1',randomUUID(),{version:1,kind:'customer_edit',customer_id:customer.customer_id,expected_version:'3',display_name:'عميل سباق',phones:[]})]);
assert.equal(removed.filter(r=>r.code===0).length,1);assert.ok(removed.find(r=>r.code!==0).error.includes('stale_customer'));
const check=await run(`select jsonb_build_object('events',(select count(*) from public.customer_number_events where customer_id='${customer.customer_id}'),'version',(select record_version from public.customers where id='${customer.customer_id}'),'requests',(select count(*) from public.customer_command_requests where customer_id='${customer.customer_id}'),'financial',(select count(*) from public.financial_operations where shop_id='${shop}'));`);assert.equal(check.code,0,check.error);const counts=JSON.parse(check.output);assert.equal(counts.version,4);assert.equal(counts.requests,4);assert.equal(counts.financial,0);assert.ok([2,3].includes(counts.events));
console.log(JSON.stringify({passed:'duplicate key once-only, competing version, removal/status serialization, exact event/request counts and zero finance'}));
