# ADR 0023: meeting corrections, calendar journal and temporary closing counts

Current October 21 status: the open-financial-day override below supersedes the original automatic calendar-journal decision. Branded handoff now offers a tall PNG image and A4 PDF from the same edition, with cream/gold or dark/gold output and explicit verified shop-image logo opt-in. [Current validation](../reviews/stabilization-2026-10-21/validation.md), [development reconciliation](../reviews/stabilization-2026-10-21/development-reconciliation.md), [device/owner acceptance](../reviews/stabilization-2026-10-21/acceptance.md). The original dated rationale and deployment checkpoints remain historical.

Subsequent status: the user authorized applying the reviewed Supabase changes and established routine deployment/verification for completed Supabase work on the existing development project. [Deployment and hosted verification](../reviews/owner-meeting-2026-10-18/deployment-2026-10-20.md) are complete. Earlier local-only delivery statements below describe the prior checkpoint.

Status: directly authorized in the 2026-10-20 chat, implemented locally. Deployment and native owner acceptance are separate. [Timestamped request register](../reviews/owner-meeting-2026-10-18/audit.md), [validation](../reviews/owner-meeting-2026-10-18/validation.md).

The local 2026-10-18 recording is a product reference. The user explicitly resolved three conflicts: PDF sharing replaces the later text-only WhatsApp action; the main journal changes automatically with the shop's server-derived calendar date; and temporary employee physical counts are permitted. These decisions supersede the conflicting parts of ADRs 0003, 0021 and 0022. Their historical records remain intact.

## Calendar and financial day

`get_daily_ledger_home_v1` returns read model v3. Exact return/note counters cover all records, independently of pagination. Current cash, stock, scrap and the explicitly open financial day remain authoritative financial state.

**2026-10-21 owner override:** while a financial day is open, the home journal and daily figures stay on that open day. Calendar midnight refreshes server timing only; it does not empty the main ledger, open a new financial day, or block sale/purchase/expense entry. The owner alone closes the open day, then opens the next. When no financial day is open, the home journal uses the shop calendar date. Historical date selection remains available. Notes can paginate across all sessions of a selected calendar date.

The response supplies server UTC `server_now` and `next_midnight_at`, calculated with the shop's time zone. Flutter schedules the interval and refreshes on resume and normal sync. It never decides a date from the device clock. There is no automatic financial close or balance reset.

## Named physical observations

Closing count v2 stores named stock rows with category, karat, required integer piece count and optional exact milligrams. An unmeasured weight remains JSON null. The server separately records book quantities; it never fills a blank physical weight with the book weight. Counts must match each book bucket. Measured subtotals cannot exceed the book; if every row is weighed, the exact weight must match. Scrap weights and owner cash counts remain required. Differences block closing for owner reconciliation.

The close remains atomic, shop/day locked, version checked and idempotent. It records UTC audit events without moving cash or gold.

## Temporary staff scope

There is still exactly one owner per shop and one shop per owner. Staff identities are separate Supabase Auth phone/password accounts, outside `shop_memberships`. The owner creates them from «المزيد ← فريق عد التقفيل»; no invitation or message is sent. There is no general employee role, shop membership or arbitrary permission grant.

The authenticated Edge Function verifies the caller through Auth, reserves one stable user ID with an owner-authorized RPC, creates only that Auth identity using server credentials, then finalizes the binding through a service-only RPC. A private PBKDF2 retry verifier permits unknown-outcome recovery without storing plaintext passwords in a client queue or database command. The client persists creation metadata and key only, and asks for the original password again when creation must resume.

An assignment lasts four hours, belongs to one financial day/version and replaces the prior assignment. Backend reads expose only shop/staff name, business date, expiry, category/karat form structure and scrap karats. They exclude expected counts/weights, cash, ledger history, customer/invoice/repair/debt data and other shop records. Existing owner RLS still denies all general shop reads and writes to staff.

An employee submits actual named counts and scrap weights. The server validates syntax and allowed buckets without revealing whether they match expected balances. Submission, expiry, revocation, account disablement, owner/shop access loss or a stale day ends task access. A retry may read only its narrow completion receipt. Staff cannot financially close. The owner separately sees the immutable submitted observations, enters cash, reviews discrepancies and explicitly confirms. Audits link submitting employee, confirming owner, financial close and server UTC timestamps.

Staff creation/submission metadata uses its own protected durable queue. Financial closing uses the existing protected financial command locker. Unknown outcomes keep the original key and envelope. Ordinary users have no direct table grants on the new staff/task/audit records; narrow security-definer RPCs enforce identity, shop, task state and expiry.

## Invoice handoff and appearance

Confirmed sale success and operation details open PDF sharing directly. The current branded edition is preferred; when absent, the owner creates one confirmed immutable edition with the existing durable presentation flow. Stale content, an unverified required logo or an unresolved request blocks branded sharing. An explicit Arabic fallback offers the original document if branded preparation fails. A share sheet is only a handoff: the owner chooses WhatsApp and the displayed customer, then separately attests to actual sending. There is no delivery claim or automatic external send.

New editions use renderer v2: white light paper (`header` / `compact`) or explicit dark/gold (`dark`). Stored renderer-v1 editions retain their appearance. Device theme does not silently change a saved document. Text-only handoff and its More settings entry are removed; historical message revisions/recovery are preserved.

Signup may explicitly select the shop image as an invoice-logo draft as well. The default is unchecked. The normalized draft is saved locally under the new owner/shop, remains visible as pending in More, and resumes from stored bytes after activation. Upload verification and reviewed appearance save establish when it appears in invoices. The shop avatar is never silently reused as a logo. Settings retain independent logo selection/removal.

## Delivery boundary

Apply the four new meeting migrations in order, deploy `closing-staff-create` with its pinned `deno.json` and server-only Auth credentials, and then validate the target environment before exposing the updated client there. This chat did not authorize hosted application or publishing. The local SQL runner uses only its dedicated loopback test database and includes migration rollback, RLS/task boundaries, atomicity, idempotency and a two-connection close retry race. Native camera/share-sheet behavior and exact resemblance to the unavailable full old app remain owner/device acceptance, not inferred test results.
