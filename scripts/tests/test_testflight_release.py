"""Synthetic release-policy checks; only a temporary ad hoc signature on macOS."""

import importlib.util
import base64
import datetime as dt
import hashlib
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]


def module(name: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


guard = module("testflight_guard")
api = module("testflight_api")
signing = module("testflight_signing")
PROJECT = (ROOT / "PacePrompt.xcodeproj/project.pbxproj").read_text()


class ReleaseGuardTests(unittest.TestCase):
    def test_signed_entitlements_reject_human_readable_codesign_output(self):
        with patch.object(guard.subprocess, "check_output", return_value=b"[Dict]\n"):
            with self.assertRaisesRegex(ValueError, "not a property list"):
                guard.signed_entitlements(Path("Synthetic.app"))

    @unittest.skipUnless(sys.platform == "darwin", "requires macOS codesign")
    def test_signed_entitlements_are_parsed_as_plist_on_macos(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "Synthetic.app"
            executable = app / "Contents/MacOS/Synthetic"
            executable.parent.mkdir(parents=True)
            executable.write_bytes(Path("/bin/echo").read_bytes())
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "test.paceprompt.synthetic",
                "CFBundleExecutable": "Synthetic",
                "CFBundlePackageType": "APPL",
            }))
            entitlements = Path(temporary) / "entitlements.plist"
            entitlements.write_bytes(plistlib.dumps({
                "com.apple.developer.healthkit": True, "get-task-allow": False,
            }))
            subprocess.run(["codesign", "-s", "-", "--force", "--entitlements",
                            str(entitlements), str(app)], check=True, capture_output=True)
            self.assertEqual(guard.signed_entitlements(app), {
                "com.apple.developer.healthkit": True, "get-task-allow": False,
            })

    def test_exported_signer_must_match_approved_ci_identity(self):
        approved = b"synthetic approved certificate"
        mismatched = b"different team-certificate leaf"
        fingerprint = hashlib.sha1(approved).hexdigest().upper()
        with tempfile.TemporaryDirectory() as temporary:
            app = Path(temporary) / "PacePrompt.app"
            app.mkdir()

            def extract(command, **_kwargs):
                self.assertEqual(command[:2], ["codesign", "-d"])
                self.assertEqual(len(command), 4)
                self.assertTrue(command[2].startswith("--extract-certificates="))
                Path(command[2].split("=", 1)[1] + "0").write_bytes(mismatched)

            with patch.object(guard.subprocess, "run", side_effect=extract) as invoked:
                with self.assertRaisesRegex(ValueError, "Signed app certificate differs"):
                    guard.verify_signing_leaf(app, fingerprint)
                self.assertEqual(invoked.call_count, 1)

    def test_missing_extracted_certificate_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(guard.subprocess, "run"):
                with self.assertRaisesRegex(ValueError, "was not extracted"):
                    guard.verify_signing_leaf(Path(temporary) / "Synthetic.app", "A" * 40)

    @unittest.skipUnless(sys.platform == "darwin", "requires macOS codesign")
    def test_certificate_extract_option_is_accepted_by_macos(self):
        with tempfile.TemporaryDirectory() as temporary:
            subprocess.run(["codesign", "-d", f"--extract-certificates={temporary}/leaf",
                            "/usr/bin/codesign"], check=True, capture_output=True)

    def test_manual_signing_profile_accepts_only_matching_app_store_identity(self):
        team = "ABCDEFGHIJ"
        certificate = b"synthetic DER certificate"
        fingerprint = hashlib.sha1(certificate).hexdigest().upper()
        identities = f'  1) {fingerprint} "Apple Distribution: CI ({team})"'
        profile = {
            "TeamIdentifier": [team], "ApplicationIdentifierPrefix": [team],
            "Platform": ["iOS"], "UUID": "12345678-1234-1234-1234-123456789abc",
            "Name": "PacePrompt CI App Store",
            "ExpirationDate": dt.datetime(2030, 1, 1),
            "DeveloperCertificates": [certificate],
            "Entitlements": {
                "application-identifier": f"{team}.com.otherweather.PromptPace",
                "com.apple.developer.team-identifier": team,
                "com.apple.developer.healthkit": True,
                "get-task-allow": False,
            },
        }
        now = dt.datetime(2026, 9, 17, tzinfo=dt.timezone.utc)
        self.assertEqual(signing.validate(profile, identities, team, now)["certificate_sha1"], fingerprint)
        invalid = [
            {**profile, "TeamIdentifier": ["WRONGTEAM0"]},
            {**profile, "Platform": ["macOS"]},
            {**profile, "ProvisionedDevices": ["device"]},
            {**profile, "ProvisionsAllDevices": True},
            {**profile, "ExpirationDate": dt.datetime(2020, 1, 1)},
            {**profile, "DeveloperCertificates": [b"different"]},
            {**profile, "Entitlements": {**profile["Entitlements"], "application-identifier": "other.app"}},
            {**profile, "Entitlements": {**profile["Entitlements"], "com.apple.developer.healthkit": False}},
            {**profile, "Entitlements": {**profile["Entitlements"], "get-task-allow": True}},
        ]
        for changed in invalid:
            with self.subTest(changed=changed), self.assertRaises(ValueError):
                signing.validate(changed, identities, team, now)
        with self.assertRaisesRegex(ValueError, "identity"):
            signing.validate(profile, "0 valid identities found", team, now)

    def test_current_source_matches_fresh_tag(self):
        self.assertEqual(guard.check_tag("testflight/1.0-b6", PROJECT), ("1.0", "6"))

    def test_rejects_wrong_tag_or_build(self):
        for tag in ("testflight/1.0-b5", "testflight/1.1-b6", "testflight/1.0-b06",
                    "testflight/1.0-b0", "testflight/1.0-b6/extra", "release/1.0-b6"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                guard.check_tag(tag, PROJECT)

    def test_rejects_release_debug_mismatch_and_bundle_change(self):
        with self.assertRaises(ValueError):
            guard.check_tag("testflight/1.0-b6", PROJECT.replace("CURRENT_PROJECT_VERSION = 6;", "CURRENT_PROJECT_VERSION = 5;", 1))
        with self.assertRaises(ValueError):
            guard.check_tag("testflight/1.0-b6", PROJECT.replace("PRODUCT_BUNDLE_IDENTIFIER = com.otherweather.PromptPace;", "PRODUCT_BUNDLE_IDENTIFIER = other.app;", 1))

    def test_rejects_missing_purpose_and_changed_version(self):
        info = {
            "CFBundleIdentifier": guard.BUNDLE_ID,
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "6",
            "ITSAppUsesNonExemptEncryption": False,
            "NSBluetoothAlwaysUsageDescription": "PacePrompt uses Bluetooth to connect to your treadmill and request speed and inclination targets during a workout you begin at its physical console.",
            "NSHealthShareUsageDescription": "PacePrompt does not read Apple Health data. It only asks to save a completed workout and optional distance when you choose Save to Apple Health.",
            "NSHealthUpdateUsageDescription": "PacePrompt saves a completed indoor workout and optional treadmill distance to Apple Health only when you choose Save to Apple Health.",
        }
        guard.metadata(info, "1.0", "6")
        for invalid in ("NO", 0, True):
            with self.subTest(encryption=invalid), self.assertRaises(ValueError):
                guard.metadata({**info, "ITSAppUsesNonExemptEncryption": invalid}, "1.0", "6")
        for key in info:
            changed = dict(info)
            del changed[key]
            with self.subTest(key=key), self.assertRaises(ValueError):
                guard.metadata(changed, "1.0", "6")

    def test_der_signature_conversion(self):
        r = b"\x01" * 32
        s = b"\x02" * 32
        der = b"\x30\x44\x02\x20" + r + b"\x02\x20" + s
        self.assertEqual(api.raw_ecdsa(der), r + s)
        with self.assertRaises(ValueError):
            api.raw_ecdsa(der + b"\x00")

    def test_team_token_has_issuer_claim(self):
        der = b"\x30\x44\x02\x20" + b"\x01" * 32 + b"\x02\x20" + b"\x02" * 32
        with tempfile.NamedTemporaryFile() as key:
            values = {"ASC_KEY_ID": "ABCDEFGHIJ", "ASC_KEY_PATH": key.name,
                      "ASC_ISSUER_ID": "issuer"}
            with patch.dict(os.environ, values), \
                 patch.object(api.subprocess, "check_output", return_value=der):
                payload = api.token().split(".")[1]
                claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
                self.assertEqual(claims["iss"], "issuer")
                self.assertNotIn("sub", claims)

    def test_duplicate_build_never_reaches_upload(self):
        with patch.object(api, "app_and_group", return_value=("app-1", "group-1")), \
             patch.object(api, "matching_builds", return_value=[{"id": "existing"}]):
            with self.assertRaisesRegex(ValueError, "already exists"):
                api.preflight("1.0", "6")

    def test_internal_group_rejects_changed_tester(self):
        answers = [
            {"data": [{"id": "app-1"}]},
            {"data": {"attributes": {"isInternalGroup": True, "hasAccessToAllBuilds": False}}},
            {"data": {"id": "app-1"}},
            {"data": [{"id": "other-tester"}]},
        ]
        with patch.dict(os.environ, {"ASC_INTERNAL_GROUP_ID": "group-1", "ASC_INTERNAL_TESTER_ID": "authorised-tester"}), \
             patch.object(api, "request", side_effect=answers):
            with self.assertRaisesRegex(ValueError, "membership differs"):
                api.app_and_group()

    def test_missing_compliance_cannot_assign_group(self):
        build = {"id": "build-1", "attributes": {"processingState": "VALID", "buildAudienceType": "INTERNAL_ONLY"}}
        with patch.object(api, "app_and_group", return_value=("app-1", "group-1")), \
             patch.object(api, "matching_builds", return_value=[build]), \
             patch.object(api, "request", return_value={"data": {"attributes": {"internalBuildState": "MISSING_EXPORT_COMPLIANCE"}}}) as request:
            with self.assertRaisesRegex(ValueError, "compliance"):
                api.processed("1.0", "6")
            self.assertEqual(request.call_count, 1)

    def test_processed_build_assigns_only_selected_internal_group(self):
        build = {"id": "build-1", "attributes": {"processingState": "VALID", "buildAudienceType": "INTERNAL_ONLY"}}
        responses = [
            {"data": {"attributes": {"internalBuildState": "READY_FOR_BETA_TESTING"}}},
            {},
            {"data": [{"id": "group-1"}]},
        ]
        with patch.object(api, "app_and_group", return_value=("app-1", "group-1")), \
             patch.object(api, "matching_builds", return_value=[build]), \
             patch.object(api, "request", side_effect=responses) as request:
            api.processed("1.0", "6")
            self.assertEqual(request.call_args_list[1].args[1], "POST")
            self.assertEqual(request.call_args_list[1].args[2],
                             {"data": [{"type": "betaGroups", "id": "group-1"}]})

    def test_dry_run_has_no_apple_secrets_or_upload(self):
        workflow = (ROOT / ".github/workflows/internal-testflight.yml").read_text()
        source_job = workflow.split("  release:", 1)[0]
        self.assertNotIn("secrets.ASC_", source_job)
        self.assertNotIn("secrets.DIST_", source_job)
        self.assertNotIn("altool", source_job)
        self.assertNotIn("upload-artifact", workflow)
        self.assertIn("testFlightInternalTestingOnly': True", workflow)
        self.assertIn("manageAppVersionAndBuildNumber': False", workflow)
        self.assertIn('test "$GITHUB_RUN_ATTEMPT" = 1', workflow)
        self.assertIn("'signingStyle': 'manual'", workflow)
        self.assertNotIn("-allowProvisioningUpdates", workflow)

    def test_source_rejects_missing_exact_head_review(self):
        sha = "a" * 40
        def fake_git(*args):
            if args[:2] == ("rev-parse", "HEAD"):
                return sha
            if args[0] == "status":
                return ""
            if args[0] == "cat-file":
                return "commit"
            if args[0] == "rev-parse":
                return sha
            if args[0] == "ls-remote":
                return f"{sha}\trefs/tags/testflight/1.0-b6"
            if args[0] == "fetch":
                return ""
            if args[0] == "rev-list" and "--first-parent" in args:
                return sha
            if args[0] == "rev-list":
                return f"{sha} {'b' * 40} {'c' * 40}"
            if args[0] == "show":
                return "No review attestation"
            raise AssertionError(args)
        pull = {"merged_at": "2026-09-17T00:00:00Z", "merge_commit_sha": sha,
                "base": {"ref": "main"}, "head": {"sha": "c" * 40}}
        with patch.object(guard, "git", side_effect=fake_git), patch.object(guard, "api", return_value=[pull]):
            with self.assertRaisesRegex(ValueError, "attestation"):
                guard.source("testflight/1.0-b6", sha)


if __name__ == "__main__":
    unittest.main()
