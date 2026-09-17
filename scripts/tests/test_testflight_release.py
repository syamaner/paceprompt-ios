"""Synthetic release-policy checks; no signing, secrets or uploads."""

import importlib.util
import base64
import json
import os
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
PROJECT = (ROOT / "PacePrompt.xcodeproj/project.pbxproj").read_text()


class ReleaseGuardTests(unittest.TestCase):
    def test_current_source_matches_fresh_tag(self):
        self.assertEqual(guard.check_tag("testflight/1.0-b2", PROJECT), ("1.0", "2"))

    def test_rejects_wrong_tag_or_build(self):
        for tag in ("testflight/1.0-b1", "testflight/1.1-b2", "testflight/1.0-b02",
                    "testflight/1.0-b0", "testflight/1.0-b2/extra", "release/1.0-b2"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                guard.check_tag(tag, PROJECT)

    def test_rejects_release_debug_mismatch_and_bundle_change(self):
        with self.assertRaises(ValueError):
            guard.check_tag("testflight/1.0-b2", PROJECT.replace("CURRENT_PROJECT_VERSION = 2;", "CURRENT_PROJECT_VERSION = 3;", 1))
        with self.assertRaises(ValueError):
            guard.check_tag("testflight/1.0-b2", PROJECT.replace("PRODUCT_BUNDLE_IDENTIFIER = com.otherweather.PromptPace;", "PRODUCT_BUNDLE_IDENTIFIER = other.app;", 1))

    def test_rejects_missing_purpose_and_changed_version(self):
        info = {
            "CFBundleIdentifier": guard.BUNDLE_ID,
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "2",
            "ITSAppUsesNonExemptEncryption": False,
            "NSBluetoothAlwaysUsageDescription": "PacePrompt uses Bluetooth to connect to your treadmill and request speed and inclination targets during a workout you begin at its physical console.",
            "NSHealthShareUsageDescription": "PacePrompt does not read Apple Health data. It only asks to save a completed workout and optional distance when you choose Save to Apple Health.",
            "NSHealthUpdateUsageDescription": "PacePrompt saves a completed indoor workout and optional treadmill distance to Apple Health only when you choose Save to Apple Health.",
        }
        guard.metadata(info, "1.0", "2")
        for invalid in ("NO", 0, True):
            with self.subTest(encryption=invalid), self.assertRaises(ValueError):
                guard.metadata({**info, "ITSAppUsesNonExemptEncryption": invalid}, "1.0", "2")
        for key in info:
            changed = dict(info)
            del changed[key]
            with self.subTest(key=key), self.assertRaises(ValueError):
                guard.metadata(changed, "1.0", "2")

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
                api.preflight("1.0", "2")

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
                api.processed("1.0", "2")
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
            api.processed("1.0", "2")
            self.assertEqual(request.call_args_list[1].args[1], "POST")
            self.assertEqual(request.call_args_list[1].args[2],
                             {"data": [{"type": "betaGroups", "id": "group-1"}]})

    def test_dry_run_has_no_apple_secrets_or_upload(self):
        workflow = (ROOT / ".github/workflows/internal-testflight.yml").read_text()
        source_job = workflow.split("  release:", 1)[0]
        self.assertNotIn("secrets.ASC_", source_job)
        self.assertNotIn("altool", source_job)
        self.assertNotIn("upload-artifact", workflow)
        self.assertIn("testFlightInternalTestingOnly': True", workflow)
        self.assertIn("manageAppVersionAndBuildNumber': False", workflow)
        self.assertIn('test "$GITHUB_RUN_ATTEMPT" = 1', workflow)

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
                return f"{sha}\trefs/tags/testflight/1.0-b2"
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
                guard.source("testflight/1.0-b2", sha)


if __name__ == "__main__":
    unittest.main()
