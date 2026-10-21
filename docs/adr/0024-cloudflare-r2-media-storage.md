# ADR 0024: Cloudflare R2 is the only store for images and documents

Status: accepted by direct user instruction on 2026-10-20 ("make all images and docs use Cloudflare across the system and set this as strict rule"). Implemented locally in `supabase/migrations/20261020160000_r2_media_everywhere.sql`, the `r2-media` Edge Function and the Flutter media client. This ADR supersedes the private Supabase Storage choice for daily notes and invoice logos in ADR 0021, the architecture guide and the delivery plan. Their historical records and validation evidence remain intact.

## Rule

Every image and document in the system is stored in Cloudflare R2. This covers shop images, invoice logos, daily-note images, and any future attachment, receipt, uploaded document, export or server-kept PDF. There is no exception without a superseding ADR.

- Clients move bytes only through short-lived presigned URLs issued by the authenticated `r2-media` Edge Function. Persist object keys, never signed URLs.
- R2 credentials exist only as Edge Function secrets. They never appear in Flutter, React/Vite variables, the database or Git.
- Object keys are shop-scoped and kind-prefixed: `shop-image/<shop>/<sha256>.(jpg|png)`, `invoice-logo/<shop>/<sha256>.(jpg|png)`, `note-image/<shop>/<business-day>/<client-id>.(jpg|png|webp)`.
- After the client uploads, the function's `confirm` operation re-reads the object from R2, checks the key, size, magic bytes and SHA-256, and records it through the service-role-only RPC `record_r2_media_object_v1` into `public.r2_media_objects`. That registry is append-only and is not readable or writable by clients.
- Domain RPCs (`record_shop_image_v1`, `confirm_invoice_logo_v2`, `post_daily_note`) accept an object only when a matching registry row exists for the same shop, owner, kind and facts. Postgres stores keys and verified metadata only.
- Do not add Supabase Storage buckets, `storage.objects` insert/update policies, `bytea` or base64 media columns, or RPCs that accept media bytes. The previous inline-bytes RPCs `set_shop_image_v1` and `confirm_invoice_logo_v1` are revoked from clients, and the note and logo Storage insert policies are dropped.
- Readers of content-addressed objects verify the downloaded SHA-256 against the recorded value, because a presigned PUT does not bind content. A mismatch is shown as unverified, never as a valid logo.

## Legacy data

Rows written before this change remain readable only: inline shop-image and invoice-logo bytes in Postgres, and note images in the private `eldafttar-private-notes` bucket, which keeps its select policy. Nothing new is written there. A later, separately reviewed backfill may copy legacy objects to R2; it must not rewrite confirmed financial records.

## Adding a media kind

The first report slice adds `report_pdf` under [ADR 0025](0025-selected-financial-day-reports.md): `report-pdf/<shop>/<sha256>.pdf`, `application/pdf`, 1–20,971,520 bytes, no image dimensions. The authenticated broker checks the PDF signature/end marker and hash from a bounded R2 read. The service-only `record_report_pdf_object_v1` accepts verified metadata only; `confirm_financial_day_pdf_v1` requires that registry row and the unchanged server report fingerprint. The client verifies downloaded bytes before save/share. Function, SQL and client tests cover this kind; no legacy image path or byte RPC is extended to accept documents.

A new kind needs, before use: a key prefix and regex in the function, MIME and size limits, a registry `kind` value with matching table checks, a domain RPC that requires the registry row, function, SQL and client tests, and updates to this ADR, the architecture guide and the database design.

## Consequences

Saving media requires the deployed `r2-media` function, the four `R2_*` secrets and the migration. A client built before this change still uploads shop images to R2 but cannot record them until it is updated, because `record_shop_image_v1` now requires a registry row. Backups and restore drills must cover R2 objects together with the Postgres registry. The hosted notes harness `supabase/tests/daily_notes_pagination_hosted.sql` validated the earlier Storage contract and remains a frozen historical record.
