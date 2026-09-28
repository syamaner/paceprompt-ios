#!/usr/bin/env python3
"""Check the closed Watch target boundary and narrow privacy/build declarations."""
import plistlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def verify():
    project = (ROOT / 'PacePrompt.xcodeproj/project.pbxproj').read_text()
    refs = dict(re.findall(r'([A-F0-9]{24})(?: /\*.*?\*/)? = \{isa = PBXFileReference;[^\n]*?path = ([^;]+);', project))
    builds = dict(re.findall(r'([A-F0-9]{24})(?: /\*.*?\*/)? = \{isa = PBXBuildFile; fileRef = ([A-F0-9]{24})', project))
    phase = re.search(r'D11500000000000000000600 /\* Watch Sources \*/ = .*?files = \((.*?)\);', project).group(1)
    sources = {refs[builds[item]] for item in re.findall(r'[A-F0-9]{24}', phase)}
    expected = {str(p.relative_to(ROOT)) for folder in ('Shared/WatchInterchange', 'PacePromptWatch') for p in (ROOT / folder).glob('*.swift')}
    # Phone lifecycle is pure, but not needed in the Watch target.
    assert sources == expected | {'PacePrompt/Import/StrictImportJSON.swift'}, sources ^ expected
    for path in sources:
        text = (ROOT / path).read_text()
        assert not re.search(r'CoreBluetooth|FTMS|WorkoutExecution|WatchConnectivity|HKHealthStore\(\)\.save', text), path
        if path.startswith('Shared/'):
            assert set(re.findall(r'^import (\w+)', text, re.M)) <= {'Foundation'}, path
    phone = (ROOT / 'PacePrompt/Watch/PhoneWatchSessionAdapter.swift').read_text()
    assert not re.search(r'HK(?:Live)?WorkoutBuilder|finishWorkout|\.save\(', phone)
    assert 'WatchCallbackIdentity.accepts(workoutSession' in phone
    native = (ROOT / 'PacePromptWatch/WatchHealthKitAdapter.swift').read_text()
    assert 'WatchCallbackIdentity.accepts(workoutSession' in native
    assert 'WatchCallbackIdentity.accepts(workoutBuilder' in native
    assert 'source.disableCollection(for: Self.distance)' in native
    assert native.index('source.disableCollection(for: Self.distance)') < native.index('builder.dataSource = source')
    assert 'D11500000000000000000602 /* Embed Watch Content */' in project
    assert project.count('WATCHOS_DEPLOYMENT_TARGET = 10.0;') == 2
    assert project.count('PRODUCT_BUNDLE_IDENTIFIER = com.otherweather.PromptPace.watchkitapp;') == 2
    info = plistlib.loads((ROOT / 'PacePromptWatch/Info.plist').read_bytes())
    assert info['WKApplication'] is True
    assert info['WKCompanionAppBundleIdentifier'] == 'com.otherweather.PromptPace'
    assert info['WKBackgroundModes'] == ['workout-processing']
    assert info['ITSAppUsesNonExemptEncryption'] is False
    assert 'heart rate' in info['NSHealthShareUsageDescription']
    assert 'discarded' in info['NSHealthUpdateUsageDescription']
    assert plistlib.loads((ROOT / 'PacePromptWatch/PacePromptWatch.entitlements').read_bytes()) == {'com.apple.developer.healthkit': True}
    privacy = plistlib.loads((ROOT / 'PacePromptWatch/PrivacyInfo.xcprivacy').read_bytes())
    assert privacy['NSPrivacyTracking'] is False and privacy['NSPrivacyTrackingDomains'] == []
    assert privacy['NSPrivacyCollectedDataTypes'] == []
    assert privacy['NSPrivacyAccessedAPITypes'] == [{'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategorySystemBootTime', 'NSPrivacyAccessedAPITypeReasons': ['35F9.1']}]
    print('PASS: Watch target has no treadmill command dependency; narrow HealthKit/privacy declarations and iPhone writer exclusion')


if __name__ == '__main__':
    verify()
