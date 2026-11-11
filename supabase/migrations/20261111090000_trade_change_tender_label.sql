-- Trade edit accepts the stored tender label snapshot.
--
-- 20261027140000_payment_method_labels made the detail trigger
-- `private.snapshot_cash_labels_on_detail` store `label_ar` in every tender
-- and taught `private.validated_tender_sum` and `private.repair_tenders` to
-- accept that key. The trade-change path was not updated: the edit screen
-- starts from the stored payload, so `review_ledger_trade_change_v1` rejected
-- it with `invalid_input`, and a labeled replacement also failed inside
-- `post_ledger_trade_change_v1`. No sale or purchase posted after the label
-- migration could be edited (found in the 2026-11-11 device pass).
--
-- `label_ar` is a server snapshot: the detail trigger rewrites it from the
-- shop's account on insert, so a client value is never trusted. Both public
-- entry points now drop `label_ar` from each tender of `p_replacement` before
-- anything else, so review and post validate and hash the same payload. The
-- previous functions stay as `…_before_tender_label`, revoked.

begin;

create function private.trade_replacement_without_tender_labels(p_replacement jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $fn$
  select case
    when pg_catalog.jsonb_typeof(p_replacement) = 'object'
      and pg_catalog.jsonb_typeof(p_replacement -> 'tenders') = 'array'
    then p_replacement || pg_catalog.jsonb_build_object(
      'tenders',
      coalesce((
        select pg_catalog.jsonb_agg(
          case
            when pg_catalog.jsonb_typeof(tender.value) = 'object'
              and pg_catalog.jsonb_typeof(tender.value -> 'label_ar') = 'string'
              then tender.value - 'label_ar'
            else tender.value
          end
          order by tender.ordinality
        )
        from pg_catalog.jsonb_array_elements(p_replacement -> 'tenders')
          with ordinality as tender(value, ordinality)
      ), '[]'::jsonb)
    )
    else p_replacement
  end;
$fn$;

revoke all on function private.trade_replacement_without_tender_labels(jsonb)
  from public, anon, authenticated;

alter function public.review_ledger_trade_change_v1(uuid, text, jsonb)
  rename to review_ledger_trade_change_v1_before_tender_label;
revoke all on function public.review_ledger_trade_change_v1_before_tender_label(
  uuid, text, jsonb
) from public, anon, authenticated;

create function public.review_ledger_trade_change_v1(
  p_operation_id uuid,
  p_action text,
  p_replacement jsonb default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  return public.review_ledger_trade_change_v1_before_tender_label(
    p_operation_id,
    p_action,
    private.trade_replacement_without_tender_labels(p_replacement)
  );
end;
$fn$;

revoke all on function public.review_ledger_trade_change_v1(uuid, text, jsonb)
  from public, anon;
grant execute on function public.review_ledger_trade_change_v1(uuid, text, jsonb)
  to authenticated;

alter function public.post_ledger_trade_change_v1(
  uuid, uuid, text, jsonb, uuid, bigint, text, text
) rename to post_ledger_trade_change_v1_before_tender_label;
revoke all on function public.post_ledger_trade_change_v1_before_tender_label(
  uuid, uuid, text, jsonb, uuid, bigint, text, text
) from public, anon, authenticated;

create function public.post_ledger_trade_change_v1(
  p_idempotency_key uuid,
  p_operation_id uuid,
  p_action text,
  p_replacement jsonb,
  p_expected_day_id uuid,
  p_expected_day_version bigint,
  p_source_sha256 text,
  p_review_token text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  return public.post_ledger_trade_change_v1_before_tender_label(
    p_idempotency_key, p_operation_id, p_action,
    private.trade_replacement_without_tender_labels(p_replacement),
    p_expected_day_id, p_expected_day_version, p_source_sha256, p_review_token
  );
end;
$fn$;

revoke all on function public.post_ledger_trade_change_v1(
  uuid, uuid, text, jsonb, uuid, bigint, text, text
) from public, anon;
grant execute on function public.post_ledger_trade_change_v1(
  uuid, uuid, text, jsonb, uuid, bigint, text, text
) to authenticated;

notify pgrst, 'reload schema';
commit;
