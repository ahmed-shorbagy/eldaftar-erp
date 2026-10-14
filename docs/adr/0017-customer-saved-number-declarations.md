# Owner declarations of saved WhatsApp numbers

Status: owner-confirmed policy; implemented, independently validated and deployed to development. Native/device/owner acceptance remains open. Date: 2026-10-14.
Scope: D30, CRM-05. Decision owner: product owner, confirmed in this implementation conversation.

CRM-05 records the owner's manual declaration that a number is saved for WhatsApp. It does not verify device contacts, registration, sending or delivery. Each normalized number has its own declaration; the directory badge explicitly refers to the current primary number. Missing phones are unavailable, distinct from unknown and an explicit not-saved declaration.

Unknown is the initial and cleared state. Unchanged normalized numbers retain their declaration through name, raw-format and primary changes. Changed/new numbers start unknown. Removal retires the active number incarnation while retaining its audit. Re-adding a removed number creates a new unknown incarnation. Never transfer declarations between customers or shops. Archive/restore retains numbers and declarations. For example, formatting an existing Egyptian number does not clear saved; removing and later re-adding it does.

The existing v1 phone helper recreates rows. Add a separate stable number-incarnation relation, reconciled inside that helper in the same transaction for both old and new edits. Existing phone reads, v1/v2 RPCs, immutable receipts and CRM event types remain unchanged. Versioned v3 reads expose incarnation identity and honest declaration metadata; a separate command/status contract uses the existing durable CRM registry and locker. A dedicated append-only declaration audit avoids breaking old history decoders. No historical declaration or past actor/time is fabricated.

Writes require the current authorized owner/session/shop and active entitlement, including archived metadata. Expired owners retain authorized reads and exact completed-request reconciliation. Contact permission under [ADR 0016](0016-customer-contact-handoff.md) does not grant metadata write access. Platform admins gain no shop access. Direct client declaration/audit writes are denied. A server command checks customer version and current number incarnation/normalization, then atomically changes metadata, audit, receipt and customer revision. Actor and UTC time come from the server. No financial quantity, invoice dispatch, immutable snapshot or existing history changes.

UI uses Arabic RTL, Cairo, existing semantic tokens, isolated LTR numbers and 48-pixel controls. Each detail number has its primary marker and declaration; review states owner intent and zero financial effects. Preparing/pending/failure remain visible; success requires a matching valid backend receipt. Unknown requests keep their exact payload/key across restart and cannot clear another pending command. Revisions/reconnect refresh authoritative data and preserve stale drafts while blocking stale reviews.

Alternatives rejected: customer-wide status loses multiple-number precision; automatic verification has no evidence/provider contract; phone-row-only identity loses status on ordinary edits; normalized-number-only matching can resurrect retired declarations. Rollback of the additive migration is a local verification gate only; deployed declaration/audit data must be retained rather than destructively rolled back.

Acceptance covers all states, number lifecycle, compatibility, owner/RLS boundaries, atomic rollback/version/concurrency/idempotency, durable recovery, sync/session changes, financial/history preservation and RTL light/dark layouts. Native/device/owner acceptance remains separate from synthetic tests. [Submitted prompt](../operations/customer-saved-number-slice-prompt-2026-10-14.md).

[Independent validation](../reviews/customer-saved-number-2026-10-14/independent-validation.md), [deployment/preservation](../reviews/customer-saved-number-2026-10-14/deployment.md).
