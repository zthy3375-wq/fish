"""Install the two release profiles and configure the temporary CI checkout."""
import base64
import datetime as dt
import io
import os
import plistlib
import re
import subprocess
import sys
import zipfile
from pathlib import Path

BASE_ID = "org.handancampus.ios.native"
TARGETS = {"Hanyuantong": (BASE_ID, "Hanyuantong_AppStore", "Hanyuantong"),
           "HanyuantongWidget": (BASE_ID + ".HanyuantongWidget", "Hanyuantong_Widget_AppStore", "Widget")}
ROOT = Path("ios-native")


def command(*args):
    return subprocess.check_output(args)


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def load_profiles(bundle, directory):
    profiles = {}
    now = dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)
    with zipfile.ZipFile(io.BytesIO(bundle)) as files:
        cert = files.read("distribution.cer")
        (directory / "distribution.cer").write_bytes(cert)
        for name, (bundle_id, profile_name, _) in TARGETS.items():
            raw = files.read(profile_name + ".mobileprovision")
            path = directory / (name + ".mobileprovision")
            path.write_bytes(raw)
            profile = plistlib.loads(command("security", "cms", "-D", "-i", str(path)))
            ent = profile["Entitlements"]
            team, = profile["TeamIdentifier"]
            prefix, = profile["ApplicationIdentifierPrefix"]
            require(profile["CreationDate"] <= now < profile["ExpirationDate"], "Expired or inactive profile: " + name)
            require(cert in profile["DeveloperCertificates"], "Certificate mismatch: " + name)
            require(ent["application-identifier"] == prefix + "." + bundle_id and
                    team == ent["com.apple.developer.team-identifier"] and
                    "group." + BASE_ID in ent["com.apple.security.application-groups"] and
                    prefix + ".*" in ent["keychain-access-groups"] and
                    ent.get("beta-reports-active") and ent.get("get-task-allow") is False and
                    not profile.get("ProvisionsAllDevices") and "ProvisionedDevices" not in profile,
                    "Incorrect App Store provisioning or entitlements: " + name)
            uuid = profile["UUID"]
            require(re.fullmatch(r"[a-fA-F0-9-]{36}", uuid), "Invalid profile UUID")
            profiles[name] = (team, uuid)
            install_dir = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles"
            install_dir.mkdir(parents=True, exist_ok=True)
            (install_dir / (uuid + ".mobileprovision")).write_bytes(raw)
    require(len({item[0] for item in profiles.values()}) == 1, "Profile teams differ")
    return profiles


def configure(directory, profiles, build):
    path = ROOT / "Hanyuantong.xcodeproj/project.pbxproj"
    project = plistlib.loads(command("plutil", "-convert", "xml1", "-o", "-", str(path)))
    objects = project["objects"]
    found = set()
    mapping = {}
    for obj in objects.values():
        name = obj.get("name")
        if obj.get("isa") != "PBXNativeTarget" or name not in TARGETS:
            continue
        bundle_id, _, folder = TARGETS[name]
        team, uuid = profiles[name]
        for config_id in objects[obj["buildConfigurationList"]]["buildConfigurations"]:
            config = objects[config_id]
            if config["name"] == "Release":
                config["buildSettings"].update(CODE_SIGN_STYLE="Manual", CODE_SIGN_IDENTITY="Apple Distribution",
                                               DEVELOPMENT_TEAM=team, PROVISIONING_PROFILE_SPECIFIER=uuid)
                found.add(name)
        info_path = ROOT / folder / "Info.plist"
        info = plistlib.loads(info_path.read_bytes())
        info["CFBundleVersion"] = build
        info_path.write_bytes(plistlib.dumps(info))
        mapping[bundle_id] = uuid
    require(found == TARGETS.keys(), "Release target configuration missing")
    path.write_bytes(plistlib.dumps(project))
    export = {"method": "app-store-connect", "destination": "upload", "teamID": profiles["Hanyuantong"][0],
              "signingStyle": "manual", "signingCertificate": "Apple Distribution", "provisioningProfiles": mapping,
              "manageAppVersionAndBuildNumber": False, "uploadSymbols": True}
    (directory / "ExportOptions.plist").write_bytes(plistlib.dumps(export))


def verify_archive(archive, build):
    app = archive / "Products/Applications/Hanyuantong.app"
    for name, path in (("Hanyuantong", app), ("HanyuantongWidget", app / "PlugIns/HanyuantongWidget.appex")):
        bundle_id = TARGETS[name][0]
        info = plistlib.loads((path / "Info.plist").read_bytes())
        require(info["CFBundleIdentifier"] == bundle_id and info["CFBundleVersion"] == build and
                info["CFBundleShortVersionString"] == "0.1.0" and info["CFBundleSupportedPlatforms"] == ["iPhoneOS"],
                "Archive metadata mismatch: " + name)
        require(int(info["DTSDKName"].removeprefix("iphoneos").split(".")[0]) >= 26, "Unexpected archive SDK")
        command("codesign", "--verify", "--strict", str(path))
        ent = plistlib.loads(command("codesign", "-d", "--entitlements", ":-", str(path)))
        profile = plistlib.loads(command("security", "cms", "-D", "-i", str(path / "embedded.mobileprovision")))
        require(ent["application-identifier"] == profile["Entitlements"]["application-identifier"] and
                not ent.get("get-task-allow") and "group." + BASE_ID in ent["com.apple.security.application-groups"] and
                profile["ApplicationIdentifierPrefix"][0] + "." + BASE_ID + ".shared" in ent["keychain-access-groups"],
                "Signed entitlements mismatch: " + name)
        print(f"Verified {bundle_id}, version 0.1.0 ({build}), {info['DTSDKName']}")


if __name__ == "__main__":
    if sys.argv[1] == "verify":
        verify_archive(Path(sys.argv[2]), sys.argv[3])
    else:
        directory = Path(sys.argv[2])
        encoded = "".join(os.environ["IOS_SIGNING_FILES_BASE64"].split())
        configure(directory, load_profiles(base64.b64decode(encoded, validate=True), directory), sys.argv[3])
