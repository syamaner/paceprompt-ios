#!/usr/bin/env python3
"""Deterministic checks for the production target's release metadata."""

import json
import plistlib
import re
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "PacePrompt.xcodeproj/project.pbxproj"
MANIFEST = ROOT / "PacePrompt/PrivacyInfo.xcprivacy"
ENTITLEMENTS = ROOT / "PacePrompt/PacePrompt.entitlements"
SCHEME = ROOT / "PacePrompt.xcodeproj/xcshareddata/xcschemes/PacePrompt.xcscheme"
APP_ICON = ROOT / "PacePrompt/Assets.xcassets/AppIcon.appiconset/Contents.json"


def verify() -> None:
    project = PROJECT.read_text()
    manifest = plistlib.loads(MANIFEST.read_bytes())
    entitlements = plistlib.loads(ENTITLEMENTS.read_bytes())
    scheme = ET.parse(SCHEME).getroot()
    icon = json.loads(APP_ICON.read_text())

    accessed = {
        entry["NSPrivacyAccessedAPIType"]: entry["NSPrivacyAccessedAPITypeReasons"]
        for entry in manifest["NSPrivacyAccessedAPITypes"]
    }
    assert accessed == {
        "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
        "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
    }
    assert manifest["NSPrivacyCollectedDataTypes"] == [
        {
            "NSPrivacyCollectedDataType": "NSPrivacyCollectedDataTypeOtherUserContent",
            "NSPrivacyCollectedDataTypeLinked": True,
            "NSPrivacyCollectedDataTypeTracking": False,
            "NSPrivacyCollectedDataTypePurposes": [
                "NSPrivacyCollectedDataTypePurposeAppFunctionality"
            ],
        },
        {
            "NSPrivacyCollectedDataType": "NSPrivacyCollectedDataTypeUserID",
            "NSPrivacyCollectedDataTypeLinked": True,
            "NSPrivacyCollectedDataTypeTracking": False,
            "NSPrivacyCollectedDataTypePurposes": [
                "NSPrivacyCollectedDataTypePurposeAppFunctionality"
            ],
        },
    ]
    assert manifest["NSPrivacyTracking"] is False
    assert manifest["NSPrivacyTrackingDomains"] == []
    assert project.count("PrivacyInfo.xcprivacy in Resources") == 2
    assert project.count("/* PrivacyInfo.xcprivacy */") == 3

    assert entitlements == {"com.apple.developer.healthkit": True}
    assert project.count("CODE_SIGN_ENTITLEMENTS = PacePrompt/PacePrompt.entitlements;") == 2
    assert project.count("PRODUCT_BUNDLE_IDENTIFIER = com.otherweather.PromptPace;") == 2
    assert project.count("TARGETED_DEVICE_FAMILY = 1;") >= 2
    assert "INFOPLIST_KEY_NSHealthShareUsageDescription" not in project
    assert project.count("INFOPLIST_KEY_NSHealthUpdateUsageDescription") == 2
    bluetooth_purpose = (
        "PacePrompt uses Bluetooth to connect to your treadmill and request speed "
        "and inclination targets during a workout you begin at its physical console."
    )
    assert project.count(
        f'INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription = "{bluetooth_purpose}";'
    ) == 2

    release_blocks = re.findall(
        r"AA000000000000000000A10[12] /\* (?:Debug|Release) \*/ = \{.*?\n\t\t\};",
        project,
        re.DOTALL,
    )
    assert len(release_blocks) == 2
    versions = {
        (
            re.search(r"MARKETING_VERSION = ([^;]+);", block).group(1),
            re.search(r"CURRENT_PROJECT_VERSION = ([^;]+);", block).group(1),
        )
        for block in release_blocks
    }
    assert len(versions) == 1
    marketing_version, build_version = versions.pop()
    assert re.fullmatch(r"\d+(?:\.\d+){1,2}", marketing_version)
    assert int(build_version) > 0

    archive_action = scheme.find("ArchiveAction")
    assert archive_action is not None
    assert archive_action.attrib["buildConfiguration"] == "Release"
    production_entry = scheme.find("./BuildAction/BuildActionEntries/BuildActionEntry")
    assert production_entry is not None
    assert production_entry.attrib["buildForArchiving"] == "YES"

    images = icon["images"]
    assert len(images) == 1
    assert images[0]["idiom"] == "universal"
    assert images[0]["platform"] == "ios"
    assert images[0]["size"] == "1024x1024"
    assert (APP_ICON.parent / images[0]["filename"]).is_file()

    print(
        "PASS: production release metadata, archive scheme, HealthKit entitlement, "
        f"privacy manifest and app icon (version {marketing_version} build {build_version})"
    )


if __name__ == "__main__":
    verify()
