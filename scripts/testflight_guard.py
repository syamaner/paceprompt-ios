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


if __package__:
    from . import testflight_policy as policy, testflight_signing as signing_policy, testflight_handoff as handoff
else:
    import testflight_policy as policy
    import testflight_signing as signing_policy
    import testflight_handoff as handoff
TRUSTED_ROOT = Path(__file__).resolve().parents[1]

# A trusted signer reads candidate metadata as data; it never imports candidate code.
ROOT = Path(os.environ.get("PACEPROMPT_RELEASE_SOURCE_ROOT",
                           str(Path(__file__).resolve().parents[1]))).resolve()
PROJECT = ROOT / "PacePrompt.xcodeproj/project.pbxproj"
TAG = re.compile(r"testflight/(\d+\.\d+(?:\.\d+)?)-b([1-9]\d*)\Z")
BUNDLE_ID = "com.otherweather.PromptPace"


def fail(message: str) -> None:
    raise ValueError(message)


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def versions(project: str) -> tuple[str, str]:
    blocks = re.findall(
        r"(?:AA000000000000000000A10[12]|D1150000000000000000070[23]) /\* (?:Debug|Release) \*/ = \{.*?name = (?:Debug|Release);\s*\};",
        project,
        re.DOTALL,
    )
    if len(blocks) != 4:
        fail("Production Debug/Release build settings are missing")
    pairs = []
    for block in blocks:
        def setting(name: str) -> str:
            values = re.findall(rf"\b{name} = ([^;]+);", block)
            if len(values) != 1:
                fail(f"Expected one {name} in each production configuration")
            return values[0].strip('"')

        expected_id = policy.WATCH_ID if "D115" in block else BUNDLE_ID
        if setting("PRODUCT_BUNDLE_IDENTIFIER") != expected_id:
            fail("Unexpected production bundle identifier")
        pairs.append((setting("MARKETING_VERSION"), setting("CURRENT_PROJECT_VERSION")))
    if any(pair != pairs[0] for pair in pairs):
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


def metadata(info: dict, version: str, build: str, role: str = "phone") -> None:
    policy.metadata(info, version, build, role)


def checked_bundles(app: Path, tag: str, signed: bool = False):
    version, build = check_tag(tag, PROJECT.read_text())
    bundles = policy.app_graph(app, signed)
    for role, bundle in bundles.items():
        metadata(plist(bundle / "Info.plist"), version, build, role)
        source = "PacePrompt" if role == "phone" else "PacePromptWatch"
        privacy = plist(bundle / "PrivacyInfo.xcprivacy")
        if privacy != plist(TRUSTED_ROOT / source / "PrivacyInfo.xcprivacy"):
            fail(f"{role}: privacy manifest differs from trusted policy")
        policy.macho((bundle / policy.role(role)["executable"]).read_bytes(), role, signed)
    return bundles


def unsigned(app: Path, tag: str) -> None:
    checked_bundles(app, tag)
    print("PASS: unsigned iPhone and Watch device artifacts")


def verify_signing_leaf(app: Path, certificate_sha1: str, architecture: str | None = None) -> None:
    selection = ["--architecture", architecture] if architecture else []
    with tempfile.TemporaryDirectory(prefix="paceprompt-signature-") as temporary:
        prefix = str(Path(temporary) / "certificate")
        try:
            subprocess.run(["codesign", "-d", *selection, f"--extract-certificates={prefix}", str(app)],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError:
            fail("Signed app certificate extraction failed")
        leaf_path = Path(f"{prefix}0")
        if not leaf_path.is_file():
            fail("Signed app certificate was not extracted")
        leaf = leaf_path.read_bytes()
        if hashlib.sha1(leaf).hexdigest().upper() != certificate_sha1:
            fail("Signed app certificate differs from approved CI identity")


def signed_entitlements(app: Path, architecture: str | None = None) -> dict:
    selection = ["--architecture", architecture] if architecture else []
    # macOS 26 emits a human-readable [Dict] for "-"; ":-" emits a plist.
    raw = subprocess.check_output(["codesign", "-d", *selection, "--entitlements", ":-", str(app)],
                                  stderr=subprocess.DEVNULL)
    try:
        result = plistlib.loads(raw)
    except plistlib.InvalidFileException:
        fail("Signed entitlements are not a property list")
    if not isinstance(result, dict):
        fail("Signed entitlements are not a dictionary")
    return result


def artifact(app: Path, tag: str, team: str, certificate_sha1: str) -> None:
    bundles = checked_bundles(app, tag, signed=True)
    uuids = set()
    # Nested code first. Every check must pass for both before the caller uploads.
    for role in ("watch", "phone"):
        bundle = bundles[role]
        bundle_id = policy.role(role)["id"]
        profile = plistlib.loads(subprocess.check_output(
            ["security", "cms", "-D", "-i", str(bundle / "embedded.mobileprovision")],
            stderr=subprocess.DEVNULL))
        # Bind the embedded profile to the already-approved keychain fingerprint.
        identity = f'  1) {certificate_sha1} "Apple Distribution: Approved ({team})"'
        result = signing_policy.validate(profile, identity, team, role=role)
        if result["uuid"] in uuids:
            fail("Phone and Watch profiles must be distinct")
        uuids.add(result["uuid"])
        desired = signing_policy.distribution_entitlements(profile, team, role)
        cpus = policy.macho((bundle / policy.role(role)["executable"]).read_bytes(), role, signed=True)
        for cpu in sorted(cpus):
            architecture = {0x100000c: "arm64", 0x200000c: "arm64_32"}[cpu]
            details = subprocess.check_output(
                ["codesign", "-d", "--architecture", architecture, "--verbose=4", str(bundle)],
                text=True, stderr=subprocess.STDOUT)
            lines = details.splitlines()
            if f"Identifier={bundle_id}" not in lines or f"TeamIdentifier={team}" not in lines:
                fail(f"{role}/{architecture}: distribution signature identity or team differs")
            if not any(line.startswith("Authority=Apple Distribution:") for line in lines):
                fail(f"{role}/{architecture}: app is not Apple Distribution signed")
            signed = signed_entitlements(bundle, architecture)
            if plistlib.dumps(signed, sort_keys=True) != plistlib.dumps(desired, sort_keys=True):
                fail(f"{role}/{architecture}: signed entitlements differ from fixed policy")
            verify_signing_leaf(bundle, certificate_sha1, architecture)
        subprocess.run(["codesign", "--verify", "--all-architectures", "--strict", "--deep", str(bundle)], check=True)
    print("PASS: signed iPhone and Watch artifacts, profiles, privacy and exact entitlements")


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
    exported = commands.add_parser("exported")
    exported.add_argument("--ipa", type=Path, required=True)
    exported.add_argument("--destination", type=Path, required=True)
    exported.add_argument("--tag", required=True)
    exported.add_argument("--team", required=True)
    exported.add_argument("--certificate-sha1", required=True)
    uns = commands.add_parser("unsigned")
    uns.add_argument("--app", type=Path, required=True)
    uns.add_argument("--tag", required=True)
    args = parser.parse_args()
    try:
        if args.command == "source":
            source(args.tag, args.sha)
        elif args.command == "unsigned":
            unsigned(args.app, args.tag)
        elif args.command == "exported":
            app = handoff.unpack_ipa(args.ipa, args.destination)
            artifact(app, args.tag, args.team, args.certificate_sha1)
        else:
            artifact(args.app, args.tag, args.team, args.certificate_sha1)
    except (ValueError, KeyError, subprocess.CalledProcessError, OSError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
