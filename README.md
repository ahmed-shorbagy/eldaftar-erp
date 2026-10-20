# ElDafttar ERP

This private monorepo contains the Flutter client in app/, the React admin starter in admin/, and connection tooling in supabase/. The source requirement DOCX/PDF files stay outside Git.

The long-term product scope, architecture, database design, roadmap, engineering practices, and decision register are indexed in [docs/README.md](docs/README.md).

Both clients provide Arabic RTL, persistent light/dark themes, and password authentication without contact verification. Flutter supports Egypt-only owner registration and email/password or Egyptian phone/password login to one Auth identity. React retains its separate platform-admin gate and has no owner signup. The reviewed registration Edge Function, nine identity migrations, Auth configuration, and rollback-only authorization tests are applied only to the owner-confirmed development project `xchapwvmvoefriqcxtvn`. Exact evidence and limits are in [Milestone 1 validation](docs/operations/milestone-1-validation.md). Local replay and staging acceptance remain pending. Onboarding, financial workflows, subscription redemption, and uploads are not operational; the ERP shell remains a prototype.

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
