# Native iOS validation

Baseline: Android main 780bbc85c0b70e8d9273129eca666d7141e21e42, production 1.2.1.

- Native protocol metadata adaptation: 5 JSDOM synthetic scenarios passed, including repeated all-history queries, partial failure and explicit-term metadata.
- Source and asset review: official icon and campus artwork reused; both school JavaScript resources are byte-identical to Android.
- No change to Android, application web code, cloud services, release version or update metadata.
- `npm ci` from the unchanged lockfile, 439 frontend tests, TypeScript and production build passed. Initial reused dependency directory lacked Leaflet; clean installation resolved it.
- Independent static security review found and fixed automatic refresh narrowing all-history grades and failure of current-term partial merges. Query selection now remains independent of resolved term; native adapter retains resolved-term metadata even on timetable failures. Additional fixes preserve inaccessible Keychain/cache records and refresh stale presenters.
- 21 native XCTest cases (10 academic adapter/session, 3 schedule, 8 backup) and two UI smoke scenarios are committed, not yet executed. There is no Linux Swift/Xcode toolchain.
- Initial macOS CI run 42998193147 on source 8b9478e passed SwiftUI simulator compilation, 10 initial unit tests and one UI navigation/cancel/relaunch smoke scenario. The expanded final source still requires its own rerun; initial success does not validate later changes.
- Web synthetic UI check could not launch because Playwright Chromium is absent in this executor; this is not iOS UI verification.
- Physical iPhone and real school login are untested. No production signing, IPA distribution, TestFlight or App Store submission.
- Full Android feature parity is not complete; see README's explicit remaining functionality list.
