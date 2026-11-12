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
| O1 | S1 | Stock lots (B-D14) (**Fixed**, ADR 0047 D1) | When a sale line's weight differs from the last piece of its named lot (for example an edit 10.50 g → 10.00 g, or a real sale whose weight differs from the recorded piece), `consume_fifo_named` skips that lot (it may not leave weight with zero pieces) and takes the weight from the oldest lots of other items. Observed: the edited chain sale took 8.80 g + 1.20 g from «خاتم» lots; «سلاسل 18» still shows 1 piece / 10.50 g, «خواتم 18» lost a piece. | **Decision**: when the last piece of a named lot is sold, either take the whole remaining weight (difference becomes a stock adjustment), or allow a residue, or block with a clear message. Then fix the edit path too. |
| O2 | S2 | Stock lots / grid (**Fixed**, 2026-11-12) | The test shop's pooled opening lots are named «رصيد سابق مجمّع» (`legacy_aggregate = true`, from an older backfill). B-D14's pooled-second preference and C-D4's row label only recognize «رصيد افتتاحي مجمّع», so this shop shows «رصيد سابق مجمع» in the table, never prefers the pooled lot, and offers «رصيد سابق مجمع» as a sellable item under «أخرى». Only one shop has such lots. | Treat `legacy_aggregate` lots as the pooled opening lot in `consume_fifo_named`, `get_inventory_item_grid_v1`, and the product list; hide the pooled pseudo-product from «أخرى». |
| O3 | S2 | Invoice logo (ADR 0039) (**Fixed**, ADR 0047 D5) | The shop has a logo and an active entitlement, but no invoice appearance revision exists, so invoices print the generic diamond. Automatic application runs only for a signup draft or a logo saved after 2026-11-08; logos saved before are never applied. | One-time: apply the current shop logo to invoice appearance for active shops without a revision (client on first owner workspace, or a reviewed server backfill). |
| O4 | S3 | Weight display (**Fixed**, ADR 0047 D6–D7) | The edit screen shows stored weights with three decimals («10.500») while new entry allows two; the weight sheets order karats differently (22, 21, 18, 14) from the choice lists (18, 21, 22, 14). | Align display rules with design-system.md. |

### UX and visual (owner-facing)

| # | Sev | Screen | Finding |
|---|---|---|---|
| U1 | S2 | Daily close (**Fixed**, M1) | One Back press (or swipe back) discards every count entered, with no confirmation and no saved draft. This is the owner's longest daily form. Add a discard confirmation and keep a local draft (M1 tier 5). |
| U2 | S3 | Ledger home (**Decided: keep**, ADR 0047 D9) | The ⚡ quick-actions button covers the weight column of the cards and fully hides values on some rows. Reserve bottom padding or move the default position. |
| U3 | S3 | Sale/purchase review (**Fixed**, ADR 0047 D12) | The review does not show per-line prices (when «سعر لكل صنف» is on) or the customer phone. |
| U4 | S3 | Sale/purchase form (**Fixed**, 2026-11-12) | With per-line prices, the payment amount is not prefilled with the line-price total. |
| U5 | S3 | Expense (**Fixed**, 2026-11-12) | Expense cards show only «مصروف» and the amount, not the description. The expense form puts «طرق الدفع» above the description; the expense review shows the five-step sale stepper and an empty divider block; the detail says «لا توجد بيانات عميل». |
| U6 | S3 | Trade-change review (**Fixed**, 2026-11-12) | Shows «التغير في مستحقات الشراء» on sales (and on every purchase now that purchases are fully paid). Hide when zero / not a purchase with a legacy payable. |
| U7 | S3 | Edit screen (**Fixed**, 2026-11-12) | Extra «الفئة» dropdown not on the add form; the category grid highlights the last-added category, not the line being edited; prices show «25000.00» instead of «25,000». |
| U8 | S3 | Card labels (**Fixed**, ADR 0047 D8) | «اسم البائع» on a purchase card names the staff member, but on a purchase the seller is the customer. Use «المسجِّل» or similar. |
| U9 | S3 | Operation detail (**Fixed**, 2026-11-12) | Title «بيع» appears twice (app bar and body); the body is a plain text list. |
| U10 | S3 | Payment methods sheet (**Fixed**, 2026-11-12) | Title «وسائل الدفع» repeated as the sheet title and the section title. |
| U11 | S3 | Inventory carousel (**Fixed**, 2026-11-12) | Order and snapping fixed (F7). Still open: tiles are tall with empty space below the value. |
| U12 | S3 | Repairs (status flow **Fixed**, M1; handover prefill **Fixed**, ADR 0047 D11; the rest **Fixed**, 2026-11-12) | After every status change the owner lands on a bare «تم حفظ الطلب» page and must go back and reopen the repair. Handover with «تحصيل الكل» does not prefill the amount or method (later collection does). Collection asks for the same amount twice for a single tender. Review lists weight twice («الوزن» and «الوزن المدخل»). «العيار» and «العطل» fields touch with no gap. Status changes follow M1 (toast and stay on the repair). |
| U13 | S3 | Customers (success page **Fixed**, M1; chip scroll **Fixed**, 2026-11-12) | After a status change the success page is cramped (icon and text not centered). The selected filter chip scrolls half off-screen. The success page is replaced under M1. |
| U14 | S3 | Daily notes (**Fixed**, 2026-11-12) | The edit sheet has no title. A previous unsent draft image appears preloaded on entry. |
| U15 | S3 | Day close (**Fixed**, 2026-11-12) | Pressing Done moves focus to the next cell, which is easy to mistype into (owner should see where the cursor is). Tapping outside a count cell does not close the keyboard. |
| U16 | S3 | Ledger after close (**Fixed**, M1) | «إضافة بيع» / «إضافة شراء» stay styled as active while no day is open; tapping shows «يوم العمل مغلق…». Disable them or replace with «فتح يوم جديد» (M1 day-closed banner). |
| U17 | S3 | Ledger header after close (**Fixed**, M1) | The header still reads «يوم العمل 30 سبتمبر 2026» after that day is closed. Show «لا يوجد يوم مفتوح» or the last closed date as such. |
| U18 | S3 | «الدفاتر» list (**Fixed**, 2026-11-12) | Each closed day shows only «مقفول · فُتح 14:19»; the close time is not shown. |
| U19 | S3 | Admin sign-in (**Fixed**, ADR 0047 D3) | A valid shop-owner account gets «تعذر تسجيل الدخول. تحقق من البيانات» (reads as wrong password). **Decision**: keep generic (no account enumeration) or say the account has no admin access. |
| U20 | S3 | Scrap-to-stock (**Fixed**, ADR 0047 D10) | Returns straight to the ledger with a snackbar, unlike sale/purchase which show a success page; weight there accepts three decimals while sale/purchase accept two. Align (M1 outcome screen). |

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

#### M1 progress (2026-11-11)

First milestone (commit `583fa75`):

- `app/lib/src/theme/message_tone.dart` (tones, colour roles, icons, Arabic screen-reader labels), `app_messages.dart` (`AppMessages` toast messenger and `AppToast`), `app_banner.dart` (`AppBanner`), `feedback_copy.dart` (shared copy). The design guide's «Feedback and messaging — 2026-11-11» section describes them.
- Every raw snack-bar call is migrated (the 32 `SnackBar`/`ScaffoldMessenger` matches in 8 files). Ledger trades no longer add a toast on top of their own outcome page. Day close, cash transfer and scrap-to-stock show «تم إقفال يوم العمل», «تم تحويل النقدية» and «تمت إضافة الكسر إلى المخزون». The day-closed or loading block on «إضافة بيع/شراء» shows a warning or info toast. The trade-change failure shows only its in-form error banner (it used to appear twice). Notes get specific success and error toasts, and the unknown-outcome toast keeps its retry. Device-preference failures and debt-reminder taps show info or warning toasts, and signup and logo outcomes show warning or success toasts.
- `_PendingNotice`, `_RefreshFailedNotice`, `InventoryNotice` (now success/info/warning/error by command state) and `_InlineNotice` render through `AppBanner` with their existing keys.
- Sign-out clears every visible and queued toast.
- `test/app_messages_test.dart` (18 tests): the source guard against raw snack bars, durations, auto-dismiss, pause on press, close and action, no auto-dismiss under a screen reader, merge, replace, queue, clear, survival across a route pop, position above the bottom bar and in the wide start corner, every tone at 200 % text in light and dark (this caught an overflow, now fixed by stacking the action), banner tone/action/spinner, and 4.5:1 text contrast for every tone in both themes.

Second milestone (working tree, not committed):

- **U16/U17, closed day:** «إضافة بيع» / «إضافة شراء» are disabled while no day is open. The header reads «لا يوجد يوم مفتوح · آخر يوم مقفول …». When the day-reset card is not shown, a warning banner «يوم العمل مغلق» offers «فتح يوم جديد». The toast that appeared after tapping is gone.
- **Outcome screen:** `theme/app_outcome.dart` (`AppOutcome`, `OutcomeFigure`) has a tinted tone icon, a specific title, the server-confirmed subtitle and a figures card. The trade sheet shows «تم حفظ البيع / الشراء / المصروف / بيع الكسر / المرتجع» with the total and each item's weight. The debt page shows «تم حفظ طلب الديون» with its status and effects.
- **U12, repairs:** the bare «تم حفظ الطلب» page is removed. Status, handover, collection and return show a specific toast and reopen the repair. Intake and archive show a toast and return to the list.
- **U13, customers:** the success page is removed. Every customer command shows a specific toast (`customerSavedCopy`) and opens the customer's file.
- **Shared confirm dialog:** `theme/app_confirm.dart` (`showAppConfirm`). It has a question title, a consequence message, the safe button autofocused, an error-coloured action for destructive choices, and Back always returns false. It is used for opening a day, deleting a note, changing repair status, revoking staff and closing-staff requests. The remaining `AlertDialog`s are tools rather than decisions (invoice preview and zoom, PDF share, WhatsApp hand-off, subscription code, inventory price, note editor), so they stay as they are.
- **U1, day close:** typed counts, including grid cells and added items, are kept as a device-local draft keyed to user, shop, day and day version (`CloseCountDrafts`, `SharedPreferencesCloseCountDrafts`). Back with counts asks «الخروج من التقفيل؟» with «خروج», which keeps the draft, or «متابعة العدّ». Reopening restores the draft under the banner «استُعيدت مسودة العدّ من هذا الجهاز» with «مسح المسودة». A successful close or correction clears the draft. Errors on this screen are banners.
- **Failure mapping:** `theme/failure_feedback.dart` maps gateway codes to `FailureKind`: offline, unknown outcome, rejected, access lost, read-only, stale, device storage and unexpected. Each kind gets a tone, generic Arabic copy and its action. Repair notices, operation edit/delete errors and inventory command banners take their tone from it. A feature's own reason text stays the title.
- **Accessibility:** error and warning toasts also send an assertive screen-reader announcement.
- **Notes:** «تم حفظ الملاحظة» is now a toast, so it no longer lingers after the note is deleted. Pending and draft states are banners, and a rejection shows once, as an error banner.
- **Admin:** MUI `Alert` (the dashboard's inline banner) gets the same tint, border, radius and 600-weight treatment through `MuiAlert` theme overrides. `palette.info` uses the brand accent instead of MUI blue. The dashboard has no snack bars.
- **Tests:** `failure_feedback_test.dart` (code mapping, Arabic-only copy, confirm dialog defaults in both themes, outcome at 170 % text), `daily_close_draft_test.dart` (5 tests: leave without counts, ask with counts, «خروج» keeps and restores, clear draft, other day version ignored), an assertive-announcement test in `app_messages_test.dart`, and an admin theme test. Repair, customer, notes and collect tests now expect the toasts.
- **Emulator (dark, 1080×2400, development):** the discard dialog appeared on Back with counts, the draft survived an app restart and came back under its banner, and «مسح المسودة» cleared it.

Remaining limits (not code work in this repository):

- TalkBack, light theme and the wide layout were not checked on a device for these screens. Automated tests cover both themes, 200 % text and wide placement.
- Admin pages behind sign-in still need a platform-admin test account for a visual check (see «Not covered in this pass»).

### Questions for the owner (answered 2026-11-11, [ADR 0047](../adr/0047-owner-answers-2026-11-11.md))

All twelve questions were answered and implemented:

- **O1:** take the whole recorded weight, book the difference as a stock correction, and tell the owner in the sale review. Migration `20261111100000_last_piece_weight_rule.sql` was deployed to development and recorded in the hosted history. An edit or delete restores the recorded weight.
- **M1 split:** keep it as it is.
- **U19:** say plainly that the account has no admin access. Other sign-in failures also name their cause.
- **Help page:** «المساعدة» stays (HELP-01, ADR 0031). Guides, tours and help cards stay removed, as requested on 2026-10-05.
- **O3:** apply the existing shop logo once, only where no invoice appearance was ever saved.
- **O4:** karats in the order 18، 21، 22، 14. The edit screen shows two decimals, keeping a real third decimal, and prices are grouped.
- **U8:** «المسجِّل» on purchases and other non-sale entries.
- **U2:** keep the ⚡ position.
- **U20:** result page, and two-decimal weight.
- **U12:** «تحصيل الكل» fills the payment line with the final fee.
- **U3:** the review shows line prices and the customer phone.

Every finding in this record is now fixed or decided (see «Follow-up fixes» below).

### Follow-up fixes (2026-11-12, working tree, not committed)

- **O2, legacy pooled lots:** migration `20261112090000_legacy_pooled_lot_name.sql` maps «رصيد سابق مجمّع» to «رصيد افتتاحي مجمّع» in `private.canonical_jewelry_name`, so the item grid shows one pooled row. `private.consume_fifo_named` takes a `legacy_aggregate` or pooled lot second (after the named item, before other items). In Flutter, `canonicalJewelryName` maps the same alias, and `isPooledOpeningItem` keeps the pooled pseudo-item out of «أخرى» in sale/purchase, scrap-to-stock and day close. Tests: `supabase/tests/legacy_pooled_lot_name.sql`, and «the legacy pooled name joins the pooled opening row (O2)» in `inventory_item_grid_test.dart`.
- **U4, payment from line prices:** with «سعر لكل صنف» on and one payment line, the amount follows the line-price total (grouped, for example «8,000»). It updates as prices change or a line is removed, and stops once the owner types a different amount. Turning line pricing off clears only an amount the app filled in. Tests: two U4 cases in `line_pricing_test.dart`.
- **U5, expenses:** migration `20261112091000_expense_feed_description.sql` adds the expense description (one line, at most 200 characters) to `item_summary` in the current-app home, date and operation-page reads. It uses an existing key, so installed builds still parse the feed, and the 361ad2e reads are unchanged. Cards show «الوصف: …» under the title. The form asks for the description before «طرق الدفع». The review has no five-step stepper and no empty divider, and it shows the description. The operation detail and the trade-change review show the description and no longer say «لا توجد بيانات عميل». Tests: `supabase/tests/expense_feed_description.sql`, plus additions to `ledger_journal_table_test.dart`, `batch2_trade_form_test.dart` and `ledger_trade_change_test.dart`.
- **U12, the rest of repairs:** with one payment method, collection and handover ask for the amount once («المبلغ المحصّل» or the final fee) and the method row has no amount field. With two or more methods, each has its own amount. The intake review shows the weight once. «العيار» has the same 8 px gap as the other fields. The collection review used to parse the grouped amount («1,500») as typed, which rejected any collection of 1,000 or more. It now uses `cashInputValue`, like every other cash field. Tests: «U12: a grouped amount over 1,000 is entered once and splits» in `repair_collect_test.dart`, plus weight-once and field-gap checks in `repair_capture_test.dart`. The existing repair tests now enter the amount once.
- **U18, close time:** migration `20261112092000_report_days_closed_at.sql` adds `closed_at_shop` (in the shop's zone) to `list_financial_report_days_v1`. Older builds ignore the key. «الدفاتر» shows «مقفول · فُتح 09:30 · أُقفل 17:45». A close after midnight also shows its date, and a server without the key shows the opening time only. Tests: `supabase/tests/report_days_closed_at.sql`, the U18 codec test in `report_test.dart`, and `ledger_archive_test.dart`.

- **U6, trade-change review:** «التغير في مستحقات الشراء» shows only when the change is not zero, which happens only for a purchase with a legacy payable. It no longer shows on sales or on fully paid purchases. Test: `ledger_trade_change_test.dart`.
- **U7, edit screen:** stored lines open like the add form, with no extra «الفئة» dropdown. The category grid shows and edits the line the owner last touched, which starts as the first line, and outlines it when there are several lines. Amounts are grouped («25,000»). Tests: the U7 case in `line_pricing_test.dart`. `purchase_to_scrap_test.dart` now checks the kept category without the dropdown.
- **U9, operation detail:** the title appears only in the app bar. The number, recorder, time and customer (or expense description) are icon rows in one card, with the copy unchanged. Test: `financial_operation_dispatch_test.dart`.
- **U10, payment sheet:** `LedgerCashBreakdown`, `LedgerTradeWeightBreakdown` and `LedgerGoldBreakdown` take `showTitle`. The sheets that already carry the title pass `false`, so «وسائل الدفع», «وزن مباع / مشترى» and «المخزون والكسر» each appear once. Test: `confirmed_ledger_dashboard_test.dart`.
- **U11, carousel tiles:** the compact tile measures 94 px at 100 % text, 116 px at 130 % and 166 px at 200 %. The slot is now `scale(100).clamp(100, 184)` instead of 148–196 px, so the empty band under the value is gone. Test: «U11: figure tiles fit their slot» at 1× and 2× in `inventory_item_grid_test.dart`.
- **U13, customer filters:** choosing a chip scrolls it to the centre of the row, so it is never left half off-screen. Test: `customer_widget_test.dart`, at 320 px.
- **U14, notes:** the edit sheet and dialog are titled «تعديل الملاحظة». If a draft on this device was never received by the server and belongs to an earlier day, it is removed on entry, both its text and its image. The info toast «حُذفت مسودة لم تُرسل من يوم سابق» says so. Such a draft could no longer be sent. A same-day draft, or one whose outcome is uncertain, is still restored and frozen as before. Tests: `daily_notes_widget_test.dart`.
- **U15, day close:** on Android the number pad's ✓ used to move focus to the next count cell. Now every count cell and every cash, stock and scrap field closes the keyboard on ✓, and tapping outside a field also closes it. Test: `closing_count_cell_test.dart`.

Gates (2026-11-12): `dart format --set-exit-if-changed lib test` clean; `dart analyze --fatal-infos` no issues; `flutter test` 1,877 passed. The three migrations and tests ran first together in one rolled-back transaction on development. Then they were applied with `supabase db query --linked` and recorded with `migration repair --status applied`. Hosted history now ends at `20261112092000`. Hosted rolled-back runs passed: `legacy_pooled_lot_name`, `expense_feed_description`, `report_days_closed_at`, `last_piece_weight_rule`, `sale_named_item_and_day_read`, `expense_return_change`, `financial_day_report`, `financial_week_report`, `jewelry_item_names`, `daily_ledger_trades`, `milestone_3_inventory`, `shop_staff_grants`, `ledger_home_day_reset`, `batch_c_review_fixes` and `legacy_read_shapes`. `ledger_date_read` runs only on a local disposable database, which this machine does not have, so it was not run. No admin code changed, so React gates were not needed. Second batch (U6–U15) gates: format clean, analyze no issues, `flutter test` 1,884 passed. That batch has no server change. These fixes were not reviewed on the emulator. Widget tests cover the changed screens in Arabic RTL, and the repair captures cover light and dark at 320, 390 and 1440 px.

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
