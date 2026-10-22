# ElDafttar ERP

This private monorepo contains the Flutter client in app/, the React administration client in admin/, and connection tooling in supabase/. The source requirement DOCX/PDF files stay outside Git.

The long-term product scope, architecture, database design, roadmap, engineering practices, and decision register are indexed in [docs/README.md](docs/README.md).

Both clients provide Arabic RTL, persistent light/dark themes, and password authentication without contact verification. Flutter supports owner registration with Egypt catalog or required international location and email/phone password login; React retains its separate platform-admin gate and has no owner signup. Financial ledger, inventory, connected shop workflows and verified R2 media now have bounded implementation/development evidence; tours and practice entry points were removed. The [requirements matrix](docs/requirements-matrix.md) tracks the scope and acceptance limits. Temporary staff access is limited to assigned physical closing counts; the owner alone confirms the financial close.

Current plan — 2026-10-22: the bounded ADM-01 subscriber directory is independently verified and deployed to development. [Review and exact checks](docs/reviews/admin-subscribers-2026-10-22/independent-validation.md), [deployment/preservation](docs/reviews/admin-subscribers-2026-10-22/deployment.md), [ADR 0027](docs/adr/0027-admin-subscriber-directory.md). The React client source remains local; owner acceptance and Milestones 4/5 stay open. Daily/weekly Reports retain their historical evidence. Next proposed feature: admin subscription-code issuance/management using the existing owner redemption contract, scoped separately in the [task pointer](docs/operations/next-slice-prompt.md).

Public client configuration is generated from `supabase/.env.local`. The generator copies only `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` into ignored `app/config/local.json` and `admin/.env.local`. Storage keys in that env file stay there and are not written into Flutter or Vite.

From the repository root:

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 apk
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 windows
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 ios
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build.ps1 admin
```

`sync` refreshes the two ignored files without building. Visual Studio Code launches run that step first. `app/config/local.example.json` shows the Flutter file shape; it is not filled in by hand.

Routine validation for a code change:

- app/: scoped Dart formatting; flutter analyze; flutter test. A debug build may run when a compile or runtime check is relevant.
- admin/: npm run lint; npm test; npx tsc -b
- supabase/: meaningful SQL, RLS, and atomicity tests for the behavior that changed. npm run verify:supabase and npm run verify:r2 remain connectivity checks and do not replace those gates.

Arabic RTL visual review in both themes and at the relevant widths remains required for UI changes. Runtime visual checks may run when relevant.

Release and production builds are opt-in. Run them only when the user explicitly asks. They are never automatic routine task gates:

- app/: `scripts/build.ps1 apk`, `scripts/build.ps1 windows`, or `scripts/build.ps1 ios`
- admin/: `scripts/build.ps1 admin`

Documentation-only changes require a link, consistency, and privacy review and git diff --check. They do not require application tests or builds. Historical validation records stay intact.

Registration server checks: from `supabase/functions/owner-register`, run `npx deno fmt --check`, `npx deno lint`, `npx deno check index.ts`, and `npx deno test --allow-env`. Local disposable database tests run with `npm run test:rls` from `supabase/`; they refuse a remote URL and roll all fixtures back. The validation record describes development execution through the connected SQL tool. Do not push the phone-confirmation field with Supabase CLI 2.118.0: it incorrectly maps that field; use the reviewed Management API setting described in the validation record.

All images and documents are stored only in Cloudflare R2 ([ADR 0024](docs/adr/0024-cloudflare-r2-media-storage.md)). The authenticated `r2-media` Edge Function issues short-lived presigned upload and read URLs, then verifies each uploaded object into `public.r2_media_objects`. Postgres keeps only object keys and verified metadata. Do not add Supabase Storage buckets or inline media bytes. R2 access keys stay server-side as the `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, and `R2_BUCKET` function secrets. A token scoped to the eldaftar bucket in supabase/.env.local is used only for the read-only bucket check. Do not put R2 keys in Flutter, Vite variables, or Git. From `supabase/functions/r2-media`, run `npx deno fmt --check`, `npx deno lint`, `npx deno check index.ts`, and `npx deno test --allow-env`.

All work follows AGENTS.md. Keep one private monorepo; publishing requires the owner's authorization.
