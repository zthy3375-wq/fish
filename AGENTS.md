# Development guide

## Start here

Read README.md and docs/STATUS.md. main is the integration baseline. Use a short-lived feature/fix/chore branch and a small PR; do not resurrect closed research or diagnostic branches. Respect the user's current authorization for merges and cleanup. Do not deploy a website or publish a store build unless requested.

## Commands

- `npm ci`: reproducible install with the committed lockfile.
- `npm run check`: current unit tests, TypeScript and production build.
- `npm run test:watch`: focused feedback during development.
- `npm run android:check`: build + Capacitor sync + native debug/release tests. Requires a full JDK 21 and SDK 35.
- `npm run android:apk`: build + sync + native debug tests + installable debug APK.
- `npm run test:ui`: synthetic-native UI regression. Install Playwright Chromium first; this does not authenticate to the school.

Run checks appropriate to the change. For native/session changes also validate Android compilation. Never substitute test counts or synthetic responses for school-account/device evidence. Keep untested behavior explicit.

## Boundaries

- Vue displays data; the Kotlin HandanAcademicClient owns school authentication/session material.
- School passwords are entered in the official page. Never commit credentials, raw authenticated HTML, cookies, tokens or personal logs.
- The Index presentation route and JSON query route are different. Use the verified school script contract, not a guessed family-wide endpoint.
- `handan-academic.js` handles requests/normalization; `handan-rendered-reader.js` is the compiled fallback page reader. If HTML shapes change, check both readers and the current adapter regression fixture.
- Keep school caches independent from personal schedules. Preserve storage keys, legacy `school-page-` recognition and backup compatibility.
- Empty/error/partial responses must not wipe previously successful data. Logout/account changes must not reuse another account's snapshot.
- Preserve the compact mobile layout and existing light theme. Do not add developer diagnostics or manual school import to the normal user flow.
- iOS project presence is not iOS school-session support. Android test signatures are not production release signatures.

## Repository hygiene

Keep mock data under tests/fixtures. Do not add generated dist/assets, APKs, SDK paths, IDE output or signing keys to git. Keep dependencies lean; use existing tooling for simple tasks. Update current docs when behavior changes; retain meaningful historical evidence rather than rewriting it as a current claim.
