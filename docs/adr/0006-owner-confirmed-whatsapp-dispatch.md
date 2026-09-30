# ADR 0006: owner-confirmed WhatsApp invoice dispatch

- Status: accepted product rule; implementation pending database verification.
- Date: 2026-09-29.
- Decision owner: product owner in the 2026-09-29 conversation.
- Scope: D11, DOC-01–DOC-03, SET-04.

## Decision

The signed-in shop owner prepares an invoice from a server-confirmed sale or purchase. Opening WhatsApp or the system share sheet is a handoff attempt, not evidence that a message was sent. The invoice remains **لم يؤكد الإرسال** until the owner explicitly confirms in the app that they sent it in WhatsApp. That confirmation records the owner and a server-generated UTC timestamp in an append-only audit event. The UI labels the result **أكد المالك الإرسال عبر واتساب**; it does not claim provider delivery or recipient receipt. A failed or abandoned handoff remains pending, and a retry may reuse the same immutable invoice snapshot without changing the financial operation.

The owner is the only actor. Dispatch never changes cash, gold, piece counts, or the original confirmed transaction. A duplicate confirmation with the same idempotency key returns the original result. A new confirmation for an already confirmed invoice returns its existing status rather than writing a second sent event.

## Acceptance example

A confirmed sale receives invoice number 42. The owner opens a WhatsApp draft and returns to the app without sending; the invoice still says **لم يؤكد الإرسال**. After sending in WhatsApp, the owner taps **تأكيد الإرسال**. The backend records owner ID and UTC time. Another device reads **أكد المالك الإرسال عبر واتساب** and that time. If the request times out, retrying its key reconciles to the one event. The status does not say **تم التسليم** because no provider receipt exists.

## Implementation boundaries

The customer PDF is generated only from an immutable confirmed snapshot. The product owner accepted the server-assigned shop operation sequence as its identifier for now on 2026-09-29. Legal/tax invoice fields and a separate invoice series remain undecided, so the PDF is labeled as a confirmed operation copy. Arabic output remains RTL. The owner confirmation control is disabled during a request and displays pending, success, or failure after a server response. The dispatch command and rollback-only RLS/idempotency tests passed on the connected project; template customization remains open.
