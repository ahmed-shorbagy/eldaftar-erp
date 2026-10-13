# Ledger UI refinement — 2026-10-13

## Reference and changes

Reviewed the owner's final Daily Ledger V2 comments, all four embedded references and the screenshots supplied with this request. Source documents and extracted images remain private local inputs. The ui-ux-pro-max skill informed hierarchy, responsive tables, touch targets and text scaling; the existing design guide and palette remain authoritative.

- Quick Actions previously displayed expense first and hid the rest in a second disclosure. All available supported operations now appear directly in a responsive grid, followed by invoice/day controls. Only button-position preferences remain disclosed. The sheet has a persistent Arabic title/close control, safe-area padding, one scroll area and a 720-pixel width limit. Capability, entitlement, pending-command and day-state gates remain unchanged.
- Journals separate title/history and add/details controls above the table. Confirmed operations group total, weight/payment, structured items and recording owner. Rounded gold boundaries, quieter rules, roomier cells and numeric column widths keep Arabic headings readable at 320 pixels. Units appear in the weight header; numbers stay LTR. Two initial rows, Show More, optional customer/date, failed-read retry and stale-read protection remain.
- Summary cards use matching Flutter/React muted gold-frame tokens in both themes. This is the user's current refinement request; the owner's written V2 comment specifically names table boundaries. The approved palette remains unchanged. Header/navigation sizes accommodate enlarged text, and floating-button placement accounts for navigation height.
- The audit found that normal sale/purchase entry still exposed price/workmanship controls contrary to the final document. Those controls are removed. Exact payment, purchase consideration, measured weight, effect review and backend confirmation remain. Historical invoices, pricing domain contracts and specialized exchange entry retain their existing behavior.

## Final document audit

| Request | Result |
| --- | --- |
| Gold table boundaries and less crowding | Refined table frames, grouped metadata, separate journal headers and direct action grid. |
| Compact top statistics; configurable five/six | Existing pinned horizontal strip and saved per-shop selection/order retained. |
| Stock/scrap figures | Confirmed balances and separate breakdowns retained; no invented data. |
| Two-decimal gold and full comma-grouped money | Integer display formatting and cash-input grouping retained; measured/stored weights remain exact. Review adds exact milligrams when needed. |
| Sale/purchase above tables and outside Quick Actions | Journal entry controls retained above tables; absent from the action sheet. |
| Required Quick Actions | Available supported operations immediately visible; returns still select an original confirmed operation. |
| Journal separation and horizontal items | Existing 24-pixel separation, two initial items and Show More retained. |
| Optional customer/date and oldest/newest order | Details disclosure and server-sequence/UTC ordering retained. |
| Compact slide-up sale/purchase | Existing 84%-height, 720-pixel keyboard-aware sheet retained. |
| Category icons, Other/catalog/Instant Inventory and editable weights | Existing vector choices, catalog pagination/manual entry, inventory access, owner suggestions and catalog overrides retained. Measured quantities govern posting. |
| Remove price/workmanship detail | Removed from normal sale/purchase entry; exact payment/payload tests cover both kinds. |
| Invoice action after confirmation | Existing supported owner-confirmed dispatch retained. |
| Theme toggle, logout in More and no Home/Start | Direct ledger navigation and persisted theme behavior retained. |
| Remove ledger profile images; allow notes | No ledger profile uploader; separate note images remain available. |

## Validation

- Scoped Dart formatting completed; **615 Flutter tests passed**.
- Eight Arabic RTL capture scenarios passed: both themes at 320/390/1440 logical pixels, plus 320 at 1.6 text scale. Populated ledger, journals, details and Quick Actions were visually reviewed. Existing sale/purchase captures cover entry, keyboard, effect review, confirmed success and enlarged-text unknown states.
- Direct `dart analyze`: no issues. `flutter analyze --no-pub` was attempted, but the installed SDK launcher fails to start its analysis server; direct analysis is the substitute.
- React lint, **38 tests** and `npx tsc -b`: passed. React only adds matching frame tokens; no administration layout changed.
- Notes and owner-review tests now use directly visible actions. Two stale assertions from the previous formatting follow-up expect two-decimal gold; scrap-conversion review also checks exact milligrams and the unchanged payload.
- Documentation links, consistency/privacy and `git diff --check` reviewed. Historical validation records remain intact.

Synthetic captures/logs are ignored local files under `app/build/ui-refinement/`, `app/build/batch2/` and existing capture directories. No source documents or private shop/customer data are included.

## Limits

These are widget captures, not fresh native-device acceptance. The five-second completion target is not measured; input and network latency affect it. No SQL/RLS/server contract changed, so SQL gates were not rerun for this presentation follow-up. No hosted data changed. No release/production build, commit, push or deployment was performed.
