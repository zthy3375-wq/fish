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
- Maintain Android only; do not reintroduce retired classroom queries or other native platforms. Android test signatures are not production release signatures.

## Repository hygiene

Keep mock data under tests/fixtures. Do not add generated dist/assets, APKs, SDK paths, IDE output or signing keys to git. Keep dependencies lean; use existing tooling for simple tasks. Update current docs when behavior changes; retain meaningful historical evidence rather than rewriting it as a current claim.

Repository review does not authorize deletion. Before deleting remote branches, tracked files or historical artifacts, present the exact candidates and reasons and obtain the owner's explicit confirmation. Preserve unmerged fixes and paused experiments until their disposition is confirmed.

## Release authorization

New versions are test-only by default. Building, delivering an APK, or passing tests does not authorize publishing. Only an explicit owner instruction to push the new version to users authorizes Pgyer publication or changing live Tencent update metadata. Never trigger deployment workflows as a side effect of test work.

When the owner explicitly requests a push, default to a mandatory update unless they specify optional. This does not authorize publishing before an explicit push request.

For future Pgyer releases, use exactly `修复了一些问题` as the public update description unless the owner explicitly requests different wording. Keep detailed technical changes in repository records.
