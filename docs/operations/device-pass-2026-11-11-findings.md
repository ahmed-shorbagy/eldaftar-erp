# Device pass 2026-11-11: findings and work list

Scope: a full hands-on run of the Flutter app on the Android emulator (Pixel, 1080×2400, Arabic RTL, dark theme first) against the development project `xchapwvmvoefriqcxtvn`, test shop «ahmed», checked against the owner requirements recorded from 2026-11-06 to 2026-11-10 (ADR 0039–0046 and their plans). Test data was added and removed freely; it is development data only.

Status key: **Fixed** = changed in the working tree (not committed); **Open** = recorded for a later session; **Decision** = needs the owner or product to choose before code changes.

Severity: **S1** blocks a core workflow or corrupts data, **S2** wrong result or broken feature with a workaround, **S3** UX/visual defect.

## Fixed in this pass

| # | Sev | Area | Finding | Fix | Evidence |
|---|---|---|---|---|---|
| F1 | S1 | Ledger edit | «تعديل» on any sale or purchase posted after 2026-11-05 failed with «تعذر إعداد التغيير أو حفظه». `20261027140000_payment_method_labels` stores `label_ar` in each tender; `trade_change_assert_draft` (and the post path) rejected that key. No edit had ever succeeded on development. | Migration `20261111090000_trade_change_tender_label.sql`: both public trade-change RPCs drop the server-owned `label_ar` from `p_replacement` before validating and hashing (`…_before_tender_label` kept, revoked). Deployed to development, history repaired. | `supabase/tests/trade_change_tender_label.sql` (registered); hosted rolled-back runs of it plus `expense_return_change`, `purchase_paid_and_scrap_routing`, `customer_auto_capture`, `pending_invoices_open_day`, `financial_day_report`, `financial_week_report` pass. Edit confirmed in the app. |
| F2 | S1 | Ledger edit / sync | Edit and delete reviews turned stale within ≤45 s and could not be confirmed («أعد فتح المراجعة…»). `ShopSyncCoordinator`'s poll invalidated every scope on each tick without reading the revision, so every open screen also reloaded every 45 s. | `shop_sync_coordinator.dart`: the poll now runs `_catchUp()` (read, compare revisions, invalidate only changed scopes; full refresh only when the read fails). | `app/test/shop_sync_coordinator_test.dart` (3 new tests; the unchanged-revision test fails on the old code). Edit confirmed after 55 s on the review screen. |
| F3 | S1 | Customers | Every customer auto-created from a sale or purchase (ADR 0043 B-D3) showed «بدون رقم هاتف» with no WhatsApp or call action. Customer reads join phones to `customer_number_declarations`; auto-capture inserted the phone without starting a declaration. | Migration `20261111091000_customer_phone_declaration.sql`: an after-insert trigger on `customer_phones` starts the `unknown` declaration; backfill for phones missing one. Deployed to development. | `supabase/tests/customer_auto_capture_phone.sql` (registered; fails without the fix with `list phones []`); `customers`, `customer_saved_numbers`, `customers_edges`, `batch_c_review_fixes` pass with it. Phone, WhatsApp and call buttons confirmed in the app. |
| F4 | S2 | Inventory calculator | «اجمالي الوزنة 21 مع النقدية»: the price field groups digits («5,000») and the dialog parsed the grouped text, so every price ≥ 1,000 was rejected. | `inventory_figures.dart` parses with `cashInputValue`. | `app/test/inventory_item_grid_test.dart` «the cash calculator accepts a grouped gram price». 5,000 → 483.25 g confirmed. |
| F5 | S1 | Inventory calculator | Closing the price dialog (Back or Cancel) disposed its controller during the exit animation; in debug the whole inventory tab became a red error screen. | The dialog is its own `StatefulWidget` that owns and disposes the controller; Done key submits. | Same test (it reproduced the crash before the fix). |
| F7 | S3 | Inventory carousel (C-D5) | The figure list was `reverse: true`; in RTL that put the first figure («عيار 18») on the far left, and free scrolling left cards cut at both edges. | `inventory_figures.dart`: no reverse; `PageScrollPhysics` with slots of exactly one viewport per page. Order and snapping confirmed on the emulator at 375 px and at landscape width. | `app/test/inventory_item_grid_test.dart` «the first figure is the rightmost tile in RTL» (fails on the old code). |
| F6 | S3 | Arabic RTL text | Latin names and phone numbers scrambled «·» lines and names: «ahmed · 5 نوفمبر» (notes, repair log, debt log) and «عميل 201001234567+» (customer card/detail), «الهاتف: +» wrapped alone (repair detail). | `isolateText` / `isolatePhoneRuns` in `theme/amount_format.dart`, applied to daily notes, repair log and phone, debt log, customer card and detail names. | `app/test/isolate_phone_runs_test.dart`. |

## Open findings

### Data and correctness

| # | Sev | Area | Finding | Suggested direction |
|---|---|---|---|---|
| O1 | S1 | Stock lots (B-D14) | When a sale line's weight differs from the last piece of its named lot (for example an edit 10.50 g → 10.00 g, or a real sale whose weight differs from the recorded piece), `consume_fifo_named` skips that lot (it may not leave weight with zero pieces) and takes the weight from the oldest lots of other items. Observed: the edited chain sale took 8.80 g + 1.20 g from «خاتم» lots; «سلاسل 18» still shows 1 piece / 10.50 g, «خواتم 18» lost a piece. | **Decision**: when the last piece of a named lot is sold, either take the whole remaining weight (difference becomes a stock adjustment), or allow a residue, or block with a clear message. Then fix the edit path too. |
| O2 | S2 | Stock lots / grid | The test shop's pooled opening lots are named «رصيد سابق مجمّع» (`legacy_aggregate = true`, from an older backfill). B-D14's pooled-second preference and C-D4's row label only recognize «رصيد افتتاحي مجمّع», so this shop shows «رصيد سابق مجمع» in the table, never prefers the pooled lot, and offers «رصيد سابق مجمع» as a sellable item under «أخرى». Only one shop has such lots. | Treat `legacy_aggregate` lots as the pooled opening lot in `consume_fifo_named`, `get_inventory_item_grid_v1`, and the product list; hide the pooled pseudo-product from «أخرى». |
| O3 | S2 | Invoice logo (ADR 0039) | The shop has a logo and an active entitlement, but no invoice appearance revision exists, so invoices print the generic diamond. Automatic application runs only for a signup draft or a logo saved after 2026-11-08; logos saved before are never applied. | One-time: apply the current shop logo to invoice appearance for active shops without a revision (client on first owner workspace, or a reviewed server backfill). |
| O4 | S3 | Weight display | The edit screen shows stored weights with three decimals («10.500») while new entry allows two; the weight sheets order karats differently (22, 21, 18, 14) from the choice lists (18, 21, 22, 14). | Align display rules with design-system.md. |

### UX and visual (owner-facing)

| # | Sev | Screen | Finding |
|---|---|---|---|
| U1 | S2 | Daily close | One Back press (or swipe back) discards every count entered, with no confirmation and no saved draft. This is the owner's longest daily form. Add a discard confirmation and keep a local draft (M1 tier 5). |
| U2 | S3 | Ledger home | The ⚡ quick-actions button covers the weight column of the cards and fully hides values on some rows. Reserve bottom padding or move the default position. |
| U3 | S3 | Sale/purchase review | The review does not show per-line prices (when «سعر لكل صنف» is on) or the customer phone. |
| U4 | S3 | Sale/purchase form | With per-line prices, the payment amount is not prefilled with the line-price total. |
| U5 | S3 | Expense | Expense cards show only «مصروف» and the amount, not the description. The expense form puts «طرق الدفع» above the description; the expense review shows the five-step sale stepper and an empty divider block; the detail says «لا توجد بيانات عميل». |
| U6 | S3 | Trade-change review | Shows «التغير في مستحقات الشراء» on sales (and on every purchase now that purchases are fully paid). Hide when zero / not a purchase with a legacy payable. |
| U7 | S3 | Edit screen | Extra «الفئة» dropdown not on the add form; the category grid highlights the last-added category, not the line being edited; prices show «25000.00» instead of «25,000». |
| U8 | S3 | Card labels | «اسم البائع» on a purchase card names the staff member, but on a purchase the seller is the customer. Use «المسجِّل» or similar. |
| U9 | S3 | Operation detail | Title «بيع» appears twice (app bar and body); the body is a plain text list. |
| U10 | S3 | Payment methods sheet | Title «وسائل الدفع» repeated as the sheet title and the section title. |
| U11 | S3 | Inventory carousel | Order and snapping fixed (F7). Still open: tiles are tall with empty space below the value. |
| U12 | S3 | Repairs | After every status change the owner lands on a bare «تم حفظ الطلب» page and must go back and reopen the repair. Handover with «تحصيل الكل» does not prefill the amount or method (later collection does). Collection asks for the same amount twice for a single tender. Review lists weight twice («الوزن» and «الوزن المدخل»). «العيار» and «العطل» fields touch with no gap. Status changes follow M1 (toast and stay on the repair). |
| U13 | S3 | Customers | After a status change the success page is cramped (icon and text not centered). The selected filter chip scrolls half off-screen. The success page is replaced under M1. |
| U14 | S3 | Daily notes | The edit sheet has no title. A previous unsent draft image appears preloaded on entry. |
| U15 | S3 | Day close | Pressing Done moves focus to the next cell, which is easy to mistype into (owner should see where the cursor is). Tapping outside a count cell does not close the keyboard. |
| U16 | S3 | Ledger after close | «إضافة بيع» / «إضافة شراء» stay styled as active while no day is open; tapping shows «يوم العمل مغلق…». Disable them or replace with «فتح يوم جديد» (M1 day-closed banner). |
| U17 | S3 | Ledger header after close | The header still reads «يوم العمل 30 سبتمبر 2026» after that day is closed. Show «لا يوجد يوم مفتوح» or the last closed date as such. |
| U18 | S3 | «الدفاتر» list | Each closed day shows only «مقفول · فُتح 14:19»; the close time is not shown. |
| U19 | S3 | Admin sign-in | A valid shop-owner account gets «تعذر تسجيل الدخول. تحقق من البيانات» (reads as wrong password). **Decision**: keep generic (no account enumeration) or say the account has no admin access. |
| U20 | S3 | Scrap-to-stock | Returns straight to the ledger with a snackbar, unlike sale/purchase which show a success page; weight there accepts three decimals while sale/purchase accept two. Align (M1 outcome screen). |

### M1 — Production messaging and feedback system (owner request, 2026-11-11)

| # | Sev | Area | Finding |
|---|---|---|---|
| M1 | S2 | Whole Flutter app | The owner rates the current snackbar feedback as poor and asks for production-level messaging across the app. Today every screen chooses its own form: 32 raw `ScaffoldMessenger.showSnackBar` calls in 8 files with the default Material bar (no icon, no success/error colour, no semantics role, generic copy such as «تم حفظ العملية بنجاح»), four separate inline-notice widgets, four hand-built success pages, and about 30 ad-hoc dialogs in 16 files. The same outcome looks different on different screens, and several findings above (U1, U12, U13, U16, U17, U20) are symptoms of having no shared rule. |

**Goal.** One messaging system, owned by the app shell and built from the existing theme tokens, that decides *how* each outcome is shown, *what* it says in Arabic, *how long* it stays and *what the owner can do next*. Every mutation keeps the AGENTS.md contract: a clear pending, success or failure state; nothing financial shown as saved before the server confirms it; unknown outcomes frozen behind an idempotent retry.

#### Message tiers

Each outcome uses exactly one tier. The choice follows from what happened, not from the screen.

| Tier | Use for | Behaviour | Never use for |
|---|---|---|---|
| **1. Outcome screen** | Confirmed operations that change cash, stock, scrap or balances: sale, purchase, expense, scrap-to-stock (U20), trade change/delete, opening, day close, repair handover with collection, debt settlement. | Replaces the review in place. Tertiary check icon, specific title («تم حفظ البيع»), the confirmed net effect (cash and gold per karat, from the server response), and the next actions (share invoice, new operation of the same kind, back to the ledger). Back returns to the ledger, never to the review. | Non-financial saves; anything not yet confirmed. |
| **2. Toast** | Short confirmations after returning to context: note saved, customer status changed (U13), repair status changed without money (U12), logo applied, settings saved on the device, «تم نسخ الرقم». | Floating card, one at a time, auto-dismiss (timing below), optional single action, swipe or ✕ to dismiss. The owner stays on the record they were working on. | Errors that block work, pending states, anything the owner must read to stay correct. |
| **3. Inline banner** | Lasting conditions of a screen or the shop: offline, a request awaiting confirmation, refresh failed after a confirmed write, stale review (F2), day closed (U16/U17), read-only subscription, retention warning, announcement. | Sits at the top of the content it affects (below the app bar), uses its container role, stays until the condition clears, carries at most one primary action («إعادة المحاولة», «فتح يوم جديد», «تجديد الاشتراك»). Replaces `_PendingNotice`, `_RefreshFailedNotice`, `InventoryNotice`, `_InlineNotice`; `SubscriptionNoticeBanner` and `AnnouncementBanner` adopt the same component. | One-off confirmations. |
| **4. Field message** | Validation of a single input, and the submit-time summary of a form. | Text under the field (error role), the field announces it; on submit, a short summary banner at the top of the form («راجع حقلين قبل الحفظ») and focus moves to the first invalid field. Errors clear as soon as the value is valid. | Server or network failures. |
| **5. Dialog** | Decisions the owner must make before anything happens: discard unsaved counts (U1), delete, leave a form with a draft, a conflicting edit, permanent actions. | Title as a question, body stating the consequence, the destructive verb as the button label («تجاهل العدّ», «حذف الملاحظة»), the safe choice («متابعة التعديل») as the default; Back equals the safe choice. | Information only («تم…»), errors, anything a banner can carry. |
| **6. In-flight state** | Between submit and the server reply. | The submit button shows a spinner and «جارٍ الحفظ…», the form freezes, duplicate taps are ignored; after 8 s without a reply the screen switches to the unknown-outcome state below. | Toasts or dialogs saying «جارٍ الحفظ». |

#### Failure handling (one mapping for every gateway)

All data-layer failures map through one presentation-side table from the domain failure kinds the gateways already return (`…Rejected`, `…Unknown`, network, permission) to a tier, Arabic copy and action, so no screen writes its own error text:

| Failure kind | Tier | Copy direction | Action |
|---|---|---|---|
| No network before sending | Banner + button stays enabled | «لا يوجد اتصال. لم يُرسل شيء.» | «إعادة المحاولة» |
| Unknown outcome (timeout, lost reply) | Banner in the form, form frozen | «لم يصل رد الخادم. لا تكرر العملية؛ نتحقق منها الآن.» | Automatic status check with the same idempotency key, then «إعادة المحاولة» only if the server has no record |
| Server rejected with a reason | Banner in the form, values kept | The reason in owner words (e.g. «يوم العمل مغلق. افتح يومًا جديدًا أولًا.») | The fix, when one exists |
| Missing grant / owner-only | Banner, control hidden or disabled where known in advance | «هذا الإجراء غير متاح لحسابك.» | — |
| Subscription read-only | Shop-level banner (existing kind) | Existing copy | «تجديد الاشتراك» |
| Stale data / revision changed (F2) | Banner on the open review | «تغيّرت البيانات منذ فتح المراجعة.» | «تحديث المراجعة» (keeps the draft) |
| Local device storage failure | Toast (info) | «تعذر حفظ الاختيار على الجهاز. يسري في هذه الجلسة.» | — |
| Unexpected error | Banner | «حدث خطأ غير متوقع. لم يُحفظ شيء.» with a short reference code for support; never raw exception text | «إعادة المحاولة» |

#### Toast specification

- **Placement:** phone — floating above the bottom navigation and the ⚡ quick-actions button, 12 px gutters (`ledgerPhoneGutter`), lifted above the keyboard inset and the system gesture area; wide (≥ 840) — bottom-start corner (right side in RTL), width ≤ 480 px. It never covers the submit button or the figure being confirmed.
- **Anatomy:** start-side icon, one-line title (600), optional one-line body (400), optional text action, ✕ close; 48 px targets; 22 px-family corner radius; Cairo at the shared scale; figures and phone numbers in LTR isolates (`isolateText`).
- **Colour roles (no new palette):** success — tertiary container / on-tertiary-container; error — error container / on-error-container; warning — secondary container; info — surface container high with on-surface. Light and dark checked for WCAG AA contrast.
- **Timing:** success 4 s, info 5 s, error toasts (only the non-blocking device-storage kind) 6 s; add 50 ms per character beyond 60, capped at 10 s. A toast with an action stays at least 8 s. The timer pauses while pressed, hovered or focused, and toasts do not auto-dismiss when the platform reports accessible navigation (TalkBack/VoiceOver).
- **Queue:** one visible, up to 3 queued, identical messages within 3 s merge, a newer message with the same key replaces the older one, a banner or outcome screen for the same event suppresses its toast.
- **Lifetime and privacy:** owned by one app-level messenger above the navigator, so a toast raised before `pop` shows on the destination; the queue is cleared on sign-out, account switch and shop switch so no message leaks into another session.
- **Accessibility and motion:** live-region announcement (polite for success/info, assertive for errors), readable at 200 % text scale with wrapping instead of truncation, slide-and-fade normally, fade only under reduced motion, swipe to dismiss in either direction.

#### Copy rules

- Name the object and the result: «تم حفظ البيع», «تم مسح الملاحظة», «تم تغيير حالة العميل» — never a generic «تمت العملية بنجاح».
- A failure states what did *not* happen and what to do next: «تعذر حفظ الشراء. لم يُسجَّل شيء. أعد المحاولة.»
- Financial results quote the confirmed figures from the server, never client-computed totals.
- No exclamation marks, no English, no technical terms (RPC, timeout, revision), no instructional or tour copy (owner feedback 2026-10-05).
- All strings live in one Arabic copy catalog per feature so the wording can be reviewed in one place.

#### Current call sites to migrate

| Where | Today | Target |
|---|---|---|
| `daily_ledger_screen.dart` (×4 «تم حفظ العملية بنجاح») | Generic snackbar after returning from an operation | Outcome screen (financial) or specific toast; scrap-to-stock gets the outcome screen (U20) |
| `daily_ledger_screen.dart` (day-closed reason) | Snackbar after tapping an enabled-looking button | Prevented up front: day-closed banner with «فتح يوم جديد», buttons disabled (U16/U17) |
| `financial_operation_screen.dart` | Snackbar with the failure text | Failure mapping, banner in the form |
| `confirmed_ledger_dashboard.dart` (×2), `ledger_more_balances.dart` | Snackbar for device-preference failures and «تعذر إضافة العملية الآن» | Info toast; the add failure becomes a banner with retry |
| `daily_notes_screen.dart` (×3) | Success/failure snackbars with retry | Success toast; failure banner in the sheet keeping the draft |
| `auth_screen.dart`, `shop_workspace.dart` | Logo preparation / applied snackbars | Info / success toast |
| `shop_accounts_gate.dart` (×2) | Debt-reminder access snackbars | Warning toast (raised from a notification tap, with no screen to hold a banner) |
| `financial_trade_screen.dart`, `repair_screen.dart`, `debt_screen.dart`, `customer_screen.dart` success pages | Four hand-built pages, two of them bare («تم حفظ الطلب») | Shared outcome screen for financial results; toasts and return-to-record for repair status and customer status (U12, U13) |
| `_PendingNotice`, `_RefreshFailedNotice`, `InventoryNotice`, `_InlineNotice` | Separate inline notices | Shared inline banner |
| ~30 `showDialog` / `AlertDialog` uses | Mixed titles and button wording | Shared confirm dialog for decisions; informational dialogs become banners or toasts |

The admin dashboard has 18 MUI `Snackbar`/`Alert` uses in 8 files. It should follow the same tiers, copy rules and colour roles through `admin/src/theme/tokens.ts` in a separate, smaller pass after the Flutter system lands.

#### Delivery and gates

1. Shared components and the messenger under `app/lib/src/theme/` (or the shell), with the failure mapping in presentation and no Supabase types in it; add a «Feedback and messaging» section to `docs/design-system.md` with the tiers, roles and timing above.
2. Migrate the ledger and financial flows first (outcome screen, in-flight and unknown-outcome states), then notes, repairs, customers, debts, settings, auth.
3. A source test fails if `lib/` calls `showSnackBar` or builds a `SnackBar` outside the messenger, so the old pattern cannot return.
4. Tests: messenger queue, merge, replace, timing, pause, no auto-dismiss under accessible navigation, cleared on sign-out; semantics announcements; failure-mapping table per kind; RTL order; light and dark; 200 % text scale; keyboard inset; toast not covering the ⚡ button or the submit button; regression tests for U1, U12, U13, U16, U20 through the new components.
5. Emulator review at 375 px and wide, Arabic RTL, light and dark, with TalkBack, covering a success, a rejection, an offline send and an unknown outcome for a sale.

**Done when** every user-visible outcome in the app goes through one of the six tiers, no raw snackbar remains, the copy catalog is reviewed in Arabic, and the emulator review above passes in both themes.

#### M1 progress (2026-11-11, working tree, not committed)

Done, in the first milestone:

- `app/lib/src/theme/message_tone.dart` (tones, colour roles, icons, Arabic screen-reader labels), `app_messages.dart` (`AppMessages` toast messenger and `AppToast`), `app_banner.dart` (`AppBanner`), `feedback_copy.dart` (shared copy). The design guide's «Feedback and messaging — 2026-11-11» section describes them.
- Every raw snack-bar call is migrated (the 32 `SnackBar`/`ScaffoldMessenger` matches in 8 files). Ledger trades no longer add a toast on top of their own outcome page. Day close, cash transfer and scrap-to-stock show «تم إقفال يوم العمل», «تم تحويل النقدية» and «تمت إضافة الكسر إلى المخزون». The day-closed or loading block on «إضافة بيع/شراء» shows a warning or info toast. The trade-change failure shows only its in-form error banner (it used to appear twice). Notes get specific success and error toasts, and the unknown-outcome toast keeps its retry. Device-preference failures and debt-reminder taps show info or warning toasts, and signup and logo outcomes show warning or success toasts.
- `_PendingNotice`, `_RefreshFailedNotice`, `InventoryNotice` (now success/info/warning/error by command state) and `_InlineNotice` render through `AppBanner` with their existing keys.
- Sign-out clears every visible and queued toast.
- `test/app_messages_test.dart` (18 tests): the source guard against raw snack bars, durations, auto-dismiss, pause on press, close and action, no auto-dismiss under a screen reader, merge, replace, queue, clear, survival across a route pop, position above the bottom bar and in the wide start corner, every tone at 200 % text in light and dark (this caught an overflow, now fixed by stacking the action), banner tone/action/spinner, and 4.5:1 text contrast for every tone in both themes.

Still open under M1:

- One shared outcome-screen widget for the trade sheet, and the repair, debt and customer success pages. U12 and U13 (repair and customer status changes should show a toast and stay on the record) still need their flows changed.
- The shared confirm dialog and migration of the ~30 dialogs; U1 (discard confirmation and draft for the daily close).
- U16 and U17: disable «إضافة بيع/شراء» and show the day-closed banner with «فتح يوم جديد», instead of the toast on tap.
- Wiring each gateway's failure kinds through one mapping table. Today the migrated call sites use `FeedbackCopy`, but `inventoryFailureCopy`, `tradeChangeFailure` and other feature copy remain separate.
- Assertive announcement for error toasts. They use the snack bar's polite live region today.
- The full emulator review (light theme, wide layout, TalkBack, rejection and offline cases), and the admin dashboard pass (18 MUI `Snackbar`/`Alert` uses). Checked so far: a debug build on the emulator (dark, 1080×2400) showed the «تم مسح الملاحظة» success toast after a real note delete on development, placed above the gesture bar.
- Plain-text inline statuses that are not snack bars, for example «تم حفظ الملاحظة» after adding a note. It stays visible even after that note is deleted. These still need the banner or toast tier.

### Questions for the owner

- «المزيد ← المساعدة» opens platform Help articles. The owner's 2026-10-05 feedback removed guides and help cards; confirm the Help page itself should stay.
- O1 (which stock a sale takes when the weight differs from the recorded piece) needs a rule before code changes.
- M1: confirm that operations changing cash or stock keep a full outcome screen with the confirmed net effect, while non-financial saves (notes, repair or customer status, settings) return the owner to the record with a short toast.

## Previously recorded open items (from earlier validation notes)

- `supabase/tests/ledger_trade_change.sql` fails `return_write_still_granted` on development; it is not in `run-rls-tests.mjs`. Its expectation predates ADR 0041 D6 (the return/exchange RPCs stay). Update or retire the file.
- `npm run test:rls` on a local disposable database has not run on this machine (no Docker).
- Device acceptance still open: WhatsApp PDF send on a phone with WhatsApp (B7), logo sharpness (A3), iOS share sheet, Windows WhatsApp hand-off.
- A release build for the owner is still needed for the 2026-11-09/10 UI; only on explicit request.

## Not covered in this pass

- Admin dashboard pages behind sign-in (overview, subscribers, codes, audit history): the only test credentials are a shop owner, which the admin gate correctly refuses. Needs a platform-admin test account.
- Windows build at desktop size: access to the window was declined; the wide layout was checked on the emulator in landscape (≈914 dp, five-destination rail) instead.
- Employee and partner accounts (grants, own-operations home), staff closing-count delegation, debts, traders, analytics and weekly reports, invoice appearance and message settings, shop profile and logo upload, sign-up and password recovery.
- WhatsApp on a device with WhatsApp installed, iOS.

## Gates after the fixes (2026-11-11)

- `dart format --set-exit-if-changed lib test`: clean. `dart analyze --fatal-infos`: no issues. `flutter test`: 1,827 passed.
- `admin/`: `npm run lint` and `npx tsc -b` clean; `npm test` 209/210 under load, the one timeout (`SupportMailboxPanel.test.tsx`) passes 12/12 when rerun alone.
- SQL: hosted rolled-back runs listed under F1 and F3. `git diff --check`: clean.
- Development deployment: migrations `20261111090000` and `20261111091000` applied with `supabase db query --linked` and recorded with `migration repair --status applied`; hosted history ends at `20261111091000`.

## Verified working in this pass

Greeting and logo header, money-only tiles, «وزن مباع» / «وزن مشترى» sheets with scrap per karat and no piece counts, payment-method sheet totals, plural built-in items and «أخرى», karat orders, two-decimal entry, «سعر لكل صنف» remembered and enforced, split tenders, phone default +20 (owner country), «العميل» labels, auto-customer naming «عميل {phone}», invoice PDF (shop name, «العميل», line prices, no internal note), WhatsApp share fallback and separate «نعم، أُرسلت», pending invoices sale-only for the open day, purchase jewelry → scrap, coin «هل تريد إضافتها لمخزون الجنيهات؟» with karats 24, 21, 22, 18, 14, purchase must be fully paid, operation screen without copies panel or return button, edit and delete with net-effect review, expense delete, customer return into named stock, note edit («معدّلة») and delete, inventory zero rows and figures, customer list figures, WhatsApp-group flag, tag and filter, «المرمات» naming, repair handover unpaid and later partial collection, «تحصيل متبقي مرمة» in the feed, item-first day close with exact match, and the reset after close (only cash carried: 563,172), pending invoices empty with no open day, «الدفاتر» newest first with a read-only closed day (WhatsApp send kept), opening a new day with cash carried, scrap-to-stock with an item name and no note field, light theme on the ledger, inventory, customers and «المزيد», the wide layout with the five-destination rail, and the admin sign-in in light and dark at 375 px.
