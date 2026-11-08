# Owner feedback 2026-11-08 — implementation plan (Flutter mobile + desktop)

Status: planned, not started. Source: ten owner voice notes (FB-001 … FB-009). Scope is the Flutter app (`app/`) on Android, iOS and Windows. The React admin dashboard is **not** affected. No database migration, Edge Function or R2 change is needed: every field used below is already returned by the server (verified in code on 2026-11-08 — see "Facts the plan relies on").

Every task below is self-contained: exact files, exact Arabic strings, exact widget keys, exact tests. Do the tasks **in the order given** (several touch the same files). Do not add anything that is not listed. If something in the code does not match what a task says, stop and ask — do not improvise.

---

## 0. Global rules for the implementer (read first)

1. Read `AGENTS.md` and `docs/design-system.md` before touching UI. Use theme tokens / `ColorScheme` roles only — no hard-coded colors.
2. All user-facing text is Arabic, RTL. Copy every Arabic string **exactly** as written in this plan (including hamza, ى/ي, and punctuation).
3. Do not commit or push. Leave the diff for review.
4. After each task run, from `app/`:
   ```bash
   dart format lib test
   ```
   ```bash
   flutter analyze
   ```
   ```bash
   flutter test
   ```
   All three must be clean before moving to the next task.
5. Do not run release builds.
6. Do not reintroduce guides, tours or help cards (owner feedback 2026-10-05).

## Decisions taken for the owner's open questions

These answer the "Needs clarification" items so the implementer does not have to decide. Product may override them later; each is isolated to one constant or one block.

| Question | Decision | Where it lives |
|---|---|---|
| Scrap («الكسر») in the purchased-weight breakdown: per karat or one total? | **Per karat**, same chip layout as the other categories (the server already stores scrap per karat, and the sale breakdown already works this way). | Task 2 |
| How many items on a ledger card before «إظهار المزيد»? | **3 items**. The 4th and later appear after tapping «إظهار المزيد». | Task 3, constant `_previewItemCount = 3` |
| What goes inside the «المزيد» tab? | Everything that is currently in the hamburger drawer **plus** everything that is currently on the «الحساب» page. Nothing new. Exact list in Task 6. | Task 6 |

## Facts the plan relies on (already verified)

- The «Insights» the owner means is the **6-tile metric strip on the daily ledger home** (`confirmed_ledger_dashboard.dart` → `_metrics`), not the separate «التحليلات» screen.
- Metric labels come from one function: `ledgerMetricLabel()` in `app/lib/src/features/daily_ledger/application/ledger_home_metrics.dart`.
- Tile values/sub-lines come from `ledgerMetricValues()` in `app/lib/src/features/daily_ledger/presentation/ledger_metric_specs.dart`.
- Day gold movements per kind/category/karat are already in `DailyLedgerView.daySummary.goldByBucket` (`LedgerGoldMovement{kind, category, karat, milligrams, count}`), for both `kind == 'sale'` and `kind == 'purchase'`. Categories: `worked_jewelry` (مشغولات 14/18/21/22), `bullion` (سبائك 24), `coin` (جنيهات 21), `scrap` (كسر).
- Every ledger feed line already has `hasNote` (`LedgerFeedLine.hasNote`, server field `has_note`).
- Each sale/purchase payload item already has `item_name`, `karat`, `milligrams`, `count`, `category` and optional `line_price_piastres` (all items priced or none). Read via `DailyLedgerScreen._loadOperationItems` → `ledgerLineItemsFromPayload()`.
- The header already renders `'أهلاً $shopName'` when expanded and only `shopName` when collapsed (`ledger_app_bar.dart`).
- When there is no shop image the header shows the painted `BrandMark` at 28 px with 10 px padding. **There is no green placeholder anywhere in the code.** The "green image" the owner sees is almost certainly a photo stored on their test shop. Task 5 makes the fallback a proper full-size ledger logo; Task 7 lets the owner remove a stored photo.

---

## Task 1 — Metric strip labels and money tiles (FB-001)

**Files**
- `app/lib/src/features/daily_ledger/application/ledger_home_metrics.dart`
- `app/lib/src/features/daily_ledger/presentation/ledger_metric_specs.dart`

**Steps**
1. In `ledgerMetricLabel()` change:
   - `'sale_gold' => 'ذهب مباع'` → `'sale_gold' => 'وزن مباع'`
   - `'purchase_gold' => 'ذهب مشترى'` → `'purchase_gold' => 'وزن مشترى'`
2. In `ledgerMetricValues()`:
   - For `'sale'` change the 3rd argument (unit) from `'${normalized('sale')} $equivalent'` to `''`.
   - For `'purchase'` change the 3rd argument from `'${normalized('purchase')} $equivalent'` to `''`.
   - Do **not** change `'sale_gold'` / `'purchase_gold'` (they keep their `جرام محيف عيار N` unit line).
3. Search the whole `app/lib` for any other literal `'ذهب مباع'` / `'ذهب مشترى'` / `'أوزان الذهب المباع'` and replace per Task 2 (do not leave old wording anywhere user-visible).

**Acceptance**
- The «إجمالي البيع» and «إجمالي الشراء» tiles show only the money amount — no second line.
- Tiles read «وزن مباع» and «وزن مشترى»; the settings slot dropdown shows the same new names.

**Tests**
- Update `app/test/ledger_karat_settings_test.dart` (asserts `محيف` text) and `app/test/confirmed_ledger_dashboard_test.dart` for the new labels.
- Add a test in `confirmed_ledger_dashboard_test.dart`: with a day summary containing sale and purchase gold, `find.descendant(of: find.byKey(Key('ledger-metric-sale')), matching: find.textContaining('محيف'))` finds nothing; same for `ledger-metric-purchase`.

---

## Task 2 — Weight breakdown sheets: no piece count, purchased weight opens, no «عرض المزيد» (FB-002, FB-003)

**Files**
- `app/lib/src/features/daily_ledger/presentation/ledger_balance_sections.dart`
- `app/lib/src/features/daily_ledger/presentation/confirmed_ledger_dashboard.dart`

**Steps — `ledger_balance_sections.dart`**
1. Rename class `LedgerSoldGoldBreakdown` to `LedgerTradeWeightBreakdown` and add a required parameter `final String kind; // 'sale' or 'purchase'`.
2. In its `build`:
   - Filter `row.kind != kind` instead of `row.kind != 'sale'`.
   - Title text: `kind == 'sale' ? 'وزن مباع' : 'وزن مشترى'`.
   - Sub-title stays `'الوزن الفعلي لكل صنف وعيار.'`.
   - Empty text: `kind == 'sale' ? 'لا يوجد وزن مباع.' : 'لا يوجد وزن مشترى.'`; empty key: `Key('ledger-$kind-gold-empty')` (sale key stays `ledger-sale-gold-empty`).
   - Category order stays `['worked_jewelry', 'jewelry', 'bullion', 'coin', 'scrap']` → for purchase this gives مشغولات (21/18/14/22), سبائك 24, جنيهات 21, كسر per karat — exactly what the owner asked.
   - Pass `count: null` for **every** row (remove `category == 'scrap' ? null : row.count`).
3. Leave `_InventoryPiece`'s optional `count` support in place (it is still used by `LedgerGoldBreakdown` for stock). Only the trade breakdown stops passing counts.

**Steps — `confirmed_ledger_dashboard.dart`**
4. Replace `_showSoldGold` with:
   ```dart
   void _showTradeWeight(String kind) => _details(
     kind == 'sale' ? 'وزن مباع' : 'وزن مشترى',
     (_) => LedgerTradeWeightBreakdown(view: widget.ledger!, kind: kind),
   );
   ```
5. In `_metricTile`, the `open` switch becomes:
   - `'sale_gold'` → `onOpen: () => _showTradeWeight('sale')`, `tooltip: 'تفاصيل الوزن المباع'`, `key: Key('ledger-sale-gold-weights')` (keep key).
   - **new** `'purchase_gold'` → `onOpen: () => _showTradeWeight('purchase')`, `tooltip: 'تفاصيل الوزن المشترى'`, `key: Key('ledger-purchase-gold-weights')`.
6. In `_metrics`, `hasAction` becomes `id == 'total_cash' || id == 'sale_gold' || id == 'purchase_gold'`.
7. The whole tile is the tap target (owner: "ادوس على الكونتينر"). `LedgerMetricTile` in `ledger_balance_sections.dart` already wraps its body in `InkWell(onTap: onOpen)` when `onOpen != null` — passing `onOpen` in step 5 is enough. Do not change `LedgerMetricTile`.
8. Remove the «عرض المزيد» button under the strip: delete the `TextButton.icon` with key `ledger-more-metrics` and the `_showAllMetrics` / `_allMetrics` methods. Keep the settings `IconButton` (`ledger-customize`), aligned to `AlignmentDirectional.centerEnd` in the same row.
9. In `_customization`, change the helper text `'اختر ست خانات للملخص. تظهر بقية الأرقام في المزيد.'` → `'اختر ست خانات تظهر في ملخص اليوم.'`.

**Acceptance**
- Tapping the «وزن مباع» tile anywhere opens «وزن مباع» with karat chips and **no** «قطعة» text.
- Tapping the «وزن مشترى» tile opens «وزن مشترى» grouped as مشغولات / سبائك / جنيهات / كسر, each with per-karat grams, no piece counts.
- No «عرض المزيد» under the metric strip.

**Tests** (`app/test/confirmed_ledger_dashboard_test.dart`, `app/test/daily_ledger_widget_test.dart`)
- Remove/replace tests that tap `ledger-more-metrics` or expect `ledger-all-metrics`; assert `find.byKey(Key('ledger-more-metrics'))` finds nothing.
- Sale sheet: fixture with worked_jewelry 18 and 21 sale rows (count "2") → sheet shows both karats and `find.textContaining('قطعة')` finds nothing.
- Purchase sheet: fixture with purchase rows worked_jewelry 21, bullion 24, coin 21, scrap 18 → tap `ledger-metric-purchase_gold` → sees «مشغولات», «سبائك», «جنيهات», «كسر», grams for each, no «قطعة».
- Empty purchase → `ledger-purchase-gold-empty` with «لا يوجد وزن مشترى.».

---

## Task 3 — Sale / purchase ledger cards show what was sold or bought (FB-007)

**Files**
- `app/lib/src/features/daily_ledger/presentation/ledger_journal_table.dart`
- `app/lib/src/features/daily_ledger/application/ledger_line_items.dart`
- `app/lib/src/features/daily_ledger/presentation/confirmed_ledger_dashboard.dart`
- `app/lib/src/features/daily_ledger/presentation/daily_ledger_screen.dart`

**Steps — data**
1. `LedgerLineItem`: add `final String? linePricePounds;` (constructor param, optional).
2. `ledgerLineItemsFromPayload`: read `entry['line_price_piastres']`; if it is a non-empty `String`, parse with `Piastres.parseWire`; if `Accepted<Piastres>` set `linePricePounds: value.poundsText`, otherwise `null`. Never use `double`.

**Steps — items always visible**
3. In `LedgerOperationTable`, remove the `showDetails` gate: items load and render whenever `loadItems != null` and the kind is in the existing set (`sale, purchase, sale_return, purchase_return, scrap_sale`). Keep the `showDetails` constructor parameter **removed** (delete it and every call-site argument).
4. In `confirmed_ledger_dashboard.dart`:
   - `_JournalPreview`: delete the `_details` map and the `IconButton` with key `ledger-journal-details-${journal.$1}` (unfold icon).
   - `_ActivitySection`: delete `_showDetails` and the `IconButton` with key `ledger-history-details`.
5. Cache item reads so cards do not refetch on every rebuild. In `daily_ledger_screen.dart`:
   - Add `final Map<String, Future<List<LedgerLineItem>?>> _itemCache = {};`.
   - `_loadOperationItems(id)` returns `_itemCache.putIfAbsent(id, () => <existing body>)`; if the future completes with `null` or throws, remove that key so a retry refetches.
   - Clear `_itemCache` whenever the ledger is refreshed (the places that call `_controller?.refresh()` and the sync-tick handler) — trades can be edited/deleted, so a refresh must refetch.

**Steps — layout**
6. Constant at top of `ledger_journal_table.dart`: `const _previewItemCount = 3;`. Replace `items.take(2)` with `items.take(_previewItemCount)` and `items.length > 2` with `items.length > _previewItemCount`.
7. Table columns become **الصنف | العيار | الوزن (جرام) | السعر** (drop «العدد»):
   - Heading cells: `'الصنف'`, `'العيار'`, `'الوزن\n(جرام)'`, `'السعر'`.
   - Row cells: `item.name`, karat or `'—'`, `displayGrams(item.grams)`, `item.linePricePounds == null ? '—' : displayPounds(item.linePricePounds!)`.
   - `columnWidths`: `0: FlexColumnWidth()`, `1: FixedColumnWidth(52 * scale)`, `2: FixedColumnWidth(72 * scale)`, `3: FixedColumnWidth(88 * scale)`.
8. Toggle button labels: `'عرض المزيد'` → `'إظهار المزيد'`, `'عرض أقل'` → `'إظهار أقل'`. Keep key `ledger-items-more-${kind}-${id}`.
9. Delete the two fallback `Text`s that print `'عدد القطع: …'` (owner does not want piece counts on cards). Keep the `itemSummary` fallback text but without the piece count part (just `line.itemSummary!`).
10. Keep loading (`LinearProgressIndicator`), failure (`'تعذر تحميل الأصناف. إعادة المحاولة'`) and empty (`'لا تحتوي العملية على أصناف مفصلة.'`) states exactly as they are.

**Acceptance**
- On the ledger home, each sale and purchase card shows, without any extra tap, a horizontal table of up to 3 items: name, karat, grams (3 decimals), price.
- A 5-item invoice shows 3 rows + «إظهار المزيد»; tapping shows 5 rows + «إظهار أقل».
- No unfold icons next to «دفتر البيع» / «دفتر الشراء» or in the history filters.
- No «عدد القطع» on any card.

**Tests**
- `app/test/ledger_line_items_test.dart` (create if missing): payload with `line_price_piastres: "125050"` → `linePricePounds == '1250.50'`; missing price → `null`; malformed price → `null`.
- `confirmed_ledger_dashboard_test.dart`: card with 2 items → 2 rows, no `ledger-items-more-*`; card with 5 items → 3 rows + «إظهار المزيد»; tap → 5 rows + «إظهار أقل».
- Remove assertions on `ledger-journal-details-*` / `ledger-history-details` in: `batch2_ledger_capture_test.dart`, `confirmed_ledger_dashboard_test.dart`, `ledger_ui_refinement_capture_test.dart`, `owner_feedback_completion_test.dart`.
- Cache test in `daily_ledger_widget_test.dart`: the fake gateway's `operation()` is called once per operation id across two rebuilds, and again after a refresh.

---

## Task 4 — Note indicator on cards (FB-008)

**File** `app/lib/src/features/daily_ledger/presentation/ledger_journal_table.dart`

**Steps**
1. In `build`, compute `final showNote = line.hasNote && !line.isDailyNote;`.
2. Wrap the sequence-number pill (`DecoratedBox` with `'${widget.position}'`) in a `Stack(clipBehavior: Clip.none, children: [pill, if (showNote) PositionedDirectional(top: -3, end: -3, child: dot)])`, where `dot` is:
   ```dart
   Semantics(
     label: 'فيها ملاحظة',
     child: Tooltip(
       message: 'فيها ملاحظة',
       child: Container(
         key: Key('ledger-note-dot-${line.kind}-${line.operationId}'),
         width: 12,
         height: 12,
         decoration: BoxDecoration(
           color: scheme.error,
           shape: BoxShape.circle,
           border: Border.all(color: scheme.surfaceContainerLow, width: 2),
         ),
       ),
     ),
   )
   ```
3. Nothing else changes; opening the card still shows the note in the existing details screen.

**Acceptance**: any card whose invoice has a note shows a small red dot on the number circle in both themes; cards without a note show nothing.

**Tests** (`confirmed_ledger_dashboard_test.dart`): line with `hasNote: true` → dot key found; `hasNote: false` → not found; `isDailyNote: true` → not found.

---

## Task 5 — Daily ledger header: no menu icon, real ledger logo fallback, greeting always (FB-004, FB-006, part of FB-005)

**File** `app/lib/src/features/daily_ledger/presentation/ledger_app_bar.dart`

**Steps**
1. Delete the `onOpenMenu` field/constructor parameter, the `openMenu` local, the `_PillIconButton` with key `workspace-menu`, and the import of `workspace_chrome.dart`.
2. Title text: always `'أهلاً $shopName'` (collapsed and expanded). Keep `maxLines: collapsed ? 1 : 2`, ellipsis.
3. `_ShopMark` fallback (both the `bytes == null` branch and `errorBuilder`): replace `Padding(padding: EdgeInsets.all(10), child: BrandMark(size: 28))` with `const BrandMark(key: Key('ledger-default-logo'), size: 48)` — no padding, fills the 48×48 tile. (`BrandMark` accepts `super.key`; its inner `CustomPaint` keeps its own `brand-mark` key, so existing tests on `brand-mark` keep working.)
4. `_ShopMark` semantics label: `'صورة المتجر'` → `'لوجو المحل'`.

**Acceptance**: no hamburger icon; shop without logo shows the full brown/cream ledger logo filling the square; greeting «أهلاً {اسم المحل}» visible also when scrolled/collapsed.

**Tests**
- `app/test/ledger_app_bar_shop_image_test.dart`: no `workspace-menu`; null bytes → `ledger-default-logo` found; corrupted bytes → `ledger-default-logo` found; collapsed → text `'أهلاً <name>'`.
- Update `ledger-title` expectations in `auth_screen_test.dart`, `daily_ledger_capture_test.dart`, `daily_notes_capture_test.dart`, `workspace_practice_test.dart` if they expect the bare name.

---

## Task 6 — Remove the drawer; «الحساب» tab becomes «المزيد» (FB-005)

**Files**
- `app/lib/src/shell/shop_workspace.dart`
- `app/lib/src/shell/workspace_chrome.dart` (delete)
- `app/lib/src/features/customers/presentation/customer_screen.dart`
- `app/lib/src/features/inventory/presentation/inventory_widgets.dart`
- `app/lib/src/features/reports/presentation/reports_screen.dart`

**Steps — remove drawer**
1. Delete `workspace_chrome.dart` and every import of it.
2. In `customer_screen.dart`, `inventory_widgets.dart`, `reports_screen.dart`: replace `leading: WorkspaceChrome.menuButton(context)` with nothing (remove the `leading:` argument when it was only that; in `customer_screen.dart` keep the back button for non-list stages: `leading: _stage == 'list' ? null : IconButton(...)`).
3. In `shop_workspace.dart`: delete `_workspaceDrawer()`, `_drawerLink()`, `_openDrawer()`, `_scaffoldKey`, the `drawer:` arguments on both `Scaffold`s, the `WorkspaceChrome(...)` wrapper in `build`, and the `leading: IconButton(key: Key('workspace-menu') …)` in `_page()`.

**Steps — «المزيد» tab**
4. `_labels[4]`: `'الحساب'` → `'المزيد'`. `_icons[4]`: `Icons.person_outline` → `Icons.grid_view_rounded`. (Rail and bottom bar both read these lists; keep key `workspace-nav-4`.)
5. Rename `_accountPage()` → `_morePage()`; AppBar title `'المزيد'`, no `leading`.
6. In the header card: the `CircleAvatar` fallback (no image) shows `const BrandMark(size: 40)` instead of `Icons.storefront_outlined`.
7. Delete the sentence `'افتح القائمة للتنقل إلى التجار والصيانة والديون والتقارير.'`.
8. Directly under the header card, add a new group using the existing `_settingsGroup(title: 'الصفحات', children: [...])` with these `_link`s, in this order, with the **same visibility conditions and same keys** the drawer used:

   | Label | Icon | Visible when | Action | Key |
   |---|---|---|---|---|
   | التقارير | `Icons.assessment_outlined` | `shop.hasPermission(ShopPermission.reports)` | `_select(3)` | `workspace-reports` |
   | التحليلات | `Icons.insights_outlined` | reports permission && `analyticsBuilder != null` | push `analyticsBuilder` | `workspace-analytics` |
   | التجار والأمانات | `Icons.storefront_outlined` | `isOwner && traderBuilder != null` | `_openTraders()` | `workspace-traders` |
   | الصيانة | `Icons.handyman_outlined` | `isOwner && repairBuilder != null` | `_openRepairs()` | `workspace-repairs` |
   | الديون | `Icons.account_balance_wallet_outlined` | `isOwner && debtBuilder != null` | `_openDebts()` | `workspace-debts` |
   | فريق عد التقفيل | `Icons.fact_check_outlined` | `isOwner && closingStaffBuilder != null` | `_openClosingStaff()` | `workspace-closing-staff` |
   | سجل العمليات | `Icons.history_outlined` | `isOwner && auditTrailGateway != null` | push `AuditTrailScreen` | `workspace-audit-trail` |

   The bottom bar on mobile has no «التقارير» tab, so this link is the mobile path to reports. On desktop the rail also has it; both are fine.
9. Everything else on the page stays in the same order: «الأرقام والمخزون», «إعدادات المتجر», «الفاتورة», «الحساب والدعم» (theme toggle, help, support, change shop, sign out).
10. Fix the mobile `selectedIndex` so «المزيد» is highlighted when reports (index 3) is open from it: `selectedIndex: _destination == 3 ? 3 : indices.indexOf(_destination)` → keep as is (3 is the position of «المزيد» in `[0,1,2,4]`). No change needed; add a test (below).

**Acceptance**
- No hamburger icon on any shop page (ledger, inventory, customers, reports, more, mobile and desktop).
- Bottom bar / rail last item reads «المزيد» with a grid icon.
- «المزيد» lists every page previously in the drawer, respecting owner/partner/employee permissions.

**Tests**
- Replace drawer navigation (`tap(find.byKey(Key('workspace-menu')))` then a drawer tile) with `tap(find.byKey(Key('workspace-nav-4')))` then the tile key, in: `audit_trail_screen_test.dart`, `debt_widget_test.dart`, `repair_pending_navigation_test.dart`, `repair_widget_test.dart`, `report_widget_test.dart`.
- Replace `'الحساب'` (as the tab/page title) with `'المزيد'` in: `audit_trail_screen_test.dart`, `debt_widget_test.dart`, `owner_feedback_2026_10_19_capture_test.dart`, `repair_pending_navigation_test.dart`, `repair_widget_test.dart`, `support_capture_test.dart`, `widget_test.dart`, `workspace_practice_test.dart`. Leave «بيانات الحساب» / «إنشاء الحساب» strings untouched — they are different texts.
- New test in `widget_test.dart` (or a new `more_tab_test.dart`): owner sees all 7 links; employee without reports sees none of التقارير/التحليلات and none of the owner-only links; `find.byKey(Key('workspace-menu'))` finds nothing on every destination.
- Mobile: open «المزيد» → tap «التقارير» → reports page shows and nav-4 is the selected destination.

---

## Task 7 — «صورة المتجر» becomes «لوجو المحل» everywhere (FB-009 part 1)

**Files**
- `app/lib/src/features/shop_accounts/presentation/shop_image_copy.dart`
- `app/lib/src/shell/shop_workspace.dart`
- `app/lib/src/features/invoice_appearance/presentation/invoice_appearance_screen.dart`
- `app/lib/src/features/auth/presentation/auth_screen.dart`

**Steps** — replace the copy exactly (code identifiers stay `shopImage…`; only user text changes):

`shop_image_copy.dart`

| Constant | New value |
|---|---|
| `title` | `'لوجو المحل'` |
| `body` | `'يظهر لوجو المحل أعلى الدفتر اليومي وعلى الفواتير.'` |
| `pick` | `'اختيار اللوجو'` |
| `change` | `'تغيير اللوجو'` |
| `clear` | `'إزالة اللوجو'` |
| `save` | `'حفظ اللوجو'` |
| `preparing` | `'جاري تجهيز اللوجو…'` |
| `success` | `'تم حفظ لوجو المحل.'` |
| `cleared` | `'تمت إزالة لوجو المحل.'` |
| `empty` | `'لا يوجد لوجو للمحل بعد. يظهر لوجو الدفتر بدلاً منه.'` |
| `signupHint` | `'لوجو المحل (اختياري)'` |
| `signupHelp` | `'التقط صورة للوجو بالكاميرا أو اختره من المعرض. يظهر على الفواتير وأعلى الدفتر اليومي.'` |
| `pickSheetTitle` | `'مصدر لوجو المحل'` |
| `rejected` | `'تعذّر استخدام هذه الصورة كلوجو. جرّب صورة أخرى.'` |
| `unavailable` | `'تعذّر حفظ لوجو المحل. أعد المحاولة.'` |
| `loadFailed` | `'تعذّر تحميل لوجو المحل. اختر اللوجو مجدداً لحفظه.'` |

Other places:
- `shop_workspace.dart` «إعدادات المتجر» link `'صورة المتجر'` → `'لوجو المحل'`, icon `Icons.photo_camera_outlined` → `Icons.image_outlined`.
- `invoice_appearance_screen.dart`: replace every user-visible `صورة المتجر` with `لوجو المحل` and every `المزيد ← صورة المتجر` with `المزيد ← لوجو المحل` (lines around 645, 659, 667, 748, 891, 900). Toggle title becomes `'إظهار لوجو المحل على الفاتورة'`.
- `auth_screen.dart` signup preview: the 64×64 placeholder when no image shows `const BrandMark(size: 48)` instead of `Icons.storefront_outlined`.
- `grep -rn "صورة المتجر\|صورة المحل" app/lib` must return nothing afterwards.

**Tests**: update `invoice_appearance_screen_test.dart` text finders; add a check that the signup form shows «لوجو المحل (اختياري)».

---

## Task 8 — Logo goes onto invoices automatically (FB-009 part 2)

Today: the signup checkbox `signup-invoice-logo` («اختيار الصورة أيضاً كشعار للفواتير») saves a *local draft* and the owner must later open «مظهر الفاتورة», upload, review and save. The owner wants: upload the logo once → it is on the invoice.

Constraint: invoice appearance is a reviewed, versioned server revision ([ADR 0021](../adr/0021-invoice-appearance-and-presentation-copies.md)) and needs an **active** entitlement; a new shop is still pending at signup. So the logo is applied automatically as soon as the shop can write, using the same server calls the appearance screen already uses. No new RPC, no new R2 kind.

**Files**
- New: `app/lib/src/features/invoice_appearance/application/apply_shop_logo_to_invoice.dart`
- `app/lib/src/features/invoice_appearance/presentation/invoice_appearance_screen.dart` (extract logic only)
- `app/lib/src/features/auth/presentation/auth_screen.dart`
- `app/lib/src/shell/shop_workspace.dart`
- `app/lib/src/features/shop_accounts/presentation/shop_image_screen.dart`
- `app/lib/src/features/shop_accounts/presentation/shop_accounts_gate.dart` (wiring)

**Steps**
1. Create `ApplyShopLogoToInvoice` (pure application class, no widgets) with:
   ```dart
   Future<ApplyLogoOutcome> call({
     required String userId,
     required String shopId,
     required Uint8List logoBytes,
   });
   ```
   `ApplyLogoOutcome` is an enum: `applied`, `alreadyApplied`, `notAllowed` (not owner / entitlement not active), `failed`.
   Its body is the **same sequence** the appearance screen runs today — move that code here and have the screen call it, do not duplicate:
   a. `readAppearance` → current saved value.
   b. If saved logo sha256 equals sha256 of `logoBytes` → `alreadyApplied`.
   c. Upload/confirm logo exactly as `_uploadLogo` does (`uploadInvoiceLogo` → `confirmInvoiceLogo`, using `LogoUploadStore` phases and the same idempotency handling).
   d. Build the appearance payload = current saved values with only the logo fields replaced (slogan, address, layout, accent unchanged).
   e. `reviewAppearance` then submit via `InvoiceAppearanceFlow.submitAppearance` with one idempotency key kept across retries (same as `_review` / `_save`); reconcile via `_applyOutcome` logic.
   f. On confirmed outcome clear the local `LogoUploadStore` record → `applied`.
2. Signup (`auth_screen.dart`): delete the `CheckboxListTile` `signup-invoice-logo` and `_useImageForInvoices`. When an image was chosen, **always** call `saveRegistrationInvoiceLogo(image)` after registration (keep the existing failure snackbar but change its text to `'تم إنشاء الحساب، وتعذر تجهيز اللوجو للفاتورة. سيُعاد المحاولة تلقائياً.'`).
3. Workspace (`shop_workspace.dart`): when the shop is owner, entitlement active and `_logoDraft` resolves to a record with `fromRegistration == true`, run `ApplyShopLogoToInvoice` once in the background (guard with a bool so it runs once per workspace instance).
   - While running, the «مظهر الفاتورة» tile subtitle shows `'جارٍ إضافة اللوجو إلى الفاتورة…'`.
   - `applied` / `alreadyApplied` → SnackBar `'تمت إضافة لوجو المحل إلى الفاتورة.'`, subtitle removed.
   - `failed` → subtitle `'تعذر إضافة اللوجو إلى الفاتورة. اضغط للمحاولة مرة أخرى.'`; tapping the tile opens «مظهر الفاتورة» (existing screen resumes the draft).
   - `notAllowed` → do nothing (draft kept; it runs on the next workspace load once active).
4. «لوجو المحل» screen (`shop_image_screen.dart`): after a confirmed save, if owner and active, call `ApplyShopLogoToInvoice` with the saved bytes; show `'جارٍ إضافة اللوجو إلى الفاتورة…'` then `'تم حفظ اللوجو وإضافته إلى الفاتورة.'` or, on failure, `'تم حفظ اللوجو، وتعذر إضافته إلى الفاتورة. أعد المحاولة من المزيد ← مظهر الفاتورة.'`. The save button stays disabled while either request is in flight. When the logo is **cleared**, do not touch the invoice appearance.
5. Wire the new class in `shop_accounts_gate.dart` where the invoice appearance gateway is already built, and pass it down to `ShopWorkspace` and the shop image screen builder as an optional dependency (null in tests that do not need it).

**Acceptance**
- New owner picks a logo at signup → after the shop becomes active, the first workspace load adds it to the invoice without the owner opening «مظهر الفاتورة»; next branded invoice PDF shows it.
- Owner changes logo from «المزيد ← لوجو المحل» → invoice appearance gets a new revision with the new logo; slogan/address/layout/accent unchanged.
- Expired/pending shop: nothing is sent; draft waits.
- Retrying after a network failure creates exactly one appearance revision (same idempotency key).

**Tests** (new `app/test/apply_shop_logo_to_invoice_test.dart` with a fake `InvoiceAppearanceGateway`)
- applies logo and keeps other appearance fields;
- same sha → `alreadyApplied`, no write;
- inactive entitlement → `notAllowed`, no write;
- transport failure then retry → one revision, same key;
- update `meeting_registration_logo_test.dart` and `owner_meeting_capture_test.dart` (checkbox removed; draft always saved);
- existing `invoice_appearance_screen_test.dart` must still pass after the extraction.

---

## Task 9 — Docs, visual review, validation

1. New ADR `docs/adr/0039-owner-feedback-2026-11-08-ledger-and-navigation.md` (use `0000-template.md`), recording: metric renames; money tiles without 21k line; purchase breakdown; removal of «عرض المزيد» metrics sheet; items always visible on cards with 3-item preview and price column; note dot; drawer removed and «المزيد» tab; «لوجو المحل» naming; automatic invoice logo application (amends the manual-only path in ADR 0021, keeps review/versioning/entitlement rules); the three clarification decisions above.
2. Add the ADR to `docs/decisions.md` and the ADR list in `docs/README.md` if that file lists ADRs; update affected rows in `docs/requirements-matrix.md`.
3. Visual review (required by AGENTS.md): run the app on Windows debug and an Android emulator; check the ledger home, both weight sheets, a 5-item sale card, a card with note, the «المزيد» page, the header with and without logo, signup step with «لوجو المحل» — each in **light and dark**, at **360 px, 390 px and ≥1280 px** widths, and with text scale 1.3. Fix overflow or contrast issues before finishing.
4. Final gates from `app/`: `dart format --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`. React/SQL gates are not affected (no admin or schema change) — state that in the hand-off.
5. Add a dated validation record `docs/operations/owner-feedback-2026-11-08-validation.md`: commands run, results, screenshots taken, anything not verified. Run `git diff --check`.

---

## Traceability

| Owner item | Task |
|---|---|
| FB-001 money tiles without 21k line; «وزن مباع» / «وزن مشترى» | 1 |
| FB-002 no piece count in sold-weight sheet | 2 |
| FB-003 purchased-weight sheet, tap container, no «عرض المزيد» | 2 |
| FB-004 ledger logo when no shop logo | 5 (+7 avatar/signup) |
| FB-005 remove hamburger; «الحساب» → «المزيد» with remaining pages | 5, 6 |
| FB-006 shop name greeting in header | 5 |
| FB-007 items on sale/purchase cards, show more | 3 |
| FB-008 note indicator | 4 |
| FB-009 «لوجو المحل» + automatic invoice logo | 7, 8 |
