# ElDafttar ERP

This private monorepo contains the Flutter client in app/, the React admin starter in admin/, and connection tooling in supabase/. The source requirement DOCX/PDF files stay outside Git.

Both clients currently provide an Arabic RTL starter, light/dark theme, and public Supabase client initialization. Authentication, onboarding, ERP workflows, database schema/RLS, and file upload endpoints are next milestones; the starter does not present them as working features.

Copy app/config/local.example.json to app/config/local.json, then enter the public Supabase values. Local configuration is stored in ignored files:
- app/config/local.json, used with: flutter run -d windows --dart-define-from-file=config/local.json (from app/)
- admin/.env.local, used with: npm run dev (from admin/)

Build checks:
- app/: flutter analyze; flutter test; flutter build windows; flutter build apk
- admin/: npm run lint; npm test; npm run build
- supabase/: npm run verify:supabase; npm run verify:r2

R2 access keys must stay server-side. Use a token scoped to the eldaftar bucket in supabase/.env.local for the read-only bucket check. Do not put R2 keys in Flutter, Vite variables, or Git. Future uploads should use an authenticated Supabase Edge Function to grant short-lived R2 presigned URLs. No upload endpoint has been deployed yet.

All work follows AGENTS.md. Commit and push this entire monorepo to one private GitHub repository.

