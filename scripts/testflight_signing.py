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

BUNDLE_ID = "com.otherweather.PromptPace"


def validate(profile: dict, certificate: bytes, identities: str, team: str,
             now: dt.datetime | None = None) -> dict[str, str]:
    if profile.get("TeamIdentifier") != [team]:
        raise ValueError("Distribution profile team differs")
    if profile.get("ApplicationIdentifierPrefix") != [team]:
        raise ValueError("Distribution profile prefix differs")
    if "iOS" not in profile.get("Platform", []):
        raise ValueError("Distribution profile is not for iOS")
    if "ProvisionedDevices" in profile or profile.get("ProvisionsAllDevices") is not None:
        raise ValueError("Distribution profile permits device or enterprise distribution")
    entitlements = profile.get("Entitlements", {})
    if entitlements.get("application-identifier") != f"{team}.{BUNDLE_ID}":
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
    if not isinstance(certificates, list) or len(certificates) != 1 or certificates[0] != certificate:
        raise ValueError("Distribution profile certificate differs from imported identity")
    fingerprint = hashlib.sha1(certificate).hexdigest().upper()
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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--certificate", type=Path, required=True)
    parser.add_argument("--keychain", type=Path, required=True)
    parser.add_argument("--team", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if not re.fullmatch(r"[A-Z0-9]{10}", args.team):
            raise ValueError("Invalid team identifier")
        profile = plistlib.loads(subprocess.check_output(
            ["security", "cms", "-D", "-i", str(args.profile)], stderr=subprocess.DEVNULL))
        certificate = args.certificate.read_bytes()
        identities = subprocess.check_output(
            ["security", "find-identity", "-v", "-p", "codesigning", str(args.keychain)],
            text=True, stderr=subprocess.DEVNULL)
        result = validate(profile, certificate, identities, args.team)
        args.output.write_text(json.dumps(result))
        args.output.chmod(0o600)
        print("PASS: CI certificate and App Store profile match app, team and HealthKit capability")
    except (ValueError, OSError, subprocess.CalledProcessError, plistlib.InvalidFileException) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
