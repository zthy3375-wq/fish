"""Verify the upload and distribute the new TestFlight build to existing testers."""
import base64
import json
import os
import re
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener

HOST = "api.appstoreconnect.apple.com"
API = f"https://{HOST}/v1/"
BUNDLE_ID = "org.handancampus.ios.native"
VERSION = "0.1.0"


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, location):
        return None


class AppleError(RuntimeError):
    def __init__(self, status, operation, payload):
        errors = payload.get("errors", []) if isinstance(payload, dict) else []
        codes = [row["code"] for row in errors if re.fullmatch(r"[A-Z0-9_.]+", row.get("code", ""))]
        self.status = status
        reason = " ".join(str(row.get("detail", "")).lower() for row in errors)
        categories = [term for term in ("required agreement", "required role", "does not have permission",
                      "not authorized", "beta review", "review information", "what to test",
                      "internal only", "already", "not allowed", "forbidden") if term in reason]
        super().__init__(f"Apple API {status} for {operation}" + (f" ({', '.join(codes + categories)})" if codes or categories else ""))


def encoded(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=")


def jwt():
    now = int(time.time())
    header = {"alg": "ES256", "kid": os.environ["ASC_KEY_ID"], "typ": "JWT"}
    claims = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now - 10, "exp": now + 300, "aud": "appstoreconnect-v1"}
    message = b".".join(encoded(json.dumps(x).encode()) for x in (header, claims))
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", os.environ["ASC_KEY_PATH"]],
                         input=message, stdout=subprocess.PIPE, check=True).stdout
    if der[0] != 48 or der[1] != len(der) - 2:
        raise ValueError("Unexpected ES256 signature")
    raw = bytearray()
    index = 2
    for _ in range(2):
        if der[index] != 2:
            raise ValueError("Unexpected ES256 component")
        end = index + 2 + der[index + 1]
        raw.extend(int.from_bytes(der[index + 2:end], "big").to_bytes(32, "big"))
        index = end
    if index != len(der):
        raise ValueError("Unexpected ES256 signature length")
    return (message + b"." + encoded(raw)).decode()


def api(path, params=None, method="GET", data=None):
    url = path if path.startswith("https://") else API + path
    parsed = urlsplit(url)
    if parsed.netloc != HOST or not parsed.path.startswith("/v1/"):
        raise ValueError("Unexpected App Store Connect URL")
    if params:
        url += "?" + urlencode(params)
    for attempt in range(5):
        request = Request(url, data=json.dumps(data).encode() if data is not None else None, method=method,
                          headers={"Authorization": "Bearer " + jwt(), "Accept": "application/json",
                                   "Content-Type": "application/json"})
        try:
            with build_opener(NoRedirect()).open(request, timeout=30) as response:
                return json.loads(response.read() or b"{}")
        except HTTPError as error:
            try:
                payload = json.loads(error.read())
            except (ValueError, OSError):
                payload = {}
            if method != "GET" or error.code not in {429, 500, 502, 503, 504} or attempt == 4:
                raise AppleError(error.code, method + " " + parsed.path, payload) from None
        except (URLError, TimeoutError):
            if method != "GET" or attempt == 4:
                raise
        time.sleep(2 ** attempt)


def all_rows(path, params=None):
    result = []
    included = {}
    while path:
        page = api(path, params)
        result.extend(page["data"])
        included.update({(row["type"], row["id"]): row for row in page.get("included", [])})
        path = page.get("links", {}).get("next")
        params = None
    return result, included


def ios_builds(app_id):
    rows, included = all_rows("builds", {"filter[app]": app_id, "include": "preReleaseVersion",
                                         "fields[preReleaseVersions]": "version,platform", "limit": 200})
    result = []
    for row in rows:
        pointer = row.get("relationships", {}).get("preReleaseVersion", {}).get("data") or {}
        train = included.get(("preReleaseVersions", pointer.get("id")), {}).get("attributes", {})
        if train.get("version") == VERSION and train.get("platform") == "IOS":
            result.append(row)
    return result


def summary(message):
    print(message, flush=True)
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as file:
        file.write(message + "\n\n")


def find_build(builds, number):
    return next((row for row in builds if row["attributes"]["version"] == number), None)


def version_key(number):
    parts = tuple(map(int, number.split(".")))
    return parts + (0,) * (3 - len(parts))


def select_previous(builds, current):
    new = current["attributes"]
    older = [row for row in builds if row["id"] != current["id"]
             and row["attributes"].get("processingState") == "VALID"
             and row["attributes"].get("uploadedDate", "") < new["uploadedDate"]
             and version_key(row["attributes"]["version"]) < version_key(new["version"])]
    return max(older, key=lambda row: row["attributes"]["uploadedDate"], default=None)


def related(build_id, relation, fields=None):
    params = {"limit": 200}
    if fields:
        params.update(fields)
    return all_rows(f"builds/{build_id}/{relation}", params)[0]


def related_ids(build_id, relation, fields=None):
    return {row["id"] for row in related(build_id, relation, fields)}


def group_has_build(group_id, build_id):
    rows, _ = all_rows(f"betaGroups/{group_id}/builds", {"fields[builds]": "version", "limit": 200})
    return any(row["id"] == build_id for row in rows)


def release_reference(builds):
    reference = find_build(builds, os.environ["TF_REFERENCE_BUILD"])
    if not reference or reference["attributes"].get("processingState") != "VALID":
        raise RuntimeError("The previous distributed reference build is unavailable.")
    if reference["attributes"].get("usesNonExemptEncryption") is not False:
        raise RuntimeError("The signed build requires the previous recorded Apple declaration.")
    return reference


def check(app_id, number):
    builds = ios_builds(app_id)
    reference = release_reference(builds)
    if version_key(reference["attributes"]["version"]) >= version_key(number):
        raise RuntimeError("Expected an earlier reference build.")
    summary("Verified the existing encryption declaration for " + VERSION + " (" + reference["attributes"]["version"] + ").")
    candidate = find_build(builds, number)
    resume = os.environ.get("TF_RESUME_ONLY") == "true" or os.environ.get("GITHUB_RUN_ATTEMPT", "1") != "1"
    if candidate and (not resume or candidate["attributes"]["processingState"] in {"FAILED", "INVALID"}
                      or candidate["attributes"].get("expired")):
        raise RuntimeError(f"Build {number} already exists or cannot be resumed")
    if not candidate and os.environ.get("TF_RESUME_ONLY") == "true":
        raise RuntimeError(f"Already uploaded build {number} could not be found")
    if any(version_key(row["attributes"]["version"]) > version_key(number) for row in builds):
        raise RuntimeError(f"A newer build already exists in this release train than {number}")
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as file:
        file.write(f"exists={str(candidate is not None).lower()}\n")
    summary(f"App Store Connect access verified. Target {VERSION} ({number}).")


def wait_for_processing(app_id, number):
    deadline = time.monotonic() + 35 * 60
    while time.monotonic() < deadline:
        builds = ios_builds(app_id)
        build = find_build(builds, number)
        state = build["attributes"]["processingState"] if build else "awaiting Apple registration"
        print(f"Build {number}: {state}", flush=True)
        if state == "VALID":
            summary(f"Apple accepted {VERSION} ({number}).")
            return builds, build
        if state in {"FAILED", "INVALID"}:
            raise RuntimeError(f"Apple rejected build {number}: {state}")
        time.sleep(45)
    raise RuntimeError(f"Build {number} was submitted; Apple processing is still pending.")


def beta_state(build_id):
    return api(f"builds/{build_id}/buildBetaDetail")["data"]["attributes"]


def prepare_feedback(build_id):
    notes = os.environ.get("TF_WHAT_TO_TEST")
    if not notes:
        return
    try:
        locales = related(build_id, "betaBuildLocalizations")
        row = next((item for item in locales if item["attributes"]["locale"] == "zh-Hans"), None)
        if row:
            if row["attributes"].get("whatsNew") != notes:
                api(f"betaBuildLocalizations/{row['id']}", method="PATCH", data={"data": {
                    "type": "betaBuildLocalizations", "id": row["id"], "attributes": {"whatsNew": notes}}})
        else:
            api("betaBuildLocalizations", method="POST", data={"data": {
                "type": "betaBuildLocalizations", "attributes": {"locale": "zh-Hans", "whatsNew": notes},
                "relationships": {"build": {"data": {"type": "builds", "id": build_id}}}}})
        summary("Chinese TestFlight testing notes are available.")
    except AppleError as error:
        summary(f"Testing notes could not be written: {error}. Continuing distribution.")


def resolve_compliance(current, previous):
    current_id = current["id"]
    deadline = time.monotonic() + 4 * 60
    applied = False
    while time.monotonic() < deadline:
        state = beta_state(current_id)
        internal = state.get("internalBuildState")
        print(f"Pre-distribution beta status: internal={internal}, external={state.get('externalBuildState')}",
              flush=True)
        if internal in {"READY_FOR_BETA_TESTING", "IN_BETA_TESTING"}:
            return
        if internal == "MISSING_EXPORT_COMPLIANCE" and not applied:
            if not previous or previous["attributes"].get("usesNonExemptEncryption") is not False:
                raise RuntimeError("Export compliance is required and no verified exemption is recorded for the previous build.")
            api(f"builds/{current_id}", method="PATCH", data={"data": {
                "type": "builds", "id": current_id, "attributes": {"usesNonExemptEncryption": False}
            }})
            applied = True
            summary("Applied the same recorded export-compliance exemption as the preceding iOS build.")
        if internal in {"PROCESSING_EXCEPTION", "EXPIRED", "IN_EXPORT_COMPLIANCE_REVIEW"}:
            raise RuntimeError(f"New build uploaded; testing awaits App Store Connect action ({internal}).")
        time.sleep(15)
    raise RuntimeError("The new build is still unavailable for testing; the previous build remains available.")


def rollout(app_id, number):
    builds, current = wait_for_processing(app_id, number)
    previous = release_reference(builds)
    current_id = current["id"]
    resolve_compliance(current, previous)
    prepare_feedback(current_id)
    group_fields = {"fields[betaGroups]": "isInternalGroup,hasAccessToAllBuilds"}
    tester_fields = {"fields[betaTesters]": "inviteType"}
    all_groups = all_rows("betaGroups", {"filter[app]": app_id, **group_fields, "limit": 200})[0]
    automatic = {row["id"] for row in all_groups
                 if row["attributes"].get("isInternalGroup") and row["attributes"].get("hasAccessToAllBuilds")}
    earlier = find_build(builds, os.environ.get("TF_EARLIER_GROUP_BUILD"))
    sources = [previous["id"]]
    if earlier and not earlier["attributes"].get("expired"):
        sources.append(earlier["id"])
    old_groups = [row for row in all_groups if row["id"] not in automatic
                  and any(group_has_build(row["id"], source) for source in sources)]
    old_testers = related(previous["id"], "individualTesters", tester_fields) if previous else []
    missing_groups = {row["id"] for row in old_groups if not group_has_build(row["id"], current_id)}
    summary(f"Eligible audiences: {len(automatic)} automatic internal group(s), "
            f"{sum(not row['attributes']['isInternalGroup'] for row in old_groups)} existing external group(s).")
    external = any(not row["attributes"]["isInternalGroup"] for row in old_groups) or any(
        row["attributes"].get("inviteType") not in {"INTERNAL", "INTERNAL_TESTER"} for row in old_testers
    )
    if external:
        detail = api(f"builds/{current_id}/buildBetaDetail")["data"]
        if not detail["attributes"].get("autoNotifyEnabled"):
            try:
                api(f"buildBetaDetails/{detail['id']}", method="PATCH", data={"data": {
                    "type": "buildBetaDetails", "id": detail["id"], "attributes": {"autoNotifyEnabled": True}}})
            except AppleError as error:
                summary(f"Automatic tester notification could not be enabled: {error}. Continuing distribution.")
    review_requested = False
    if external and os.environ.get("TF_RESUME_ONLY") == "true":
        summary(f"External rollout check: audience={current['attributes'].get('buildAudienceType')}, "
                f"state={detail['attributes'].get('externalBuildState')}.")
        if detail["attributes"].get("externalBuildState") == "READY_FOR_BETA_SUBMISSION":
            try:
                api("betaAppReviewSubmissions", method="POST", data={"data": {
                    "type": "betaAppReviewSubmissions",
                    "relationships": {"build": {"data": {"type": "builds", "id": current_id}}}}})
                review_requested = True
                summary("Apple accepted the external TestFlight beta review submission.")
            except AppleError as error:
                summary(f"External beta review submission response: {error}.")
    for group_id in sorted(missing_groups):
        try:
            api(f"builds/{current_id}/relationships/betaGroups", method="POST",
                data={"data": [{"type": "betaGroups", "id": group_id}]})
        except AppleError as error:
            if error.status not in {409, 422} or not group_has_build(group_id, current_id):
                group = next(row for row in old_groups if row["id"] == group_id)
                kind = "internal" if group["attributes"]["isInternalGroup"] else "external"
                raise RuntimeError(f"Apple denied the existing {kind} tester group. {error}") from None
    tester_ids = {row["id"] for row in old_testers}
    missing_testers = tester_ids - related_ids(current_id, "individualTesters", tester_fields) if tester_ids else set()
    if missing_testers:
        api(f"builds/{current_id}/relationships/individualTesters", method="POST",
            data={"data": [{"type": "betaTesters", "id": item} for item in sorted(missing_testers)]})
    deadline = time.monotonic() + 12 * 60
    while time.monotonic() < deadline:
        state = beta_state(current_id)
        internal, outside = state.get("internalBuildState"), state.get("externalBuildState")
        print(f"Beta availability: internal={internal}, external={outside}, autoNotify={state.get('autoNotifyEnabled')}",
              flush=True)
        if internal in {"MISSING_EXPORT_COMPLIANCE", "PROCESSING_EXCEPTION", "EXPIRED"}:
            raise RuntimeError(f"Build uploaded; testing requires App Store Connect action ({internal}). Previous build kept.")
        audiences_ready = all(group_has_build(row["id"], current_id) for row in old_groups) and (
            not tester_ids or tester_ids <= related_ids(current_id, "individualTesters", tester_fields)
        )
        internal_ready = internal == "IN_BETA_TESTING" or (
            internal == "READY_FOR_BETA_TESTING" and bool(automatic)
        )
        if audiences_ready and (internal_ready or external and outside == "IN_BETA_TESTING") and (
                not external or outside == "IN_BETA_TESTING"):
            summary(f"TestFlight is available for {VERSION} ({number}) for the existing testers.")
            return
        if external and outside == "READY_FOR_BETA_SUBMISSION" and not review_requested:
            api("betaAppReviewSubmissions", method="POST", data={"data": {
                "type": "betaAppReviewSubmissions",
                "relationships": {"build": {"data": {"type": "builds", "id": current_id}}}
            }})
            review_requested = True
            summary("Submitted the replacement for external TestFlight beta review.")
        if external and outside in {"WAITING_FOR_BETA_REVIEW", "IN_BETA_REVIEW", "BETA_REJECTED",
                                    "MISSING_BETA_REVIEW_INFO"}:
            summary(f"External TestFlight status is {outside}. The previous build remains available.")
            return
        time.sleep(30)
    raise RuntimeError("New build uploaded; tester availability was not verified. Previous build kept.")


def main():
    number = os.environ["TF_BUILD"]
    if not re.fullmatch(r"[1-9][0-9]{0,3}(\.[0-9]{1,2}){0,2}", number):
        raise ValueError("Invalid build number")
    records = api("apps", {"filter[bundleId]": BUNDLE_ID})["data"]
    if len(records) != 1 or records[0]["attributes"]["bundleId"] != BUNDLE_ID:
        raise RuntimeError("Expected the existing Hanyuantong iOS app")
    app_id = records[0]["id"]
    if not app_id.isdigit():
        raise ValueError("Unexpected App Store Connect identifier")
    summary(f"[Hanyuantong TestFlight](https://appstoreconnect.apple.com/apps/{app_id}/testflight/ios)")
    {"check": check, "rollout": rollout}[sys.argv[1]](app_id, number)


if __name__ == "__main__":
    main()
