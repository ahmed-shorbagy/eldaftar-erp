-- SET-02 / D24 payment method rename + archive RPCs and helpers.
begin;
select plan(8);

select has_function('public', 'list_shop_payment_methods_v1', array[]::text[]);
select has_function(
  'public', 'save_shop_payment_methods_v1', array['uuid', 'jsonb']
);
select has_column('public', 'ledger_accounts', 'display_label_ar');
select has_column('public', 'ledger_accounts', 'archived_at');

select ok(
  position(
    'method_archived' in pg_get_functiondef(
      'private.assert_active_cash_methods(uuid,jsonb)'::regprocedure
    )
  ) > 0,
  'assert rejects archived cash methods'
);

select ok(
  position(
    'label_ar' in pg_get_functiondef(
      'private.snapshot_cash_labels_on_detail()'::regprocedure
    )
  ) > 0,
  'detail trigger snapshots label_ar'
);

select ok(
  position(
    'relabel_ledger_cash' in pg_get_functiondef(
      'public.get_daily_ledger_v2()'::regprocedure
    )
  ) > 0,
  'ledger v2 relabels cash from accounts'
);

select ok(
  position(
    'require_shop_owner' in pg_get_functiondef(
      'public.save_shop_payment_methods_v1(uuid,jsonb)'::regprocedure
    )
  ) > 0,
  'save is owner-only'
);

select * from finish();
rollback;
