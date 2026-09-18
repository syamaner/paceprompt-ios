#!/usr/bin/env python3
"""Fail-closed, credential-free checks for a TestFlight release tag."""

import argparse
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "PacePrompt.xcodeproj/project.pbxproj"
TAG = re.compile(r"testflight/(\d+\.\d+(?:\.\d+)?)-b([1-9]\d*)\Z")
BUNDLE_ID = "com.otherweather.PromptPace"


def fail(message: str) -> None:
    raise ValueError(message)


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def versions(project: str) -> tuple[str, str]:
    blocks = re.findall(
        r"AA000000000000000000A10[12] /\* (?:Debug|Release) \*/ = \{.*?\n\t\t\};",
        project,
        re.DOTALL,
    )
    if len(blocks) != 2:
        fail("Production Debug/Release build settings are missing")
    pairs = []
    for block in blocks:
        def setting(name: str) -> str:
            values = re.findall(rf"\b{name} = ([^;]+);", block)
            if len(values) != 1:
                fail(f"Expected one {name} in each production configuration")
            return values[0].strip('"')

        if setting("PRODUCT_BUNDLE_IDENTIFIER") != BUNDLE_ID:
            fail("Unexpected production bundle identifier")
        pairs.append((setting("MARKETING_VERSION"), setting("CURRENT_PROJECT_VERSION")))
    if pairs[0] != pairs[1]:
        fail("Production Debug and Release versions differ")
    return pairs[0]


def check_tag(tag: str, project: str) -> tuple[str, str]:
    match = TAG.fullmatch(tag)
    if match is None:
        fail("Tag must be testflight/<marketing-version>-b<build>")
    expected = match.groups()
    if versions(project) != expected:
        fail("Tag version/build differs from checked-in production settings")
    return expected


def api(path: str) -> object:
    token = os.environ.get("GITHUB_TOKEN")
    if not token:
        fail("Missing read-only GitHub token")
    request = urllib.request.Request(
        f"https://api.github.com/repos/{os.environ['GITHUB_REPOSITORY']}/{path}",
        headers={"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json"},
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        return json.load(response)


def source(tag: str, sha: str) -> None:
    check_tag(tag, PROJECT.read_text())
    if git("rev-parse", "HEAD") != sha:
        fail("Checkout is not the tag event SHA")
    if git("status", "--porcelain", "--untracked-files=all"):
        fail("Checkout differs from the tagged source tree")
    if git("cat-file", "-t", f"refs/tags/{tag}") != "commit":
        fail("Only lightweight commit tags are accepted")
    if git("rev-parse", f"refs/tags/{tag}") != sha:
        fail("Local tag moved from event SHA")
    remote = git("ls-remote", "--exit-code", "origin", f"refs/tags/{tag}").split()[0]
    if remote != sha:
        fail("Remote tag moved or does not match event SHA")
    git("fetch", "--no-tags", "origin", "+refs/heads/main:refs/remotes/origin/main")
    if sha not in git("rev-list", "--first-parent", "origin/main").splitlines():
        fail("Tag target is not a first-parent commit on current main")
    parents = git("rev-list", "--parents", "-n", "1", sha).split()
    if len(parents) != 3:
        fail("Tag target must be a merge commit")
    pulls = api(f"commits/{sha}/pulls")
    if not isinstance(pulls, list):
        fail("Pull-request association is unavailable")
    reviewed = [pr for pr in pulls if
                pr.get("merged_at") and pr.get("merge_commit_sha") == sha
                and pr.get("base", {}).get("ref") == "main"
                and pr.get("head", {}).get("sha") == parents[2]]
    if len(reviewed) != 1:
        fail("No merged pull request matches the second parent of main commit")
    if git("rev-parse", f"{sha}^{{tree}}") != git("rev-parse", f"{parents[2]}^{{tree}}"):
        fail("Merge tree differs from reviewed pull-request head")
    if f"Exact-head-review: {parents[2]}" not in git("show", "-s", "--format=%B", sha).splitlines():
        fail("Merge commit lacks the reviewed-head attestation")
    runs = api(f"actions/workflows/ci.yml/runs?head_sha={sha}&event=push&per_page=30")
    if not any(
        run.get("head_sha") == sha and run.get("conclusion") == "success"
        for run in runs.get("workflow_runs", [])
    ):
        fail("Fast main CI has not passed on the exact tag commit")
    print(f"PASS: source {sha}, tag {tag}, merged main PR and exact-SHA CI")


def plist(path: Path) -> dict:
    return plistlib.loads(path.read_bytes())


def metadata(info: dict, version: str, build: str) -> None:
    expected = {
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleShortVersionString": version,
        "CFBundleVersion": build,
        "ITSAppUsesNonExemptEncryption": False,
        "NSBluetoothAlwaysUsageDescription": "PacePrompt uses Bluetooth to connect to your treadmill and request speed and inclination targets during a workout you begin at its physical console.",
        "NSHealthShareUsageDescription": "PacePrompt does not read Apple Health data. It only asks to save a completed workout and optional distance when you choose Save to Apple Health.",
        "NSHealthUpdateUsageDescription": "PacePrompt saves a completed indoor workout and optional treadmill distance to Apple Health only when you choose Save to Apple Health.",
    }
    for key, value in expected.items():
        if key == "ITSAppUsesNonExemptEncryption":
            if info.get(key) is not False:
                fail(f"Unexpected or missing {key}")
        elif info.get(key) != value:
            fail(f"Unexpected or missing {key}")


def verify_signing_leaf(app: Path, certificate_sha1: str) -> None:
    with tempfile.TemporaryDirectory(prefix="paceprompt-signature-") as temporary:
        prefix = str(Path(temporary) / "certificate")
        subprocess.run(["codesign", "-d", "--extract-certificates", prefix, str(app)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        leaf = Path(f"{prefix}0").read_bytes()
        if hashlib.sha1(leaf).hexdigest().upper() != certificate_sha1:
            fail("Signed app certificate differs from approved CI identity")


def signed_entitlements(app: Path) -> dict:
    # macOS 26 emits a human-readable [Dict] for "-"; ":-" emits a plist.
    raw = subprocess.check_output(["codesign", "-d", "--entitlements", ":-", str(app)],
                                  stderr=subprocess.DEVNULL)
    try:
        result = plistlib.loads(raw)
    except plistlib.InvalidFileException:
        fail("Signed entitlements are not a property list")
    if not isinstance(result, dict):
        fail("Signed entitlements are not a dictionary")
    return result


def artifact(app: Path, tag: str, team: str, certificate_sha1: str) -> None:
    version, build = check_tag(tag, PROJECT.read_text())
    metadata(plist(app / "Info.plist"), version, build)
    privacy = plist(app / "PrivacyInfo.xcprivacy")
    if privacy != plist(ROOT / "PacePrompt/PrivacyInfo.xcprivacy"):
        fail("Bundled privacy manifest differs from source")
    signing = subprocess.check_output(["codesign", "-d", "--verbose=4", str(app)], text=True, stderr=subprocess.STDOUT)
    if f"Identifier={BUNDLE_ID}" not in signing or f"TeamIdentifier={team}" not in signing:
        fail("Distribution signature identity or team differs")
    if "Authority=Apple Distribution:" not in signing:
        fail("App is not Apple Distribution signed")
    signed = signed_entitlements(app)
    if signed.get("com.apple.developer.healthkit") is not True:
        fail("Signed app lacks HealthKit entitlement")
    if signed.get("get-task-allow") is not False:
        fail("Signed app permits debugging")
    if signed.get("com.apple.developer.team-identifier") != team:
        fail("Signed entitlement team differs")
    if signed.get("application-identifier") != f"{team}.{BUNDLE_ID}":
        fail("Signed application identifier differs")
    profile_path = app / "embedded.mobileprovision"
    if not profile_path.is_file():
        fail("Distribution provisioning profile is missing")
    profile = plistlib.loads(subprocess.check_output(["security", "cms", "-D", "-i", str(profile_path)], stderr=subprocess.DEVNULL))
    if profile.get("TeamIdentifier") != [team]:
        fail("Distribution profile belongs to another team")
    if profile.get("Entitlements", {}).get("application-identifier") != f"{team}.{BUNDLE_ID}":
        fail("Distribution profile app identifier differs")
    if profile.get("Entitlements", {}).get("get-task-allow") is not False:
        fail("Distribution profile permits debugging")
    if profile.get("Entitlements", {}).get("com.apple.developer.healthkit") is not True:
        fail("Distribution profile lacks HealthKit entitlement")
    if "ProvisionedDevices" in profile or "ProvisionsAllDevices" in profile:
        fail("Distribution profile allows non-App Store distribution")
    certificates = profile.get("DeveloperCertificates")
    if not isinstance(certificates, list) or len(certificates) != 1 or \
            hashlib.sha1(certificates[0]).hexdigest().upper() != certificate_sha1:
        fail("Embedded profile certificate differs from approved CI identity")
    subprocess.run(["codesign", "--verify", "--strict", "--deep", str(app)], check=True)
    verify_signing_leaf(app, certificate_sha1)
    print(f"PASS: signed artifact {BUNDLE_ID} {version} ({build}), team {team}")


def main() -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    src = commands.add_parser("source")
    src.add_argument("--tag", required=True)
    src.add_argument("--sha", required=True)
    art = commands.add_parser("artifact")
    art.add_argument("--app", type=Path, required=True)
    art.add_argument("--tag", required=True)
    art.add_argument("--team", required=True)
    art.add_argument("--certificate-sha1", required=True)
    args = parser.parse_args()
    try:
        if args.command == "source":
            source(args.tag, args.sha)
        else:
            artifact(args.app, args.tag, args.team, args.certificate_sha1)
    except (ValueError, KeyError, subprocess.CalledProcessError, OSError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
