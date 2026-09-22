from __future__ import annotations

import asyncio
import json
import os
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest
from unittest.mock import patch

from paceprompt_eval import sol_comparison
from paceprompt_eval.v3 import strict_json_load


PARAMETERS = [
    "max_tokens", "response_format", "structured_outputs", "reasoning",
]


def fake_catalogue(url: str) -> bytes:
    if url == "https://openrouter.ai/api/v1/models":
        result = {"data": [
            {"id": model_id, "canonical_slug": revision}
            for model_id, revision in (
                ("openai/gpt-5.6-sol", "openai/gpt-5.6-sol-20260709"),
                ("openai/gpt-6-sol", "openai/gpt-6-sol-20260922"),
            )
        ]}
    else:
        result = {"data": {"endpoints": [{
            "provider_name": "OpenAI",
            "tag": "openai",
            "quantization": "unknown",
            "pricing": {"prompt": "0.000002", "completion": "0.00001"},
            "supported_parameters": PARAMETERS,
        }]}}
    return json.dumps(result).encode("utf-8")


class SolComparisonTests(unittest.TestCase):
    def test_profile_and_queue_are_pinned_and_balanced(self) -> None:
        report = sol_comparison.verify()
        self.assertEqual(report["status"], "valid", report["errors"])
        self.assertEqual((report["modelCount"], report["caseCount"]), (2, 109))
        queue = sol_comparison.queue_document()
        self.assertEqual(len(queue["entries"]), 218)
        self.assertEqual(len({item["attemptID"] for item in queue["entries"]}), 218)
        positions = {
            model: [item["modelPosition"] for item in queue["entries"] if item["modelID"] == model]
            for model in sol_comparison.EXPECTED_MODELS
        }
        self.assertEqual({len(value) for value in positions.values()}, {109})
        self.assertEqual(
            queue["queueSha256"], sol_comparison.queue_document()["queueSha256"]
        )

    def test_zero_spend_gate_rechecks_payloads_and_budget(self) -> None:
        with TemporaryDirectory() as directory:
            root = Path(directory)

            def safe_run_dir(run_id: str, *, create: bool) -> Path:
                path = root / run_id
                if create:
                    path.mkdir()
                return path

            with patch.object(sol_comparison, "safe_run_dir", side_effect=safe_run_dir), patch.dict(
                os.environ, {"OPENROUTER_API_KEY": "must-not-be-read"}
            ):
                gate = asyncio.run(sol_comparison.prepare_gate(fetch=fake_catalogue))
                run_dir = root / sol_comparison.RUN_ID
                self.assertEqual(gate["status"], "awaitingProfileAndSpendingLimitRatification")
                self.assertEqual(gate["costPreflight"]["estimatedUSD"], "25.080060")
                self.assertFalse(gate["credentialRead"])
                self.assertNotIn("must-not-be-read", str(gate))
                sol_comparison.validate_gate(run_dir, gate, status=gate["status"])
                sealed = sol_comparison.seal_gate(sol_comparison.RUN_ID, "26.00")
                self.assertEqual(sealed["status"], "awaitingExactLiveAuthorization")
                sol_comparison.validate_gate(run_dir, sealed, status=sealed["status"])
                with self.assertRaises(RuntimeError):
                    asyncio.run(sol_comparison.run_live(
                        run_id=sol_comparison.RUN_ID,
                        authorization="wrong",
                        spending_limit_usd="26.00",
                    ))
                path = run_dir / "mock-payloads" / "openai--gpt-6-sol.json"
                value = strict_json_load(path)
                value["body"]["model"] = "another-model"
                path.write_text(json.dumps(value), encoding="utf-8")
                with self.assertRaises(RuntimeError):
                    sol_comparison.validate_gate(run_dir, sealed, status=sealed["status"])


if __name__ == "__main__":
    unittest.main()
