#!/usr/bin/env python3
"""Check an imported CI distribution identity against its App Store profile."""

import argparse
import datetime as dt
import hashlib
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path

if __package__:
    from . import testflight_policy as policy
else:
    import testflight_policy as policy

BUNDLE_ID = policy.PHONE_ID


def validate(profile: dict, identities: str, team: str,
             now: dt.datetime | None = None, role: str = "phone") -> dict[str, str]:
    bundle_id = policy.role(role)["id"]
    if profile.get("TeamIdentifier") != [team]:
        raise ValueError("Distribution profile team differs")
    if profile.get("ApplicationIdentifierPrefix") != [team]:
        raise ValueError("Distribution profile prefix differs")
    # Apple's profile family can be iOS for a Watch companion. The exact App ID,
    # certificate and team bind the role; this is not a claim about a real profile.
    platforms = profile.get("Platform")
    allowed = [["iOS"]] if role == "phone" else [["iOS"], ["watchOS"], ["iOS", "watchOS"]]
    if platforms not in allowed:
        raise ValueError("Distribution profile platform family differs")
    if "ProvisionedDevices" in profile or "ProvisionsAllDevices" in profile:
        raise ValueError("Distribution profile permits device or enterprise distribution")
    entitlements = profile.get("Entitlements", {})
    if entitlements.get("application-identifier") != f"{team}.{bundle_id}":
        raise ValueError("Distribution profile app identifier differs")
    if entitlements.get("com.apple.developer.team-identifier") != team:
        raise ValueError("Distribution profile entitlement team differs")
    if entitlements.get("com.apple.developer.healthkit") is not True:
        raise ValueError("Distribution profile lacks HealthKit")
    if entitlements.get("get-task-allow") is not False:
        raise ValueError("Distribution profile permits debugging")
    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, dt.datetime):
        raise ValueError("Distribution profile expiration is missing")
    current = now or dt.datetime.now(dt.timezone.utc)
    if expiration.replace(tzinfo=expiration.tzinfo or dt.timezone.utc) <= current:
        raise ValueError("Distribution profile has expired")
    certificates = profile.get("DeveloperCertificates")
    if not isinstance(certificates, list) or len(certificates) != 1 or \
            not isinstance(certificates[0], bytes) or not certificates[0]:
        raise ValueError("Distribution profile must contain one signing certificate")
    fingerprint = hashlib.sha1(certificates[0]).hexdigest().upper()
    escaped_team = re.escape(team)
    identity = re.compile(rf"^\s*\d+\) {fingerprint} \"Apple Distribution: [^\"\n]+ \({escaped_team}\)\"$", re.MULTILINE)
    if len(identity.findall(identities)) != 1:
        raise ValueError("Matching Apple Distribution identity is not available in temporary keychain")
    uuid = profile.get("UUID")
    name = profile.get("Name")
    if not isinstance(uuid, str) or not re.fullmatch(r"[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}", uuid):
        raise ValueError("Distribution profile UUID is invalid")
    if not isinstance(name, str) or not name.strip() or any(c in name for c in "\r\n\x00"):
        raise ValueError("Distribution profile name is invalid")
    return {"uuid": uuid, "name": name, "certificate_sha1": fingerprint}


def distribution_entitlements(profile: dict, team: str, role: str = "phone") -> dict:
    bundle_id = policy.role(role)["id"]
    # Consumer-owned fixed entitlement policy: candidate input cannot broaden it.
    desired = {
        "application-identifier": f"{team}.{bundle_id}",
        "com.apple.developer.team-identifier": team,
        "com.apple.developer.healthkit": True,
        "get-task-allow": False,
        "beta-reports-active": True,
        "keychain-access-groups": [f"{team}.{bundle_id}"],
    }
    granted = profile.get("Entitlements", {})
    for key, value in desired.items():
        if key == "keychain-access-groups":
            groups = granted.get(key, [])
            if not isinstance(groups, list) or not any(
                    group in (f"{team}.{bundle_id}", f"{team}.*") for group in groups):
                raise ValueError("Profile does not grant the app's default keychain group")
        elif granted.get(key) != value or type(granted.get(key)) is not type(value):
            raise ValueError(f"Profile does not grant required distribution entitlement {key}")
    return desired


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--role", choices=tuple(policy.BUNDLES), required=True)
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--keychain", type=Path, required=True)
    parser.add_argument("--team", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--entitlements-output", type=Path)
    args = parser.parse_args()
    try:
        if not re.fullmatch(r"[A-Z0-9]{10}", args.team):
            raise ValueError("Invalid team identifier")
        profile = plistlib.loads(subprocess.check_output(
            ["security", "cms", "-D", "-i", str(args.profile)], stderr=subprocess.DEVNULL))
        identities = subprocess.check_output(
            ["security", "find-identity", "-v", "-p", "codesigning", str(args.keychain)],
            text=True, stderr=subprocess.DEVNULL)
        result = validate(profile, identities, args.team, role=args.role)
        if args.entitlements_output is not None:
            args.entitlements_output.write_bytes(plistlib.dumps(distribution_entitlements(profile, args.team, args.role)))
            args.entitlements_output.chmod(0o600)
        args.output.write_text(json.dumps(result))
        args.output.chmod(0o600)
        print("PASS: CI certificate and App Store profile match app, team and HealthKit capability")
    except (ValueError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
