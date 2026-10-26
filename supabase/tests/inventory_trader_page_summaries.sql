-- Gap-fill summaries for instant inventory and trader list pending counts.
begin;
select plan(4);

select has_function('public', 'get_inventory_totals_v1', array['text', 'smallint']);
select has_function('public', 'search_traders_v1', array['text', 'integer', 'text']);

select ok(
  position('original_held_milligrams' in pg_get_functiondef('public.get_inventory_totals_v1(text,smallint)'::regprocedure)) > 0,
  'get_inventory_totals_v1 returns original_held_milligrams'
);

select ok(
  position('pending_receipt_count' in pg_get_functiondef('public.search_traders_v1(text,integer,text)'::regprocedure)) > 0,
  'search_traders_v1 returns pending_receipt_count'
);

select * from finish();
rollback;
