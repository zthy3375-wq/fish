# Flutter core verification scope

The owner's current request explicitly adds Android and iOS in this independent directory. This overrides the root guide's Android-only scope **only here**. Keep the original Vue/Capacitor production project and all production release/update configuration unchanged.

- Native Android WebView / iOS WKWebView own school authentication and session storage. Never return credentials or cookies over Flutter channels.
- Flutter owns whitelisted timetable data, scoped encrypted offline storage, and UI.
- Only migrate school connection and timetable. No other module or backend.
- Test with synthetic fixtures only. No passwords, tokens, raw authenticated pages or personal school records in repository, logs, screenshots or CI.
- Run `flutter analyze`, `flutter test`, `flutter build apk --debug`; run iOS simulator build on macOS. Run `node --test flutter_app/test_js/adapter.test.mjs` from repository root after `npm ci` for the compiled school adapters.
- Tests/builds do not prove real login, CAPTCHA, session renewal or device compatibility. Keep these evidence categories separate.
- No merge, production signing, distribution upload, deployment, release or update-channel change is authorized for this phase.
