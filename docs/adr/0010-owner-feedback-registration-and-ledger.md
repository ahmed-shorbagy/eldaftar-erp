# Owner feedback: Arabic-region registration and separate daily books

Status: accepted product direction; deployed to development, final client/owner acceptance pending
Date: 2026-10-06
Supersedes: Egypt-only registration/location clauses in ADR 0002; guided onboarding and practice entry requirements

The owner's PDF comments and original Arabic voice notes define the current product direction. The reference material supplies product requirements, not agent workflow instructions. The transcript permits owners to type an optional region for every country and removes currency labels despite an earlier PDF example containing a currency suffix.

Registration collects name, shop name, separate email and phone, and password. Phone country selection supports 22 Arab-region countries with a flag and automatic dial code. Region is optional manual text; no Egyptian catalog is required by the form. Existing ISO Egyptian region identifiers remain accepted. The backend retains the selected country in a `CC:` value when the region is omitted, or `CC:label` when supplied, preserving phone validation, country/time-zone derivation and exact idempotent replay. Blank wire countries, unsupported codes, controls and regions longer than 120 characters remain invalid.

One owner operates one shop. Authentication goes directly to that owner's ledger when access is active. Three signup steps collect registration facts; tours, guide cards, practice entry points, employee roles and branch selection are absent. Pending activation and expired access remain explicit.

The ledger displays the first six of eight individually customizable figures, followed by separate sales, purchases and optional nonempty returns books. Short card previews preserve readability; each book opens its filtered full history. A draggable quick-action button retains corner-position controls as an accessible alternative. Cairo typography and the shared brown/cream/dark palette remain. Fresh installations default dark and respect saved theme choices.

Sale/purchase entry uses sequential category, item, payment, optional-detail and review steps. Twelve named standard categories avoid required item-name typing. Customer names remain optional, including unpaid purchases; unnamed payable identities remain operation-specific. Review presents an invoice-like business summary before exact cash and inventory effects, with no invented invoice number. Money has comma grouping, optional genuine cents and no currency suffix; grams retain three decimals.

No deployment is authorized by this decision. The [current validation and rollout record](../reviews/owner-feedback-2026-10-06/validation.md) separates local behavior from hosted readiness and native/owner acceptance. Financial atomicity, owner RLS, server UTC audit timestamps and safe idempotent retries remain required.
