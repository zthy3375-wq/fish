# Native iOS validation

Baseline: Android main 780bbc85c0b70e8d9273129eca666d7141e21e42, production 1.2.1.

- Source and asset review: official icon and campus artwork reused; both school JavaScript resources are byte-identical to Android.
- No change to Android, application web code, cloud services, release version or update metadata.
- Linux executor has no Swift/Xcode. Native compilation, XCTest and screenshot results are pending macOS CI, not claimed as passed.
- Physical iPhone and real school login are untested. No production signing, IPA distribution, TestFlight or App Store submission.
- Full Android feature parity is not complete; see README's explicit remaining functionality list.
