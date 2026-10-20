-- Shop image contract smoke checks.
begin;
select plan(8);

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

select * from finish();
rollback;
