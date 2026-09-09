from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).parents[1] / "scripts" / "phase_usage.py"
MISSING = object()


def counter(
    input_tokens: int,
    cached_input_tokens: int,
    output_tokens: int,
    *,
    cache_write_input_tokens: int | object = MISSING,
    reasoning_output_tokens: int | object = MISSING,
) -> dict[str, int]:
    value = {
        "input_tokens": input_tokens,
        "cached_input_tokens": cached_input_tokens,
        "output_tokens": output_tokens,
        "total_tokens": input_tokens + output_tokens,
    }
    if cache_write_input_tokens is not MISSING:
        value["cache_write_input_tokens"] = cache_write_input_tokens
    if reasoning_output_tokens is not MISSING:
        value["reasoning_output_tokens"] = reasoning_output_tokens
    return value


def add_counters(left: dict[str, int], right: dict[str, int]) -> dict[str, int]:
    fields = set(left) | set(right)
    return {field: left.get(field, 0) + right.get(field, 0) for field in fields}


def session_records(
    requests: list[dict[str, int]], *, session_id: str = "synthetic-session"
) -> list[dict[str, object]]:
    records: list[dict[str, object]] = [
        {"type": "session_meta", "payload": {"id": session_id}},
        {"type": "turn_context", "payload": {"model": "gpt-test"}},
    ]
    cumulative: dict[str, int] = {
        "input_tokens": 0,
        "cached_input_tokens": 0,
        "output_tokens": 0,
        "total_tokens": 0,
    }
    optional_fields = (
        "cache_write_input_tokens",
        "reasoning_output_tokens",
    )
    for field in optional_fields:
        if requests and all(field in request for request in requests):
            cumulative[field] = 0
    for index, request in enumerate(requests, start=1):
        cumulative = add_counters(cumulative, request)
        records.append(
            {
                "timestamp": f"2026-09-03T10:00:{index:02d}Z",
                "type": "event_msg",
                "payload": {
                    "type": "token_count",
                    "info": {
                        "total_token_usage": dict(cumulative),
                        "last_token_usage": request,
                    },
                },
            }
        )
    return records


def session_records_with_reset() -> list[dict[str, object]]:
    before = session_records(
        [
            counter(10, 4, 1, cache_write_input_tokens=0, reasoning_output_tokens=0),
            counter(20, 5, 2, cache_write_input_tokens=0, reasoning_output_tokens=1),
        ]
    )
    after = session_records(
        [
            counter(7, 2, 1, cache_write_input_tokens=0, reasoning_output_tokens=0),
            counter(11, 3, 2, cache_write_input_tokens=0, reasoning_output_tokens=1),
        ]
    )[2:]
    for index, record in enumerate(after, start=3):
        record["timestamp"] = f"2026-09-03T10:00:{index:02d}Z"
    return [*before, *after]


class PhaseUsageTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.directory = Path(self.temporary.name)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_records(
        self, records: list[dict[str, object]], *, name: str = "session.jsonl"
    ) -> Path:
        path = self.directory / name
        path.write_text(
            "".join(json.dumps(record) + "\n" for record in records),
            encoding="utf-8",
        )
        return path

    def run_tool(self, *arguments: object) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), *(str(argument) for argument in arguments)],
            check=False,
            capture_output=True,
            text=True,
        )

    def report_arguments(self, session: Path) -> list[object]:
        return [
            "report",
            session,
            "--boundary-label",
            "synthetic acceptance boundary",
            "--included-agent",
            "synthetic root",
            "--included-channel",
            "synthetic session",
            "--excluded-channel",
            "no subagents supplied",
            "--json",
        ]

    def pricing_arguments(self) -> list[object]:
        return [
            "--model",
            "gpt-test",
            "--pricing-date",
            "2026-09-03",
            "--pricing-source",
            "synthetic ledger rates",
            "--currency",
            "USD",
            "--uncached-input-rate",
            "4",
            "--cached-input-rate",
            "0.4",
            "--output-rate",
            "20",
            "--long-context-threshold",
            "2000000",
        ]

    def test_whole_session_reports_known_usage_and_boundary_metadata(self) -> None:
        session = self.write_records(
            session_records(
                [
                    counter(100, 40, 10, cache_write_input_tokens=0, reasoning_output_tokens=4),
                    counter(200, 150, 20, cache_write_input_tokens=0, reasoning_output_tokens=8),
                ]
            )
        )
        completed = self.run_tool(*self.report_arguments(session))
        self.assertEqual(completed.returncode, 0, completed.stderr)
        report = json.loads(completed.stdout)
        self.assertEqual(report["boundary"]["mode"], "whole-session")
        self.assertEqual(report["session_id"], "synthetic-session")
        self.assertEqual(report["included_agents"], ["synthetic root"])
        self.assertEqual(report["usage"]["input_tokens"], 300)
        self.assertEqual(report["usage"]["cached_input_tokens"], 190)
        self.assertEqual(report["usage"]["uncached_input_tokens"], 110)
        self.assertEqual(report["usage"]["output_tokens"], 30)
        self.assertEqual(report["usage"]["reasoning_output_tokens"], 12)
        self.assertEqual(report["usage"]["total_tokens"], 330)
        self.assertEqual(report["requests"]["input_tokens"], [100, 200])

    def test_snapshot_and_exact_delta_use_the_captured_event(self) -> None:
        session = self.write_records(
            session_records(
                [
                    counter(10, 4, 2, cache_write_input_tokens=0, reasoning_output_tokens=1),
                    counter(20, 5, 3, cache_write_input_tokens=2, reasoning_output_tokens=1),
                    counter(30, 6, 4, cache_write_input_tokens=1, reasoning_output_tokens=2),
                ]
            )
        )
        baseline = self.directory / "baseline.json"
        captured = self.run_tool(
            "snapshot", session, "--token-count-event", 1, "--output", baseline
        )
        self.assertEqual(captured.returncode, 0, captured.stderr)
        arguments = self.report_arguments(session)
        arguments[2:2] = ["--baseline", baseline]
        completed = self.run_tool(*arguments)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        report = json.loads(completed.stdout)
        self.assertEqual(report["boundary"]["mode"], "delta")
        self.assertEqual(report["boundary"]["start"]["token_count_event"], 1)
        self.assertEqual(report["usage"]["input_tokens"], 50)
        self.assertEqual(report["usage"]["cached_input_tokens"], 11)
        self.assertEqual(report["usage"]["cache_write_input_tokens"], 3)
        self.assertEqual(report["usage"]["output_tokens"], 7)
        self.assertEqual(report["usage"]["reasoning_output_tokens"], 3)
        self.assertEqual(report["usage"]["total_tokens"], 57)
        self.assertEqual(report["requests"]["count"], 2)

    def test_snapshot_rejects_zero_event_instead_of_moving_to_latest(self) -> None:
        session = self.write_records(session_records([counter(10, 4, 2)]))
        completed = self.run_tool(
            "snapshot",
            session,
            "--token-count-event",
            0,
            "--output",
            self.directory / "baseline.json",
        )
        self.assertEqual(completed.returncode, 2)
        self.assertIn("outside the available range", completed.stderr)

    def test_historical_reset_before_baseline_is_reported_and_allowed(self) -> None:
        session = self.write_records(session_records_with_reset())
        latest_baseline = self.directory / "latest-baseline.json"
        latest = self.run_tool(
            "snapshot", session, "--output", latest_baseline
        )
        self.assertEqual(latest.returncode, 0, latest.stderr)
        self.assertEqual(json.loads(latest.stdout)["token_count_event"], 4)

        baseline = self.directory / "baseline.json"
        captured = self.run_tool(
            "snapshot", session, "--token-count-event", 3, "--output", baseline
        )
        self.assertEqual(captured.returncode, 0, captured.stderr)
        snapshot = json.loads(captured.stdout)
        self.assertEqual(
            snapshot["historical_counter_resets"],
            [
                {
                    "decreased_counters": [
                        "input_tokens",
                        "cached_input_tokens",
                        "output_tokens",
                        "total_tokens",
                        "reasoning_output_tokens",
                    ],
                    "previous_token_count_event": 2,
                    "timestamp": "2026-09-03T10:00:03Z",
                    "token_count_event": 3,
                }
            ],
        )

        arguments = self.report_arguments(session)
        arguments[2:2] = ["--baseline", baseline]
        completed = self.run_tool(*arguments)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        report = json.loads(completed.stdout)
        self.assertEqual(report["usage"]["input_tokens"], 11)
        self.assertEqual(report["usage"]["cached_input_tokens"], 3)
        self.assertEqual(report["usage"]["output_tokens"], 2)
        self.assertEqual(report["usage"]["total_tokens"], 13)
        self.assertEqual(report["requests"]["count"], 1)
        self.assertEqual(
            report["boundary"]["historical_counter_resets"],
            snapshot["historical_counter_resets"],
        )

    def test_snapshot_and_report_measure_exact_reset_inside_boundary(self) -> None:
        session = self.write_records(session_records_with_reset())
        baseline = self.directory / "baseline.json"
        captured = self.run_tool(
            "snapshot",
            session,
            "--token-count-event",
            2,
            "--output",
            baseline,
        )
        self.assertEqual(captured.returncode, 0, captured.stderr)
        arguments = self.report_arguments(session)
        arguments[2:2] = ["--baseline", baseline]
        completed = self.run_tool(*arguments)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        report = json.loads(completed.stdout)
        self.assertEqual(report["usage"]["input_tokens"], 18)
        self.assertEqual(report["usage"]["cached_input_tokens"], 5)
        self.assertEqual(report["usage"]["output_tokens"], 3)
        self.assertEqual(report["usage"]["total_tokens"], 21)
        self.assertEqual(report["requests"]["count"], 2)
        self.assertEqual(
            report["boundary"]["counter_resets_inside_boundary"],
            [
                {
                    "decreased_counters": [
                        "input_tokens",
                        "cached_input_tokens",
                        "output_tokens",
                        "total_tokens",
                        "reasoning_output_tokens",
                    ],
                    "previous_token_count_event": 2,
                    "timestamp": "2026-09-03T10:00:03Z",
                    "token_count_event": 3,
                }
            ],
        )

    def test_whole_session_measures_complete_exact_epochs_across_reset(self) -> None:
        session = self.write_records(session_records_with_reset())
        completed = self.run_tool(*self.report_arguments(session))
        self.assertEqual(completed.returncode, 0, completed.stderr)
        report = json.loads(completed.stdout)
        self.assertEqual(report["usage"]["input_tokens"], 48)
        self.assertEqual(report["usage"]["cached_input_tokens"], 14)
        self.assertEqual(report["usage"]["output_tokens"], 6)
        self.assertEqual(report["usage"]["total_tokens"], 54)
        self.assertEqual(report["requests"]["count"], 4)

    def test_reset_inside_boundary_requires_exact_new_epoch_anchor(self) -> None:
        records = session_records_with_reset()
        reset_total = records[4]["payload"]["info"]["total_token_usage"]
        reset_total["input_tokens"] += 1
        reset_total["total_tokens"] += 1
        session = self.write_records(records)
        baseline = self.directory / "baseline.json"
        captured = self.run_tool(
            "snapshot", session, "--token-count-event", 2, "--output", baseline
        )
        self.assertEqual(captured.returncode, 0, captured.stderr)
        arguments = self.report_arguments(session)
        arguments[2:2] = ["--baseline", baseline]
        completed = self.run_tool(*arguments)
        self.assertEqual(completed.returncode, 2)
        self.assertIn(
            "counter reset 2->3 does not establish an exact cumulative epoch anchor",
            completed.stderr,
        )

    def test_missing_optional_counters_are_distinct_from_reported_zero(self) -> None:
        missing_session = self.write_records(
            session_records([counter(10, 5, 1)]), name="missing.jsonl"
        )
        zero_session = self.write_records(
            session_records(
                [counter(10, 5, 1, cache_write_input_tokens=0, reasoning_output_tokens=0)]
            ),
            name="zero.jsonl",
        )
        missing = self.run_tool(*self.report_arguments(missing_session))
        zero = self.run_tool(*self.report_arguments(zero_session))
        self.assertEqual(missing.returncode, 0, missing.stderr)
        self.assertEqual(zero.returncode, 0, zero.stderr)
        missing_usage = json.loads(missing.stdout)["usage"]
        zero_usage = json.loads(zero.stdout)["usage"]
        self.assertIsNone(missing_usage["cache_write_input_tokens"])
        self.assertIsNone(missing_usage["reasoning_output_tokens"])
        self.assertEqual(zero_usage["cache_write_input_tokens"], 0)
        self.assertEqual(zero_usage["reasoning_output_tokens"], 0)

    def test_reasoning_is_not_added_to_total_or_priced_twice(self) -> None:
        session = self.write_records(
            session_records(
                [
                    counter(
                        0,
                        0,
                        100_000,
                        cache_write_input_tokens=0,
                        reasoning_output_tokens=40_000,
                    )
                ]
            )
        )
        completed = self.run_tool(
            *self.report_arguments(session), *self.pricing_arguments()
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        report = json.loads(completed.stdout)
        self.assertEqual(report["usage"]["total_tokens"], 100_000)
        self.assertEqual(report["api_equivalent"]["exact"], "2.0")

    def test_cache_writes_use_the_explicit_multiplier(self) -> None:
        session = self.write_records(
            session_records(
                [
                    counter(
                        1_000_000,
                        200_000,
                        100_000,
                        cache_write_input_tokens=100_000,
                        reasoning_output_tokens=50_000,
                    )
                ]
            )
        )
        completed = self.run_tool(
            *self.report_arguments(session),
            *self.pricing_arguments(),
            "--cache-write-multiplier",
            "1.25",
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        report = json.loads(completed.stdout)
        self.assertEqual(report["api_equivalent"]["exact"], "5.38")
        self.assertEqual(report["api_equivalent"]["rounded"], "5.38")

    def test_cost_refuses_unreported_cache_write_counter(self) -> None:
        session = self.write_records(session_records([counter(10, 0, 1)]))
        completed = self.run_tool(
            *self.report_arguments(session), *self.pricing_arguments()
        )
        self.assertEqual(completed.returncode, 2)
        self.assertIn("cache_write_input_tokens is not reported", completed.stderr)

    def test_threshold_crossings_are_strictly_greater_and_identified(self) -> None:
        session = self.write_records(
            session_records(
                [
                    counter(100, 0, 1, cache_write_input_tokens=0, reasoning_output_tokens=0),
                    counter(101, 0, 1, cache_write_input_tokens=0, reasoning_output_tokens=0),
                ]
            )
        )
        completed = self.run_tool(
            *self.report_arguments(session), "--long-context-threshold", 100
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        requests = json.loads(completed.stdout)["requests"]
        self.assertEqual(requests["largest_input_tokens"], 101)
        self.assertEqual(
            requests["threshold_crossings"],
            [{"input_tokens": 101, "phase_request": 2, "token_count_event": 2}],
        )

    def test_threshold_crossing_cost_requires_long_context_multipliers(self) -> None:
        session = self.write_records(
            session_records(
                [counter(101, 0, 1, cache_write_input_tokens=0, reasoning_output_tokens=0)]
            )
        )
        pricing = self.pricing_arguments()
        threshold_index = pricing.index("--long-context-threshold")
        pricing[threshold_index + 1] = "100"
        completed = self.run_tool(*self.report_arguments(session), *pricing)
        self.assertEqual(completed.returncode, 2)
        self.assertIn("both long-context multipliers", completed.stderr)

    def test_threshold_multipliers_are_applied_per_request(self) -> None:
        session = self.write_records(
            session_records(
                [
                    counter(100, 0, 1, cache_write_input_tokens=0, reasoning_output_tokens=0),
                    counter(101, 0, 1, cache_write_input_tokens=0, reasoning_output_tokens=0),
                ]
            )
        )
        pricing = self.pricing_arguments()
        threshold_index = pricing.index("--long-context-threshold")
        pricing[threshold_index + 1] = "100"
        completed = self.run_tool(
            *self.report_arguments(session),
            *pricing,
            "--long-context-input-multiplier",
            "2",
            "--long-context-output-multiplier",
            "1.5",
        )
        self.assertEqual(completed.returncode, 0, completed.stderr)
        report = json.loads(completed.stdout)
        self.assertEqual(report["api_equivalent"]["exact"], "0.001258")

    def test_decimal_cost_rounds_half_up(self) -> None:
        session = self.write_records(
            session_records(
                [counter(5_000, 0, 0, cache_write_input_tokens=0, reasoning_output_tokens=0)]
            )
        )
        pricing = self.pricing_arguments()
        pricing[pricing.index("--uncached-input-rate") + 1] = "1"
        pricing[pricing.index("--cached-input-rate") + 1] = "0"
        pricing[pricing.index("--output-rate") + 1] = "0"
        completed = self.run_tool(*self.report_arguments(session), *pricing)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        estimate = json.loads(completed.stdout)["api_equivalent"]
        self.assertEqual(estimate["exact"], "0.005")
        self.assertEqual(estimate["rounded"], "0.01")

    def test_malformed_jsonl_is_rejected_with_line_number(self) -> None:
        session = self.directory / "malformed.jsonl"
        session.write_text('{"type":"session_meta","payload":{"id":"s"}}\n{bad\n')
        completed = self.run_tool(*self.report_arguments(session))
        self.assertEqual(completed.returncode, 2)
        self.assertIn("malformed JSONL at line 2", completed.stderr)

    def test_incomplete_total_counter_is_rejected(self) -> None:
        records = session_records([counter(10, 2, 1)])
        del records[-1]["payload"]["info"]["total_token_usage"]["total_tokens"]
        session = self.write_records(records)
        completed = self.run_tool(*self.report_arguments(session))
        self.assertEqual(completed.returncode, 2)
        self.assertIn("missing required counter(s): total_tokens", completed.stderr)

    def test_incomplete_request_counter_is_rejected(self) -> None:
        records = session_records([counter(10, 2, 1)])
        del records[-1]["payload"]["info"]["last_token_usage"]["input_tokens"]
        session = self.write_records(records)
        completed = self.run_tool(*self.report_arguments(session))
        self.assertEqual(completed.returncode, 2)
        self.assertIn("last_token_usage is incomplete", completed.stderr)

    def test_baseline_counters_must_match_selected_event(self) -> None:
        session = self.write_records(
            session_records(
                [counter(10, 0, 1, cache_write_input_tokens=0, reasoning_output_tokens=0)]
            )
        )
        baseline = self.directory / "baseline.json"
        baseline.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "session_id": "synthetic-session",
                    "token_count_event": 1,
                    "timestamp": "2026-09-03T10:00:01Z",
                    "counters": counter(
                        20,
                        0,
                        2,
                        cache_write_input_tokens=0,
                        reasoning_output_tokens=0,
                    ),
                }
            )
        )
        arguments = self.report_arguments(session)
        arguments[2:2] = ["--baseline", baseline]
        completed = self.run_tool(*arguments)
        self.assertEqual(completed.returncode, 2)
        self.assertIn("baseline does not match its selected session event", completed.stderr)

    def test_request_totals_must_reconcile_to_cumulative_usage(self) -> None:
        records = session_records(
            [counter(10, 2, 1, cache_write_input_tokens=0, reasoning_output_tokens=0)]
        )
        records[-1]["payload"]["info"]["total_token_usage"]["input_tokens"] = 11
        records[-1]["payload"]["info"]["total_token_usage"]["total_tokens"] = 12
        session = self.write_records(records)
        completed = self.run_tool(*self.report_arguments(session))
        self.assertEqual(completed.returncode, 2)
        self.assertIn("do not reconcile", completed.stderr)

    def test_repeated_cumulative_snapshot_is_reported_but_not_counted(self) -> None:
        requests = [
            counter(10, 2, 1, cache_write_input_tokens=0, reasoning_output_tokens=0),
            counter(20, 5, 2, cache_write_input_tokens=0, reasoning_output_tokens=1),
        ]
        records = session_records(requests)
        repeated = json.loads(json.dumps(records[2]))
        repeated["timestamp"] = "2026-09-03T10:00:01.500Z"
        repeated["payload"]["info"]["last_token_usage"] = counter(
            0,
            0,
            0,
            cache_write_input_tokens=0,
            reasoning_output_tokens=0,
        )
        repeated["payload"]["info"]["last_token_usage"]["total_tokens"] = 12_345
        records.insert(3, repeated)
        session = self.write_records(records)

        completed = self.run_tool(*self.report_arguments(session))

        self.assertEqual(completed.returncode, 0, completed.stderr)
        report = json.loads(completed.stdout)
        self.assertEqual(report["usage"]["total_tokens"], 33)
        self.assertEqual(report["requests"]["count"], 2)
        self.assertEqual(report["requests"]["input_tokens"], [10, 20])
        self.assertEqual(
            report["requests"]["repeated_cumulative_snapshots"],
            [
                {
                    "non_usage_last_total_tokens": 12_345,
                    "timestamp": "2026-09-03T10:00:01.500Z",
                    "token_count_event": 2,
                }
            ],
        )
        self.assertEqual(report["requests"]["exact_replayed_token_events"], [])

    def test_exact_info_replay_is_reported_and_not_double_counted(self) -> None:
        requests = [
            counter(10, 2, 1, cache_write_input_tokens=0, reasoning_output_tokens=0),
            counter(20, 5, 2, cache_write_input_tokens=0, reasoning_output_tokens=1),
        ]
        records = session_records(requests)
        replay = json.loads(json.dumps(records[2]))
        replay["timestamp"] = "2026-09-03T10:00:01.500Z"
        records.insert(3, replay)
        session = self.write_records(records)

        completed = self.run_tool(*self.report_arguments(session))

        self.assertEqual(completed.returncode, 0, completed.stderr)
        report = json.loads(completed.stdout)
        self.assertEqual(report["usage"]["total_tokens"], 33)
        self.assertEqual(report["requests"]["count"], 2)
        self.assertEqual(report["requests"]["input_tokens"], [10, 20])
        self.assertEqual(report["requests"]["repeated_cumulative_snapshots"], [])
        self.assertEqual(
            report["requests"]["exact_replayed_token_events"],
            [
                {
                    "exact_replay_of": 1,
                    "timestamp": "2026-09-03T10:00:01.500Z",
                    "token_count_event": 2,
                }
            ],
        )

    def test_changed_info_with_nonzero_request_is_not_treated_as_replay(self) -> None:
        requests = [
            counter(10, 2, 1, cache_write_input_tokens=0, reasoning_output_tokens=0),
            counter(20, 5, 2, cache_write_input_tokens=0, reasoning_output_tokens=1),
        ]
        records = session_records(requests)
        records[2]["payload"]["info"]["model_context_window"] = 100
        changed = json.loads(json.dumps(records[2]))
        changed["timestamp"] = "2026-09-03T10:00:01.500Z"
        changed["payload"]["info"]["model_context_window"] = 101
        records.insert(3, changed)
        session = self.write_records(records)

        completed = self.run_tool(*self.report_arguments(session))

        self.assertEqual(completed.returncode, 2)
        self.assertIn(
            "unchanged cumulative snapshot but has non-zero metered counter(s)",
            completed.stderr,
        )

    def test_pricing_requires_a_complete_explicit_basis(self) -> None:
        session = self.write_records(
            session_records(
                [counter(10, 0, 1, cache_write_input_tokens=0, reasoning_output_tokens=0)]
            )
        )
        completed = self.run_tool(
            *self.report_arguments(session), "--uncached-input-rate", "4"
        )
        self.assertEqual(completed.returncode, 2)
        self.assertIn("API-equivalent pricing is incomplete", completed.stderr)


if __name__ == "__main__":
    unittest.main()
