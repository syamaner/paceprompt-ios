#!/usr/bin/env python3
"""Verify the production app bundle's effective background execution modes."""

import argparse
import plistlib
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("info_plist", type=Path)
    args = parser.parse_args()

    payload = plistlib.loads(args.info_plist.read_bytes())
    modes = payload.get("UIBackgroundModes")
    assert modes == ["bluetooth-central"], (
        "Built product must declare exactly the bluetooth-central background mode; "
        f"found {modes!r}"
    )
    print(f"PASS: {args.info_plist} declares only bluetooth-central")


if __name__ == "__main__":
    main()
