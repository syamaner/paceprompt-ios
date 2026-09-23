"""Offline tests for proposed issue #145 transient-response retry decisions."""

from datetime import datetime, timezone
import unittest

from paceprompt_eval.issue145_retry import RetryPolicy, decide_retry, reserve_wire_send


class Issue145RetryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.policy = RetryPolicy(
            max_sends_per_position=3,
            retryable_status_codes=frozenset({429, 502, 503, 504, 524, 529}),
            fallback_backoff_seconds=(30, 120),
            max_single_wait_seconds=900,
            max_cumulative_wait_seconds=900,
        )
        self.now = datetime(2026, 9, 23, 12, 0, 0, tzinfo=timezone.utc)

    def decide(self, status=429, headers=None, sends=1, waited=0):
        return decide_retry(
            self.policy,
            status_code=status,
            response_headers={} if headers is None else headers,
            completed_sends=sends,
            cumulative_wait_seconds=waited,
            received_at=self.now,
        )

    def test_missing_response_and_non_transient_status_never_retry(self) -> None:
        self.assertEqual(self.decide(status=None, headers=None).reason, "noCompleteHTTPResponse")
        for status in (429.0, True, "429"):
            self.assertEqual(self.decide(status=status).reason, "invalidHTTPStatus")
        for status in (400, 401, 403, 408, 422, 500):
            self.assertFalse(self.decide(status=status).retry)
        for status in (429, 502, 503, 504, 524, 529):
            self.assertTrue(self.decide(status=status).retry)

    def test_fallback_schedule_and_send_limit_are_exact(self) -> None:
        self.assertEqual(self.decide().wait_seconds, 30)
        self.assertEqual(self.decide(sends=2).wait_seconds, 120)
        self.assertEqual(self.decide(sends=3).reason, "sendLimitReached")

    def test_retry_after_seconds_and_http_date_are_minimum_delays(self) -> None:
        self.assertEqual(self.decide(headers={"ReTrY-AfTeR": "45"}).wait_seconds, 45)
        self.assertEqual(
            self.decide(headers={"retry-after": "Wed, 23 Sep 2026 12:02:30 GMT"}).wait_seconds,
            150,
        )
        self.assertEqual(self.decide(headers={"retry-after": "0"}).wait_seconds, 30)

    def test_invalid_or_excessive_header_stops_closed(self) -> None:
        self.assertEqual(
            self.decide(headers={"Retry-After": "1000", "retry-after": "0"}).reason,
            "ambiguousResponseHeaders",
        )
        for header in ("-1", "1.5", "tomorrow", "1000"):
            self.assertFalse(self.decide(headers={"Retry-After": header}).retry)
        self.assertEqual(
            self.decide(headers={"Retry-After": "1000"}).reason,
            "singleWaitLimitReached",
        )
        self.assertEqual(self.decide(headers={"Retry-After": "800"}, waited=200).reason,
                         "cumulativeWaitLimitReached")
        self.assertEqual(self.decide(headers={"Retry-After": 30}).reason,
                         "invalidResponseHeaders")

    def test_policy_rejects_unbounded_or_incomplete_controls(self) -> None:
        with self.assertRaises(ValueError):
            RetryPolicy(3, frozenset({429}), (30,), 900, 900)
        with self.assertRaises(ValueError):
            RetryPolicy(0, frozenset({429}), (), 900, 900)
        with self.assertRaises(ValueError):
            RetryPolicy(True, frozenset({429}), (), 900, 900)

    def test_each_retry_needs_a_new_conservative_budget_reservation(self) -> None:
        self.assertEqual(
            reserve_wire_send(hard_limit_usd="0.03", charged_usd="0.01",
                              reserved_usd="0", worst_case_usd="0.01"),
            "0.01",
        )
        with self.assertRaises(ValueError):
            reserve_wire_send(hard_limit_usd="0.03", charged_usd="0.02",
                              reserved_usd="0.01", worst_case_usd="0.01")
        with self.assertRaises(ValueError):
            reserve_wire_send(hard_limit_usd="NaN", charged_usd="0",
                              reserved_usd="0", worst_case_usd="0.01")


if __name__ == "__main__":
    unittest.main()
