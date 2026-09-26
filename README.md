# ElDafttar ERP

This private monorepo contains the Flutter client in app/, the React admin starter in admin/, and connection tooling in supabase/. The source requirement DOCX/PDF files stay outside Git.

The long-term product scope, architecture, database design, roadmap, engineering practices, and decision register are indexed in [docs/README.md](docs/README.md).

Both clients provide Arabic RTL, persistent light/dark themes, and password authentication without contact verification. Flutter supports Egypt-only owner registration and email/password or Egyptian phone/password login to one Auth identity. React retains its separate platform-admin gate and has no owner signup. The reviewed registration Edge Function, nine identity migrations, Auth configuration, and rollback-only authorization tests are applied only to the owner-confirmed development project `xchapwvmvoefriqcxtvn`. Exact evidence and limits are in [Milestone 1 validation](docs/operations/milestone-1-validation.md). Local replay and staging acceptance remain pending. Onboarding, financial workflows, subscription redemption, and uploads are not operational; the ERP shell remains a prototype.

Copy app/config/local.example.json to app/config/local.json, then enter the public Supabase values. Local configuration is stored in ignored files:

- app/config/local.json, used with: flutter run -d windows --dart-define-from-file=config/local.json (from app/)
- admin/.env.local, used with: npm run dev (from admin/)

Routine validation for a code change:

- app/: scoped Dart formatting; flutter analyze; flutter test. A debug build may run when a compile or runtime check is relevant.
- admin/: npm run lint; npm test; npx tsc -b
- supabase/: meaningful SQL, RLS, and atomicity tests for the behavior that changed. npm run verify:supabase and npm run verify:r2 remain connectivity checks and do not replace those gates.

Arabic RTL visual review in both themes and at the relevant widths remains required for UI changes. Runtime visual checks may run when relevant.

Release and production builds are opt-in. Run them only when the user explicitly asks. They are never automatic routine task gates:

- app/: flutter build apk; flutter build windows; an iOS release build
- admin/: npm run build

Documentation-only changes require a link, consistency, and privacy review and git diff --check. They do not require application tests or builds. Historical validation records stay intact.

Registration server checks: from `supabase/functions/owner-register`, run `npx deno fmt --check`, `npx deno lint`, `npx deno check index.ts`, and `npx deno test --allow-env`. Local disposable database tests run with `npm run test:rls` from `supabase/`; they refuse a remote URL and roll all fixtures back. The validation record describes development execution through the connected SQL tool. Do not push the phone-confirmation field with Supabase CLI 2.118.0: it incorrectly maps that field; use the reviewed Management API setting described in the validation record.

R2 access keys must stay server-side. Use a token scoped to the eldaftar bucket in supabase/.env.local for the read-only bucket check. Do not put R2 keys in Flutter, Vite variables, or Git. Future uploads should use an authenticated Supabase Edge Function to grant short-lived R2 presigned URLs. No upload endpoint has been deployed yet.

All work follows AGENTS.md. Keep one private monorepo; publishing requires the owner's authorization.
