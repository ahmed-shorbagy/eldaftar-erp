-- Shop image and R2 media contract smoke checks.
begin;
select plan(13);

select has_table('public', 'shop_image_assets', 'shop image assets table exists');
select has_column('public', 'shops', 'image_asset_id', 'shops reference current image');
select has_column('public', 'shop_image_assets', 'object_key', 'r2 object key column exists');
select has_column('public', 'shop_image_assets', 'storage', 'storage kind column exists');
select has_function('public', 'set_shop_image_v1', array['text'], 'set shop image rpc');
select has_function(
  'public',
  'record_shop_image_v1',
  array['text', 'text', 'text', 'integer', 'integer', 'integer'],
  'record r2 shop image rpc'
);
select has_function('public', 'get_shop_image_v1', array[]::text[], 'get shop image rpc');
select has_function('public', 'clear_shop_image_v1', array[]::text[], 'clear shop image rpc');
select has_table('public', 'r2_media_objects', 'verified r2 media registry exists');
select ok(
  not has_function_privilege('authenticated', 'public.set_shop_image_v1(text)', 'execute'),
  'inline shop image bytes are closed to clients'
);
select ok(
  not has_function_privilege('authenticated',
    'public.record_r2_media_object_v1(uuid,uuid,text,text,bigint,text,text)', 'execute'),
  'only the r2-media function records verified objects'
);
select ok(
  not has_table_privilege('authenticated', 'public.r2_media_objects', 'insert'),
  'clients cannot write the registry'
);
select has_function('public', 'confirm_invoice_logo_v2', array['text'], 'r2 invoice logo confirm rpc');

select * from finish();
rollback;
