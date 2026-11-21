#!/usr/bin/env python3
"""Static guard for the shared Android/iOS achievement contract.

This is intentionally narrow: it prevents missing catalog IDs and native route
regressions. It does not assert UI, server, payment, school or hardware parity.
"""
from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
android = (root / "src/domain/globalAchievements.ts").read_text(encoding="utf-8")
community = (root / "src/domain/communityHonors.ts").read_text(encoding="utf-8")
ios = (root / "ios-native/Hanyuantong/Features/Achievements/CampusAchievementStore.swift").read_text(encoding="utf-8")
root_view = (root / "ios-native/Hanyuantong/Views/RootView.swift").read_text(encoding="utf-8")
service = (root / "ios-native/Hanyuantong/Services/TreeholeService.swift").read_text(encoding="utf-8")
profile = (root / "ios-native/Hanyuantong/Views/ProfileView.swift").read_text(encoding="utf-8")
project = (root / "ios-native/Hanyuantong.xcodeproj/project.pbxproj").read_text(encoding="utf-8")

android_local = re.findall(r"\blocal\('([a-z][a-z0-9-]*)'", android)
android_cloud = re.findall(r"\{code:'([a-z][a-z0-9-]*)'", community)
ios_codes = re.findall(r'\.init\("([a-z][a-z0-9-]*)",', ios)
expected = set(android_local) | set(android_cloud)
actual = set(ios_codes)
errors = []

if len(android_local) != len(set(android_local)):
    errors.append("Android local achievement definitions contain duplicate codes")
if len(android_cloud) != len(set(android_cloud)):
    errors.append("Android community achievement definitions contain duplicate codes")
if len(ios_codes) != len(actual):
    errors.append("iOS achievement definitions contain duplicate codes")
if missing := expected - actual:
    errors.append("iOS missing achievement IDs: " + ", ".join(sorted(missing)))
if extra := actual - expected:
    errors.append("iOS has IDs not in Android catalog: " + ", ".join(sorted(extra)))
if len(actual) < 25:
    errors.append("Unexpectedly small native achievement catalog")
for title in ["首页", "课表", "社区", "待办", "我的"]:
    if f'Label("{title}", systemImage:' not in root_view:
        errors.append(f"Missing native tab: {title}")
if "CampusAchievementCollectionView()" not in profile:
    errors.append("Global achievement hall is absent from iOS personal page")
if '"honors.hall"' not in service or '"collection.profile"' not in service:
    errors.append("Native community honor actions missing")
for path in ["Hanyuantong/Features/Achievements/CampusAchievementStore.swift",
             "Hanyuantong/Views/CampusAchievementCollectionView.swift"]:
    if f'"{path}"' not in project:
        errors.append(f"New native file not included in committed Xcode project: {path}")

print(f"Android: {len(expected)} unique achievement codes | iOS: {len(actual)}")
if errors:
    for error in errors:
        print("ERROR:", error, file=sys.stderr)
    raise SystemExit(1)
print("Native achievement ID, entry and build-reference contract: OK")
