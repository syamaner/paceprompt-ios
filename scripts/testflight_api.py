#!/usr/bin/env python3
"""Narrow App Store Connect operations for internal TestFlight distribution."""

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path


HOST = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.otherweather.PromptPace"


def require(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise ValueError(f"Missing {name}")
    return value


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def raw_ecdsa(der: bytes) -> bytes:
    # OpenSSL emits ASN.1 DER; JWT ES256 requires fixed-width R || S.
    if len(der) < 8 or der[0] != 0x30 or der[1] != len(der) - 2:
        raise ValueError("Invalid ECDSA signature")
    position = 2
    integers = []
    for _ in range(2):
        if position + 2 > len(der) or der[position] != 0x02:
            raise ValueError("Invalid ECDSA integer")
        length = der[position + 1]
        position += 2
        number = der[position:position + length]
        if len(number) != length or not number:
            raise ValueError("Invalid ECDSA integer length")
        integers.append(int.from_bytes(number, "big").to_bytes(32, "big"))
        position += length
    if position != len(der):
        raise ValueError("Trailing ECDSA signature data")
    return b"".join(integers)


def token() -> str:
    key_id = require("ASC_KEY_ID")
    issuer = require("ASC_ISSUER_ID")
    key_path = require("ASC_KEY_PATH")
    if not Path(key_path).is_file():
        raise ValueError("ASC private key file is missing")
    now = int(time.time())
    header = b64(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}, separators=(",", ":")).encode())
    claims = {"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    payload = b64(json.dumps(claims, separators=(",", ":")).encode())
    message = f"{header}.{payload}"
    der = subprocess.check_output(["openssl", "dgst", "-sha256", "-sign", key_path], input=message.encode())
    return f"{message}.{b64(raw_ecdsa(der))}"


def request(path: str, method: str = "GET", body: dict | None = None) -> dict:
    data = None if body is None else json.dumps(body, separators=(",", ":")).encode()
    req = urllib.request.Request(
        HOST + path,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token()}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=30) as response:
        return json.load(response) if response.status != 204 else {}


def one(items: list, description: str) -> dict:
    if len(items) != 1:
        raise ValueError(f"Expected exactly one {description}, found {len(items)}")
    return items[0]


def app_and_group() -> tuple[str, str]:
    apps = request("/apps?" + urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID, "limit": 2}))
    app = one(apps["data"], "matching App Store Connect app")
    app_id = app["id"]
    group_id = require("ASC_INTERNAL_GROUP_ID")
    group = request(f"/betaGroups/{group_id}")["data"]
    attributes = group["attributes"]
    if attributes.get("isInternalGroup") is not True:
        raise ValueError("Selected beta group is not internal")
    if attributes.get("hasAccessToAllBuilds") is not False or attributes.get("publicLinkEnabled") is True:
        raise ValueError("Selected beta group must use explicit assignment without a public link")
    relationship = request(f"/betaGroups/{group_id}/relationships/app")["data"]
    if relationship["id"] != app_id:
        raise ValueError("Selected beta group belongs to another app")
    testers = request(f"/betaGroups/{group_id}/betaTesters?limit=200")
    tester_id = require("ASC_INTERNAL_TESTER_ID")
    if (len(testers["data"]) != 1 or testers["data"][0]["id"] != tester_id
            or testers.get("links", {}).get("next")):
        raise ValueError("Internal group membership differs from the authorised sole tester")
    return app_id, group_id


def matching_builds(app_id: str, version: str, build: str) -> list:
    query = urllib.parse.urlencode({"filter[app]": app_id, "filter[version]": build, "limit": 200})
    response = request("/builds?" + query)
    if response.get("links", {}).get("next"):
        raise ValueError("Build lookup is paginated; cannot prove uniqueness")
    matches = []
    for item in response["data"]:
        prerelease = request(f"/builds/{item['id']}/preReleaseVersion")["data"]
        if prerelease["attributes"]["version"] == version:
            matches.append(item)
    return matches


def preflight(version: str, build: str) -> None:
    app_id, _ = app_and_group()
    if matching_builds(app_id, version, build):
        raise ValueError("Version/build already exists in App Store Connect")
    print(f"PASS: existing app {app_id}, sole-tester internal group, fresh {version} ({build})")


def processed(version: str, build: str) -> None:
    app_id, group_id = app_and_group()
    deadline = time.monotonic() + 60 * 60
    selected = None
    while time.monotonic() < deadline:
        matches = matching_builds(app_id, version, build)
        if len(matches) > 1:
            raise ValueError("More than one matching build appeared")
        if matches:
            selected = matches[0]
            state = selected["attributes"].get("processingState")
            if state in ("FAILED", "INVALID"):
                raise ValueError(f"Apple processing ended with {state}")
            if state == "VALID":
                break
        time.sleep(60)
    else:
        raise ValueError("Apple processing timed out; inspect the existing upload before any retry")
    if selected["attributes"].get("buildAudienceType") != "INTERNAL_ONLY":
        raise ValueError("Processed build is not restricted to internal testing")
    detail = request(f"/builds/{selected['id']}/buildBetaDetail")["data"]
    internal_state = detail["attributes"].get("internalBuildState")
    if internal_state not in ("READY_FOR_BETA_TESTING", "IN_BETA_TESTING"):
        raise ValueError(f"Internal TestFlight state is {internal_state}; resolve compliance before assignment")
    request(
        f"/builds/{selected['id']}/relationships/betaGroups",
        "POST",
        {"data": [{"type": "betaGroups", "id": group_id}]},
    )
    for attempt in range(12):
        assigned = request(f"/betaGroups/{group_id}/builds?limit=200")
        if assigned.get("links", {}).get("next"):
            raise ValueError("Group build lookup is paginated; cannot prove assignment")
        if selected["id"] in {item["id"] for item in assigned["data"]}:
            break
        if attempt == 11:
            raise ValueError("Group assignment was not observable after read-only polling")
        time.sleep(10)
    print(f"PASS: processed build {selected['id']} is internal-only and assigned to sole-tester group {group_id}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["preflight", "processed"])
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    args = parser.parse_args()
    try:
        if args.command == "preflight":
            preflight(args.version, args.build)
        else:
            processed(args.version, args.build)
    except Exception as error:
        # Never print HTTP response bodies: Apple can return sensitive account data.
        print(f"FAIL: {type(error).__name__}: {error if isinstance(error, ValueError) else 'App Store Connect request failed'}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
