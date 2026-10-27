-- Period analytics RPCs exist with owner-only actor aggregation and reports grant.
begin;
select plan(6);

select has_function(
  'public', 'get_financial_period_analytics_v1', array['text', 'date']
);
select has_function(
  'public',
  'confirm_financial_period_analytics_pdf_v1',
  array['text', 'date', 'text', 'text']
);

select ok(
  position(
    'is_shop_owner' in pg_get_functiondef(
      'public.get_financial_period_analytics_v1(text,date)'::regprocedure
    )
  ) > 0,
  'analytics gates actor rows on shop owner'
);

select ok(
  position(
    '''month''' in pg_get_functiondef(
      'public.get_financial_period_analytics_v1(text,date)'::regprocedure
    )
  ) > 0,
  'analytics supports calendar month'
);

select ok(
  position(
    '''year''' in pg_get_functiondef(
      'public.get_financial_period_analytics_v1(text,date)'::regprocedure
    )
  ) > 0,
  'analytics supports calendar year'
);

select ok(
  position(
    'allow_member_permission' in pg_get_functiondef(
      'public.get_financial_period_analytics_v1(text,date)'::regprocedure
    )
  ) > 0,
  'analytics requires reports permission'
);

select * from finish();
rollback;
