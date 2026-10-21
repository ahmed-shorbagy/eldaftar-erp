select proname,
  pg_get_functiondef(oid) like '%انستا%' as has_insta,
  pg_get_functiondef(oid) like '%تحويل فوري%' as has_old,
  pg_get_functiondef(oid) like '%إنستا باي%' as has_instapay
from pg_proc
where proname in ('get_ledger_date_v1','get_ledger_operation_page');
