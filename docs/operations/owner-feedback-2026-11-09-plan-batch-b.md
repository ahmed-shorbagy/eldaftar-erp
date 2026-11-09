# Owner voice notes (2026-11-09), batch B: «بيانات العملاء» and «الجرد الفوري»

Status: planned. Nothing implemented yet.
Scope: the Flutter app (Android, iOS, Windows) and the Supabase backend it calls. The React admin dashboard is out of scope.
Source: 10 owner voice notes received 2026-11-09 (FB-001 … FB-010). This batch covers FB-001, FB-002, FB-003 and the inventory part of FB-004. [Batch A](owner-feedback-2026-11-09-plan-batch-a.md) covers the rest.
Decision record to write: ADR 0043 (task B0.1).

Follow this plan step by step. Every task names its files, the exact Arabic copy, the widget keys tests use, what "done" means, and the tests to add. If the code contradicts this plan, stop and ask the project lead. Do not improvise around it.

Batch A and batch B touch different files except `shop_workspace.dart` and `docs/decisions.md`. They can run in parallel if the second one to finish rebases those two files.

---

## 0. Rules for every task

Rules 1–10 of [batch A section 0](owner-feedback-2026-11-09-plan-batch-a.md#0-rules-for-every-task) apply unchanged: Arabic RTL and theme tokens only, integer piastres and milligrams, the existing pending-command pattern, new migrations only (after `20261108160200`, and after batch A's if batch A is merged first), wrap from the **live** function definition, `private.compensation_extend_in_check`, Clean Architecture layers, the gates, development-only deployment, and no commits by Grok.

One more rule for this batch: **the owner's guiding principle (voice note 6).** Each page keeps the concept of the old app (tables, summary containers at the top, the same information) in the new design: our brown, cream and dark palette, Cairo, and the existing components. "Same body, new uniform." Do not invent new sections the reference does not have, and do not show an action that does nothing.

---

## 1. Decisions fixed by this plan

| # | Question | Decision |
|---|---|---|
| B-D1 | Page name (FB-001) | The customers page is **«بيانات العملاء»** everywhere: app bar, phone navigation bar, desktop rail, «المزيد» texts, tooltips, and the workspace placeholder page. |
| B-D2 | Design reference (FB-001) | The customer mockup in the owner's requirements document (section «صفحة العملاء (Customer CRM)», the image with «العملاء» list on the left and «تفاصيل العميل» on the right). The layout is described in B1.3 and B1.4, so you do not need the document. The source document is not committed (AGENTS.md); ask the project lead if you want to see the image. |
| B-D3 | Which operations create or update a customer (FB-002) | Every confirmed **sale** and **purchase** with a customer phone or name, from any path that writes the operation (new, edit replacement, exchange). One shop, one customer per normalized phone. Returns, expenses and notes do not. |
| B-D4 | How a customer is matched (FB-002) | **Phone first.** A valid phone that belongs to an **active** customer of the shop → link to that customer. A valid phone that no customer has → create a customer with that phone and link. A phone owned by an **archived** customer → do nothing (no link, no new customer). **No phone, name only:** exactly one active customer with the same trimmed name → link; no customer with that name → create one without a phone and link; two or more → do nothing. An invalid phone counts as no phone. |
| B-D5 | The name of an auto-created customer | The trimmed sale name if it is 1–200 characters and contains an Arabic letter (the existing `customers_name_check`). Otherwise **«عميل {phone}»** with the phone as typed. With neither a valid name nor a valid phone, nothing is created. |
| B-D6 | Existing customer data | Auto-capture never renames a customer, never changes its phones, VIP flag, notes or open request. The owner's edits win. |
| B-D7 | Failure isolation | Auto-capture runs in the same transaction as the sale, but it must **never** make a sale fail. Any error inside it is caught; the sale commits without a customer link. Tests prove both paths. |
| B-D8 | Past sales | No backfill of operations recorded before this change (see owner confirmation 1). |
| B-D9 | Who sees it | Customers stay owner-only (AGENTS.md). An employee's or partner's sale still creates the customer on the server; only the owner sees «بيانات العملاء». |
| B-D10 | Instant inventory table (FB-003) | Rows are **item names** (خاتم، سلسلة، حلق، …) of owned, available worked jewelry. Columns are karats. Each cell shows the piece count and the weight. Bullion and coins keep their own existing sections. Scrap is the last row, weight only. |
| B-D11 | Which karat columns show (FB-003) | The shop's karat order is a list of the four jewelry karats; default **18, 21, 22, 14** (same order as the closing grid, ADR 0041 D9). The **first two** columns of that order always show. **«عيارات أخرى»** shows the other two. The merchant can reorder the four in **«ترتيب العيارات»**. Both the order and the expanded state are saved per shop on the device, like the ledger layout. |
| B-D12 | Inventory insights (FB-003) | The page starts with a strip of six figures built with the ledger's `LedgerMetricTile`, the way the ledger home starts with its figures. Details in B3.3. |
| B-D13 | Cell density (FB-004) | Karat cells are 62 logical px wide. The item name column takes the rest (minimum 80 px). In list cells, grams show with two decimals (`displayGrams`), and the exact milligrams are one tap away in the lot history. With two karats there is never a horizontal scroll at 375 px. Four karats need 80 + 4 × 62 + gaps ≈ 340 px, which is about the content width of a 375 px phone. When it does not fit (page padding or large text scale), the table scrolls sideways with the name column first. |

### Owner confirmations (do not block work; the default above is implemented)
1. Should customers be created from sales recorded **before** this change? Default: no.
2. Should a purchase (the shop buying from a person) also create the customer? Default: yes; the customer card already shows «باع العميل للمحل».
3. The mockup's «محادثة», «مشاركة العميل» and a list of open requests are not built. The app has no SMS channel, no share feature for customers, and «طلب مفتوح» is one flag (ADR 0014).

---

## 2. What the code does today

| Item | Where | Today |
|---|---|---|
| FB-001 | `app/lib/src/shell/shop_workspace.dart:208, 380`; `customers/presentation/customer_screen.dart:1758` | Title and navigation say «العملاء». The list card (`_card`, line ~998) is a `ListTile` with long text lines («حالة حفظ الرقم الأساسي لواتساب: …», «صافي العمليات المؤكدة المرتبطة فقط»). There is no summary header. |
| FB-002 | ADR 0014; `20261013114617_customers_crm.sql` | «No matching name or phone imports or merges transaction parties.» A sale's `customer_name` / `customer_phone` stay inside the payload. Customers are created only by hand, and operations are linked only by hand. |
| FB-002 stats | `get_customer_list_v3`, `get_customer_v3` (`20261014080820_customer_saved_numbers.sql`) | Statistics and linked-operation lists do **not** exclude operations hidden by edit or delete (`private.ledger_trade_hidden`). With auto-linking, an edited sale would count twice. |
| FB-003 | `inventory/presentation/inventory_screen.dart` `build` (line ~476) | Search, filter chips, «صنف جديد», a cash card, «أرصدة الذهب», karat sections, then «الدفعات»: a lot-by-lot table. There is no item × karat table and no figure strip. |
| FB-003 data | `list_inventory_lots_v1` | Lots carry `product_name`, `category`, `karat`, `stock_class`, `remaining_milligrams`, `remaining_count`. They are paged by 50, so the client cannot total them. A server aggregate is needed. |

---

## 3. Milestones and order

| Milestone | Items | Layers | Risk |
|---|---|---|---|
| B0 | ADR 0043 | docs | low |
| B1 | FB-001 «بيانات العملاء» redesign | SQL (overview read) + Flutter | medium |
| B2 | FB-002 automatic customer capture | SQL + small Flutter | high (runs inside every sale) |
| B3 | FB-003, FB-004 inventory table and insights | SQL (aggregate read) + Flutter | medium |
| B4 | Gates, validation note, owner checklist | docs + hosted checks | low |

B2's server work does not depend on B1. Do B2.1–B2.2 first if you can only do one thing: it is the business rule the owner stressed. B3 is independent.

---

## B0 — Bookkeeping

### B0.1 Write ADR 0043
- File: `docs/adr/0043-owner-feedback-2026-11-09-customer-data-and-inventory.md`. Copy the structure of ADR 0041.
- Decision: section 1 of this plan (B-D1 … B-D13).
- **Supersedes in part** [ADR 0014](../adr/0014-customer-directory-notes-and-links.md): the sentence «No matching name or phone imports or merges transaction parties» no longer holds for sales and purchases (B-D3, B-D4). Manual link and unlink stay. Say so in both ADRs (add one "Amended by ADR 0043" line under ADR 0014's status line; do not rewrite the rest of it).
- Data impact: trigger `financial_operation_details_customer_capture`; function `private.customer_auto_capture`; `customer_events` payload `source: 'auto'`; reads exclude hidden operations; `get_customer_overview_v1`; `get_inventory_item_grid_v1`.
- Add one line to `docs/decisions.md`.

---

## B1 — «بيانات العملاء» (FB-001)

### B1.1 Rename
1. `app/lib/src/shell/shop_workspace.dart`: in `_labels`, `'العملاء'` → `'بيانات العملاء'`. In the placeholder page (`_page('العملاء', …)`, line ~380) the title becomes «بيانات العملاء».
2. `customer_screen.dart` app bar (line ~1758): `'العملاء'` → `'بيانات العملاء'`. The success-stage button «قائمة العملاء» → «قائمة بيانات العملاء». The filter label `'active': 'العملاء'` (line ~1205) stays; it names a filter, not the page.
3. `grep -rn "'العملاء'" app/lib` must return only that filter label afterwards.
4. Visual check: the phone navigation bar at 375 px shows «الدفتر», «الجرد الفوري», «بيانات العملاء», «المزيد» on one line each at text scale 1.0.
- Tests: update tests that find `'العملاء'` as a nav label (`grep -rln "'العملاء'" app/test`). Add one assertion that `find.text('بيانات العملاء')` exists in the navigation bar.

### B1.2 Server: overview figures
New migration `supabase/migrations/20261109110000_customer_overview.sql`.
`public.get_customer_overview_v1() returns jsonb`, `stable security definer set search_path = ''`. Use the same owner/reader check as `get_customer_list_v3` (read its live definition; copy its first lines). Return:
```json
{
  "active_count": "1250",
  "vip_count": "86",
  "active_30_days": "312",
  "open_request_count": "18"
}
```
- `active_count`: customers with `status = 'active'`.
- `vip_count`: active and `is_vip`.
- `active_30_days`: active customers with at least one **active** link to a non-hidden operation (`not private.ledger_trade_hidden(...)`) whose `created_at >= now() - interval '30 days'`.
- `open_request_count`: active and `has_open_request`.
- All counts are text. Grant execute to `authenticated` only.
- SQL test: extend `supabase/tests/customers.sql`: the four counts on a seeded shop; an archived customer is excluded; another shop's customers are excluded; a partner or employee gets `forbidden`.

### B1.3 Client: list layout
Split the screen while you change it. New files under `customers/presentation/`:
- `customer_overview_header.dart` — the four tiles.
- `customer_list_card.dart` — one customer card.
Keep state, loading and commands in `customer_screen.dart`.

Gateway: add `Future<CustomerOverview> customerOverview({required String callerUserId})` to `CustomerGateway`, a `CustomerOverview` class with four `BigInt`s in `application/customer_gateway.dart`, decode in `data/customer_codec.dart`, and implement it in `daily_ledger/data/http_opening_gateway.dart` next to `get_customer_list_v3`. If the RPC is missing (old server), hide the header; do not show an error.

List stage, top to bottom:
1. **Overview header** (key `customer-overview`): four equal tiles in one row on ≥600 px and a 2 × 2 grid below that. Each tile: icon, label, number, unit «عميل». Use `LedgerMetricTile` (`daily_ledger/presentation/ledger_balance_sections.dart`) with `compact: true`:
   | Label | Value | Icon | Tone |
   |---|---|---|---|
   | «إجمالي العملاء» | `active_count` | `Icons.groups_outlined` | `primary` |
   | «عملاء مميزون» | `vip_count` | `Icons.star_outline` | `primary` |
   | «نشطون آخر 30 يوم» | `active_30_days` | `Icons.person_search_outlined` | `positive` |
   | «طلبات مفتوحة» | `open_request_count` | `Icons.schedule_outlined` | `neutral` |
2. Search field (unchanged behavior), hint **«ابحث بالاسم أو رقم الهاتف…»**.
3. A row: title **«قائمة العملاء»** (`titleMedium`) and, at the end, the existing sort control shown as a compact `OutlinedButton.icon` **«ترتيب»** (`Icons.swap_vert`) that opens the same «الاسم» / «آخر عملية» choice.
4. Customer cards (B1.3 card below).
5. «عرض المزيد من العملاء» (unchanged).
6. A full-width `FilledButton.icon` **«إضافة عميل جديد»** (`Icons.person_add_alt_1_outlined`, key `customer-add`) pinned at the bottom of the list stage (`Scaffold.bottomNavigationBar` padded with `AppTokens.spaceMd`). It opens the existing edit stage. Remove the old add button wherever it was.

**Card** (`CustomerListCard`, key stays `customer-${id}` on the tappable area; keep `customer-whatsapp-${id}` on the WhatsApp button so existing tests keep working):
```
┌───────────────────────────────────────────────────────────┐
│ (م)  محمد أحمد                         آخر عملية           │
│      01012345678  [واتساب] [اتصال]       7 نوفمبر  🕑       │
│ ┌──────────┬──────────┬──────────┐                          │
│ │   18K    │   21K    │   24K    │   ← bought grams          │
│ │ 152.30 g │ 84.15 g  │ 10.00 g  │                          │
│ └──────────┴──────────┴──────────┘                          │
│ ☆   يبحث عيار 18 عايز طقم لازورد   ·   [واتساب] محفوظ        │
└───────────────────────────────────────────────────────────┘
```
1. Avatar: 44 px `CircleAvatar`, first letter of the name, background `colorScheme.primaryContainer`, border `AppSemanticColors.of(context).goldFrame`. Hide it when text scale > 1.25 (as today).
2. Name `titleMedium` w600, one line, ellipsis. Phone: the primary number, LTR-isolated (`⁦…⁩`), then two 40 px `IconButton`s: WhatsApp (`CustomerWhatsappIcon`, tooltip «واتساب») and call (`Icons.call_outlined`, tooltip «اتصال»), both calling the existing `_prepareContact` with `whatsapp` and `dialer`. No phone → the text **«بدون رقم هاتف»** and no buttons.
3. End column: «آخر عملية» (`bodySmall`, `onSurfaceVariant`) above the date (`customerDate(lastAtShop)`), with `Icons.schedule`. No operation → «لا توجد عمليات». Use the date, not «منذ N يوم»: relative time would need the device clock.
4. Karat strip: one bordered row split into equal boxes. Boxes for 18, 21, 24 always, plus 22 and 14 only when their bought weight is non-zero, in `karatDisplayOrder`. Each box: «{k}K» (`labelMedium`, `primary`) over the bought grams with two decimals and « g». Values come from `statistics.weights`; a missing karat shows `0.00 g`. If `statistics` is null, hide the strip.
5. Footer row: a star icon (`Icons.star` in `primary` when VIP, `Icons.star_border` otherwise; display only, tooltip «عميل مميز» / «ليس مميزًا»); the latest note, one line, ellipsis (nothing when there is no note); then a small chip with the saved-number state: WhatsApp icon + **«محفوظ»** (tone `positive`) or **«غير محفوظ»** (tone `negative`), from `savedNumberLabel` / the primary phone's `saved?.state`. No chip when there is no phone. Archived customers keep the existing «مؤرشف» chip in this row.
6. Remove from the card: «حالة حفظ الرقم الأساسي لواتساب: …», «اشترى العميل من المحل (جرام)», «صافي العمليات المؤكدة المرتبطة فقط», and the separate «واتساب» `TextButton` row.

### B1.4 Client: detail layout
New file `customers/presentation/customer_detail_view.dart` (stateless; callbacks come from `customer_screen.dart`). Sections, top to bottom, each a `Card` with 16 px padding and `AppTokens.spaceMd` between cards:
1. **Header card** (key `customer-detail-header`): avatar (56 px), name (`titleLarge`), primary phone LTR with a small WhatsApp icon, and a **«مميز»** chip with a star when VIP. Below, a row of three equal tonal buttons: **«اتصال»** (`Icons.call_outlined`, dialer), **«واتساب»** (WhatsApp icon), **«تعديل»** (`Icons.edit_outlined`, opens the edit stage). Disable them under the same conditions as today (`_canContact`, `_readOnly`, busy).
2. **«ملخص المشتريات»** (key `customer-detail-summary`): the same karat boxes as the list card, larger (`titleMedium` values); then two tiles side by side: **«إجمالي الفواتير»** = `statistics.boughtCount` with unit «فاتورة» (`Icons.receipt_long_outlined`), and **«آخر عملية»** = the last operation date (`Icons.schedule`). Below, one line in `bodySmall`: «باع العميل للمحل: {soldCount} عملية» when `soldCount > 0`.
3. **«الملاحظات»** (key `customer-detail-notes`): header row with the title and a `TextButton.icon` **«إضافة ملاحظة»** (`Icons.add`, opens the note stage). The newest 4 notes, each a row with a note icon, the date (`customerDate`), and the text. If there are more, a `TextButton` **«عرض كل الملاحظات»** that shows the rest in place. Empty: «لا توجد ملاحظات.»
4. **«طلب مفتوح»** (key `customer-detail-request`): only when `openRequest` is true: one line «يوجد طلب مفتوح لهذا العميل.» with a `TextButton` «إنهاء الطلب» that opens the existing status stage.
5. **«العمليات»**: the existing linked-operation history and the existing manual link control, unchanged, under this title.
6. **«إجراءات سريعة»** (key `customer-detail-actions`): a grid (3 columns ≥600 px, 2 below) of outlined tiles with icon and label: **«تعديل بيانات العميل»** (edit stage), **«تاريخ العمليات»** (scrolls to section 5 with `Scrollable.ensureVisible`), **«إضافة ملاحظة»** (note stage), **«عميل مميز» / «إلغاء التمييز»** and **«طلب مفتوح» / «إنهاء الطلب»** (status stage), **«أرشفة العميل»** (archive flow; shown in `error` color; **«استرجاع العميل»** when archived). Do not add «مشاركة العميل» or «محادثة» (owner confirmation 3).
7. Remove the old detail text lines that the cards above now cover. Keep the saved-number and contact-review stages exactly as they are.
- Tests (new `app/test/customer_data_layout_test.dart`, with the existing fake customer gateway from `app/test/` — find it with `grep -rln "implements CustomerGateway" app/test`):
  (a) the list shows the four overview tiles with the fake counts;
  (b) a card shows the name, the phone, 18K/21K/24K boxes with the right grams, the latest note, and «محفوظ»;
  (c) a card has no «حالة حفظ الرقم الأساسي لواتساب» text;
  (d) «إضافة عميل جديد» opens the edit stage;
  (e) the detail shows the header, «ملخص المشتريات» with «إجمالي الفواتير», four notes and «عرض كل الملاحظات» when there are five, and the quick actions without «مشاركة العميل»;
  (f) a missing overview RPC hides the header without an error.
  Run the existing `customers*` tests too and fix any that searched for removed text.

---

## B2 — Automatic customer capture from sales and purchases (FB-002)

### B2.1 Server: capture function and trigger
New migration `supabase/migrations/20261109110100_customer_auto_capture.sql`.

1. `private.customer_auto_capture(p_shop uuid, p_operation uuid) returns void`, `language plpgsql volatile security definer set search_path = ''`:
   ```text
   select o.kind, o.actor_user_id, d.payload into v_kind, v_actor, v_payload
     from public.financial_operations o
     join public.financial_operation_details d on d.shop_id = o.shop_id and d.operation_id = o.id
    where o.shop_id = p_shop and o.id = p_operation;
   if v_kind not in ('sale', 'purchase') then return; end if;
   if exists (active link for this operation) then return; end if;

   v_name  := btrim(coalesce(v_payload ->> 'customer_name', ''));
   v_raw   := btrim(coalesce(v_payload ->> 'customer_phone', ''));
   v_phone := null;
   if v_raw <> '' then
     begin v_phone := private.customer_normalize_phone(v_raw);
     exception when others then v_phone := null; end;
   end if;
   v_name_ok := char_length(v_name) between 1 and 200 and v_name ~ '[ء-ي]';
   if v_phone is null and not v_name_ok then return; end if;

   if v_phone is not null then
     select c.* into v_customer from public.customer_phones p
       join public.customers c on c.shop_id = p.shop_id and c.id = p.customer_id
      where p.shop_id = p_shop and p.normalized_number = v_phone
      for update of c;
     if found and v_customer.status = 'archived' then return; end if;   -- B-D4
   else
     select count(*) into v_matches from public.customers c
      where c.shop_id = p_shop and c.status = 'active' and c.display_name = v_name;
     if v_matches > 1 then return; end if;
     if v_matches = 1 then
       select c.* into v_customer from public.customers c
        where c.shop_id = p_shop and c.status = 'active' and c.display_name = v_name
        for update;
     end if;
   end if;

   v_at := clock_timestamp();
   v_actor_name := private.customer_actor_name(p_shop);
   if v_customer.id is null then
     insert into public.customers (shop_id, status, record_version, display_name, is_vip,
       has_open_request, created_at, updated_at, created_by)
     values (p_shop, 'active', 1,
       case when v_name_ok then v_name else 'عميل ' || v_raw end,
       false, false, v_at, v_at, v_actor)
     returning * into v_customer;
     if v_phone is not null then
       insert into public.customer_phones (shop_id, customer_id, raw_number,
         normalized_number, is_primary, created_at)
       values (p_shop, v_customer.id, left(v_raw, 32), v_phone, true, v_at);
     end if;
     perform private.customer_event(p_shop, v_customer.id, 'created', v_actor, v_actor_name, v_at,
       jsonb_build_object('source', 'auto', 'operation_id', p_operation, 'record_version', '1'));
   end if;

   insert into public.customer_operation_links (shop_id, customer_id, operation_id, status, linked_at, linked_by)
   values (p_shop, v_customer.id, p_operation, 'active', v_at, v_actor);
   update public.customers set record_version = record_version + 1, updated_at = v_at
    where shop_id = p_shop and id = v_customer.id returning * into v_customer;
   perform private.customer_event(p_shop, v_customer.id, 'linked', v_actor, v_actor_name, v_at,
     jsonb_build_object('source', 'auto', 'operation_id', p_operation, 'operation_kind', v_kind,
       'record_version', v_customer.record_version::text));
   perform private.bump_shop_sync(p_shop, 'customer');
   ```
   Write it as real PL/pgSQL with declared variables and `pg_catalog.`-qualified built-ins. Check `private.customer_event`'s exact parameter list and `private.customer_actor_name` in the live definitions first. If the customer's name check or the phone check rejects a row, the exception handler in step 2 catches it.
2. Trigger function `private.financial_operation_details_customer_capture()` returns trigger:
   ```text
   begin
     perform private.customer_auto_capture(new.shop_id, new.operation_id);
     return new;
   exception when others then
     raise warning 'customer_auto_capture_skipped: % %', new.operation_id, sqlerrm;
     return new;
   end;
   ```
   The `exception` block rolls back only the capture's writes (PL/pgSQL subtransaction). The sale stays (B-D7).
3. `create trigger financial_operation_details_customer_capture after insert on public.financial_operation_details for each row execute function private.financial_operation_details_customer_capture();`
   An `after insert` trigger on the details row covers every writer: `post_daily_ledger_trade` v1/v2, the edit replacement and the exchange. An idempotent replay inserts nothing, so it captures nothing twice.
4. Revoke execute on both new functions from `public, anon, authenticated`.
5. Customer reads: every read that lists or counts linked operations must ignore operations hidden by edit or delete. Find them with `grep -ln "customer_operation_links" supabase/migrations/*.sql`, take the **live** definitions of `get_customer_list_v3`, `get_customer_v3`, `private.customer_last_operation_at`, and the statistics function (`20261013175048_customer_statistics.sql`), and add `and not private.ledger_trade_hidden(link.shop_id, link.operation_id)` wherever they join `customer_operation_links` to operations. Use `create or replace` with the same signature.
- SQL test (new `supabase/tests/customer_auto_capture.sql`, added to `run-rls-tests.mjs`):
  (a) a sale with name «محمد أحمد» and phone `01012345678` creates one active customer «محمد أحمد» with primary phone `+201012345678` and links the sale;
  (b) a second sale with the same phone in another format (`+20 101 234 5678`) and the name «أبو أحمد» links to the **same** customer and does not rename it;
  (c) a purchase with that phone also links;
  (d) a sale with only the name «سارة» creates «سارة» with no phone; a second sale «سارة» links to it; after a manual second «سارة» customer exists, a third sale «سارة» links nothing;
  (e) a phone owned by an archived customer: no link and no new customer;
  (f) a Latin name «Ahmed» with phone `01198765432` creates «عميل 01198765432»;
  (g) an invalid phone with no name: nothing created, and the sale still commits;
  (h) inside the test's own transaction, create a `before insert` trigger on `public.customers` that always raises, post a sale with a new phone, then drop that trigger: the sale committed, there is no link, and there is no partial customer or phone row;
  (i) replaying the sale's idempotency key creates no second link;
  (j) editing the sale through `post_ledger_trade_change_v1` links the replacement to the same customer, and the customer statistics count the sale **once**;
  (k) a deleted sale disappears from the customer's operations and statistics;
  (l) an employee with the `sale` grant posts a sale: the customer is created (actor = the employee), and the employee still cannot call `get_customer_list_v3` (`forbidden`);
  (m) another shop with the same phone gets its own customer.

### B2.2 Client: say what happens
File `daily_ledger/presentation/financial_trade_screen.dart`, the customer fields of a sale or purchase.
1. Under the phone field, when the name or phone is not empty, show `bodySmall` / `onSurfaceVariant` text (key `trade-customer-capture-hint`): **«يُحفظ العميل تلقائيًا في بيانات العملاء بعد تأكيد العملية.»**
2. After a confirmed sale that had a customer, the existing success state shows no extra step. The customer appears in «بيانات العملاء» after the next sync; the customers screen already reloads on the `customer` sync scope.
- Tests: extend `app/test/financial_trade_screen_test.dart`: the hint appears after typing a phone and is absent while both fields are empty.

### B2.3 Hosted check after deploy
After deploying B2.1 to `xchapwvmvoefriqcxtvn`, post one test sale with a new phone on a test shop and record in the validation note: the customer row, the link, and that `customers` has no other new rows. Do not create customers in any shop that is not a test shop.

---

## B3 — «الجرد الفوري»: item × karat table and insights (FB-003, FB-004)

### B3.1 Server: aggregate read
New migration `supabase/migrations/20261109110200_inventory_item_grid.sql`.
`public.get_inventory_item_grid_v1() returns jsonb`, `stable security definer set search_path = ''`. First line: `perform private.allow_member_permission('inventory');` then `v_shop := private.opening_require_reader_shop();` (same as `list_inventory_lots_v1`).
1. Rows: from `inventory_lots` joined to `inventory_products` and `inventory_lot_movements` exactly like `list_inventory_lots_v1_before_staff` (`20261004081229_milestone_3_inventory_contract.sql:3332`), with `lot.stock_class = 'owned_available'` and `lot.category_code = 'worked_jewelry'`. Group by `product.name` and `lot.karat`. Sum remaining milligrams and remaining count. Keep groups with remaining milligrams > 0. A lot with `original_count is null` adds nothing to the count; return `count_known: false` for the group if any of its lots has a null count.
2. Scrap: the shop's scrap balance per karat, from the same source `get_inventory_totals_v1` uses for the `scrap` category (read its live definition and reuse that query; do not invent a second definition of scrap).
3. Return:
   ```json
   {
     "rows": [
       {"item_name": "خاتم", "karat": 21, "count": "12", "count_known": true, "milligrams": "45230"}
     ],
     "scrap": [{"karat": 21, "milligrams": "100000"}],
     "karats": [14, 18, 21, 22]
   }
   ```
   `rows` ordered by `item_name`, then karat. `karats` = the distinct karats in `rows`, ascending. All amounts are text. Cap `rows` at 500.
4. Grant execute to `authenticated` only.
- SQL test (new `supabase/tests/inventory_item_grid.sql`): two «خاتم» lots at 21 (3 and 2 pieces) sum to one row with count 5; a sold-out lot is not listed; a trader-custody lot is not listed; bullion and coin lots are not listed; scrap per karat matches `get_inventory_totals_v1`; a staff member without the `inventory` grant gets `forbidden`; another shop's lots are invisible.

### B3.2 Client: domain and data
1. New pure-Dart file `inventory/domain/inventory_item_grid.dart`:
   ```dart
   final class InventoryGridCell { final BigInt count; final bool countKnown; final BigInt milligrams; }
   final class InventoryGridRow { final String itemName; final Map<int, InventoryGridCell> cells; }
   final class InventoryItemGrid {
     final List<InventoryGridRow> rows;      // order: خاتم, حلق, سلسلة, تعليقة first (when present), then the rest by name
     final Map<int, BigInt> scrapByKarat;
     final Map<int, InventoryGridCell> totals; // per karat, over all rows
   }

   const inventoryDefaultKaratOrder = <int>[18, 21, 22, 14];

   /// The visible karat columns: the first two of [order], plus the rest when [expanded].
   List<int> visibleInventoryKarats(List<int> order, {required bool expanded});

   /// Parses a saved order; anything that is not a permutation of 14/18/21/22 gives the default.
   List<int> parseInventoryKaratOrder(List<String>? saved);
   ```
   Totals: a karat's total count is "known" only if every cell in that column is known.
2. `inventory/application/inventory_gateway.dart`: add `Future<InventoryItemGrid> itemGrid({required String callerUserId})` to `InventoryGateway`. Implement it in `daily_ledger/data/http_opening_gateway.dart` with `get_inventory_item_grid_v1`, and decode in `inventory/data/inventory_codec.dart`. A missing RPC throws the same "not available" error the other inventory reads throw.
- Tests (new `app/test/inventory_item_grid_test.dart`): the codec parses the contract above; built-in names come first; `visibleInventoryKarats([18,21,22,14], expanded:false) == [18,21]`; expanded gives all four in order; `[22,14,18,21]` collapsed gives `[22,14]`; a bad saved order (`['18','18','21','22']`) gives the default; totals add counts and mark unknown when a cell is unknown.

### B3.3 Client: insights strip
At the top of `InventoryScreen.build` (above the search field), key `inventory-insights`. Six `LedgerMetricTile`s with `compact: true`, three per row at ≥600 px and two per row below. Values come from data the screen already loads (`_totals`, `_cash`), so no new request:
| Label | Value | Unit | Icon | Tone |
|---|---|---|---|---|
| «وزن المشغولات» | sum of `availableMilligrams` over `worked_jewelry` buckets | «جرام» | `Icons.diamond_outlined` | `primary` |
| «عدد القطع» | sum of `availableCount` over `worked_jewelry` buckets («—» if any is null) | «قطعة» | `Icons.format_list_numbered` | `primary` |
| «الكسر» | sum of `availableMilligrams` over `scrap` buckets | «جرام» | `Icons.content_cut_outlined` | `negative` |
| «السبائك» | sum of `availableMilligrams` over `bullion` buckets | «جرام» | `Icons.view_in_ar_outlined` | `neutral` |
| «الجنيهات» | sum of `availableCount` over `coin` buckets | «قطعة» | `Icons.monetization_on_outlined` | `neutral` |
| «النقدية» | sum of `_cash` values | «جنيه» | `Icons.payments_outlined` | `positive` |
Grams with `displayGrams`, money with `displayPounds`, counts with grouping. Put the sums in a small pure function in `inventory_item_grid.dart` (`inventoryInsights(InventoryTotals, Map<String, BigInt> cash)`) and unit-test it.

### B3.4 Client: the table
New widget file `inventory/presentation/inventory_item_grid_view.dart`, placed in `InventoryScreen.build` **directly after the insights strip and before the search field**, under the title **«الأصناف حسب العيار»** (`titleMedium`).
1. Header row: **«الصنف»**, then one header per visible karat: **«عيار {k}»** with a second line «عدد · وزن» (`labelSmall`, `onSurfaceVariant`).
2. Each row: item name (flexible, minimum 80 px, one line, ellipsis); per visible karat a 62 px cell with the count on line 1 (`bodyMedium` w600; «—» if unknown; empty cell = «·») and the grams on line 2 (`bodySmall`, two decimals, LTR-isolated). Cells are `InkWell`s: tapping a non-empty cell runs the existing lot search with `category = worked_jewelry`, that karat, and the item name as the query, then scrolls to «الدفعات».
3. Last two rows: **«كسر»** (weight only, from `scrapByKarat`, count shows «—»), then **«الإجمالي»** (`totals`, w700, top border `colorScheme.outlineVariant`).
4. Row separators: 1 px `outlineVariant`. Row height grows with text scale; never clip.
5. Controls under the title, one wrapping row:
   - `FilterChip` **«عيارات أخرى»** (key `inventory-grid-more-karats`): selected = expanded. Label shows the hidden karats, e.g. «عيارات أخرى (22، 14)».
   - `TextButton.icon` **«ترتيب العيارات»** (key `inventory-grid-order`, `Icons.reorder`): opens a bottom sheet (dialog at ≥600 px) titled «ترتيب العيارات» with a `ReorderableListView` of «عيار 18», «عيار 21», «عيار 22», «عيار 14» in the current order, a line **«أول عيارين يظهران دائمًا.»**, and buttons **«حفظ»** / «إلغاء» / **«الترتيب الافتراضي»**.
6. Persistence (per shop, on the device, like `ledger_layout_${shopId}`): `SharedPreferences` keys `inventory_karat_order_${shopId}` (string list) and `inventory_karat_expanded_${shopId}` (bool). Wrap reads and writes in `try/catch`; a failure keeps the default and shows nothing.
7. Width: the table sits in the screen's existing content width. Use a `LayoutBuilder`. If `80 + 62 × visibleKarats + gaps` exceeds the width (only at large text scale), wrap it in a horizontal `SingleChildScrollView` and keep the name column first.
8. States: loading → the existing `LinearProgressIndicator`; error → **«تعذر تحميل جدول الأصناف. أعد المحاولة.»** with «إعادة المحاولة» (the rest of the page still works); no rows and no scrap → **«لا توجد أصناف متاحة في المخزون.»**
9. Refresh with the rest of the screen: call `itemGrid` inside the screen's existing `_load` and after every confirmed inventory command (where `_totals` is reloaded).
10. The old «أرصدة الذهب» board and the karat breakdown cards stay below the table. Bullion and coin sections stay. «الدفعات» stays. Do not delete anything else on this page.
- Keys: rows `inventory-grid-row-{itemName}`, cells `inventory-grid-cell-{itemName}-{karat}`, scrap row `inventory-grid-scrap`, totals `inventory-grid-total`.
- Tests (new `app/test/inventory_item_grid_view_test.dart`):
  (a) default shows only «عيار 18» and «عيار 21»;
  (b) tapping «عيارات أخرى» adds 22 and 14, and the choice survives a rebuild (mock `SharedPreferences`);
  (c) a saved order `[22, 14, 18, 21]` shows 22 and 14 by default;
  (d) a cell shows count and grams, and an unknown count shows «—»;
  (e) the «كسر» and «الإجمالي» rows appear;
  (f) at 375 × 812 with two karats, there is no horizontal `Scrollable` around the table;
  (g) at 375 × 812 with four karats and text scale 1.0, there is no `RenderFlex` overflow (record in the validation note whether it fit or used the fallback scroll);
  (h) tapping a cell filters «الدفعات» to that item and karat;
  (i) the six insight tiles show the expected values from a fake gateway;
  (j) the page has no text «مشغولات» in the new table.

### B3.5 Copy fix on the same page
`inventory_screen.dart:1412` title «المشغولات حسب العيار» → **«الأصناف حسب العيار — تفصيل»**, so the page no longer uses the word «مشغولات» (owner, voice notes 7 and 9). Leave the category name «مشغولات» in filters and codecs; it names a stock category, not an item.

---

## B4 — Finish

### B4.1 Gates
- `flutter analyze`, full `flutter test`, full `npm run test:rls`.
- React lint, tests and `npx tsc -b` only if a file under `supabase/contracts/` changed.
- Visual review: «بيانات العملاء» list and detail; the sale form hint; «الجرد الفوري» insights, table collapsed and expanded, the order sheet. Arabic RTL, light and dark, 375 px and ≥1280 px, Windows desktop and an Android emulator. Compare the customer screens with the owner's mockup layout (B-D2) and fix visible differences in spacing and order.

### B4.2 Validation note and deployment record
- New `docs/operations/owner-feedback-2026-11-09-batch-b-validation.md` (same format as batch A's): gates, results, limitations, migrations deployed to `xchapwvmvoefriqcxtvn`, the B2.3 hosted check, and one `get_inventory_item_grid_v1` call on a test shop.
- Set ADR 0043 status to "implemented and deployed to development; not committed".

### B4.3 Owner acceptance checklist (send in Arabic)
1. الصفحة اسمها «بيانات العملاء»، وشكلها مثل التصميم: أرقام في الأعلى، كارت لكل عميل فيه الهاتف وآخر عملية وأوزان 18 و21 و24 وآخر ملاحظة.
2. عند تسجيل بيع أو شراء باسم العميل أو رقمه، يظهر العميل تلقائيًا في «بيانات العملاء» مرتبطًا بالعملية. نفس الرقم لا يُنشئ عميلًا مكررًا.
3. «الجرد الفوري» يبدأ بأرقام ملخصة، ثم جدول: الصنف، والعدد والوزن لعيار 18 و21. زر «عيارات أخرى» يُظهر 22 و14، و«ترتيب العيارات» يغيّر الترتيب كما يريد التاجر.
4. الخانات صغيرة وتتسع للأرقام، والجدول لا يحتاج سحبًا جانبيًا على الموبايل.

---

## Traceability

| Feedback | Tasks |
|---|---|
| FB-001 | B1.1–B1.4 |
| FB-002 | B2.1–B2.3 |
| FB-003 | B3.1–B3.5 |
| FB-004 | B3.4 (inventory); closing grid in batch A, A1.2 |
