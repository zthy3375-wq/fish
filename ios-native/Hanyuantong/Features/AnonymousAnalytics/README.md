# Native anonymous analytics: implemented, production-gated

## Current build

The settings page and opt-in state machine are available for integration. Production analytics is **disabled** by `AnalyticsBuild.current.rolloutReviewed = false`, independent of saved consent. The current app's real `CFBundleVersion=1` also fails the unchanged server's `versionCode >= 102` rule. Do not increase or impersonate the Android version to bypass it. No live metrics requests were made during this work. This is not completed live-service parity.

`cloudbase/functions/analytics/core.mjs` accepts only `id, day, version, versionCode, features` for record and only `id` for enroll/delete. The endpoint and `X-Hyt-Token` header match Android's current `AnalyticsContract`; older `docs/ANALYTICS.md` D1/Bearer descriptions are historical, not this wire contract. There is no platform column: an extra `platform: "ios"` is rejected. The request User-Agent always truthfully identifies iOS. Current aggregation cannot separately label Android/iOS, and has not been modified.

`cloudbase/schema.sql` deletes rows but does not retain a revocation tombstone. An uncertain, delayed enrollment could recreate a deleted row. The client serializes normal enrollment/record/deletion, persists an in-flight marker before enrollment, and never announces confirmed erasure after an ambiguous enrollment. It retains encrypted credentials and a pending/off state for deletion retry without re-enrolling. This unresolved server guarantee is another reason not to enable production collection just because a future build passes validation. Resolving it requires a separately approved server change and compatibility review.

## Integration

- Own one `@StateObject private var analytics = AnonymousAnalyticsStore()` at app scope and pass it to `AnonymousAnalyticsSettingsView(store: analytics)` from “我的 → 匿名使用统计” and/or Privacy.
- A foreground `analytics.flush()` retries existing consent/deletion only; a fresh installation performs no writes, ID creation, events or network activity.
- If event hooks are added, call only `recordFeature(AnalyticsFeature)` at the same actual feature-entry actions as Android. Never pass accounts, school records, URLs, order IDs, amounts, free-form strings or untrusted web values. Counts mean entry, not completion/payment.
- `setEnabled(false)` stops new collection synchronously. Existing requests may finish but cannot trigger a following record. `deleteData()` requires the view's confirmation dialog and persists the deletion intent first.
- Do not call `cancelSending()` merely when the settings page closes. Off/delete must retain their serial completion path. The method handles genuine cancellation/teardown and cannot retract server-accepted requests.
- Regenerate the Xcode project after adding the new files. Production gate stays off pending explicitly reviewed activation; test fixtures alone pass `rolloutReviewed: true` and use synthetic credentials/URLProtocol.

## Local privacy behavior

The small identity/state record lives in a dedicated, non-synchronizing `AfterFirstUnlockThisDeviceOnly` Keychain item. A backup-excluded app-container marker contains only one format byte; absent marker means a fresh installation, so Keychain persistence across uninstall cannot silently restore consent. Neither marker nor Keychain data is written until the user chooses. No IDFA, IDFV, device model, OS version, network reachability, account identifier, clipboard or tracking SDK is used. Counters are capped at 1000/day/feature in Beijing time. Off preserves prior counters but adds none; delete clears them immediately. State/response bodies and credential values are never logged.

Requests are bounded POSTs, with ephemeral URLSession, no cookies/cache/credential storage, no redirects, a fixed destination, 2048-byte request cap and 4096-byte response cap. An HTTP 200 with Boolean `ok: true` is required to acknowledge recording/deletion. Retry is foreground/manual and normally throttled to five minutes; there is no background collection task.

## Privacy manifest and future activation

The current disabled production build collects no new analytics data, so do not claim the dormant implementation is collecting it. Existing unrelated manifest declarations still require a whole-app audit. Before any future enabling build, update the app's privacy policy, manifest and App Store privacy answers together with the actual shipped data flow. At minimum review Device ID (random installation identifier) and Product Interaction (daily feature counts/activity), Analytics purpose, tracking false. Review whether version/date and the service's salted network-address usage need additional classification. Do not label data “not linked” merely because it is called anonymous: the server relates events to a persistent installation ID. A conservative classification is linked to the installation/device. No third-party ad tracking is implemented.

Apple primary references, checked during implementation:
- https://developer.apple.com/app-store/app-privacy-details/
- https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests
- https://developer.apple.com/documentation/technotes/tn3184-adding-data-collection-details-to-your-privacy-manifest
- https://developer.apple.com/app-store/user-privacy-and-data-use/

## Verification

- Existing server's 7 synthetic node tests passed unchanged.
- Four additional local, read-only contract assertions passed: real build 1 rejected, same schema/build 102 accepted, added `platform` rejected, deletion schema accepted. No server or external network write.
- `Tests/AnalyticsTests.swift` adds synthetic XCTest coverage of opt-in/no-consent/no-write behavior, current rollout gates, bounded counters, exact payload fields, choice persistence failures, fast close/delete races, late results, cancellation, relaunch, offline deletion, ambiguous enrollment, Keychain/reinstall behavior, response limits, redirects and URLProtocol interception.
- This Linux executor has neither Swift nor Xcode. XCTest and Swift compilation are **not run** here and must pass the project's current Xcode simulator and unsigned iPhone CI checks. No real-account or physical-device acceptance is claimed.
