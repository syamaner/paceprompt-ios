from __future__ import annotations

from copy import deepcopy
import unittest

from paceprompt_eval.issue145_lineage import admit_child, reserve_next, usd


HASH = "a" * 64
PROFILE = "b" * 64


def parent(*, run_id="root", parent_id=None, parent_hash=None, attempts=None, cap="1.00"):
    return {
        "rootRunID": "root",
        "runID": run_id,
        "parentRunID": parent_id,
        "parentEvidenceSha256": parent_hash,
        "verifiedEvidenceTreeSha256": HASH,
        "profileSha256": PROFILE,
        "lineageHardLimitUSD": cap,
        "attempts": attempts if attempts is not None else [],
    }


def plan(parents):
    return admit_child(
        root_run_id="root",
        profile_sha256=PROFILE,
        queue_ids=["a", "b", "c", "d"],
        hard_limit_usd="1.00",
        parents=parents,
        child_run_id="next",
        child_queue_ids=["b", "c", "d"],
        child_worst_case_usd={"b": "0.25", "c": "0.25", "d": "0.25"},
    )


class Issue145LineageTests(unittest.TestCase):
    def test_unlimited_depth_preserves_cumulative_budget_and_parent_hash(self):
        ancestors = [parent(attempts=[{
            "attemptID": "a", "state": "failed",
            "reservedWorstCaseUSD": "0.25", "actualUSD": "0.10",
        }])]
        for number in range(20):
            ancestors.append(parent(
                run_id=f"child-{number}",
                parent_id=ancestors[-1]["runID"],
                parent_hash=HASH,
            ))
        admitted = plan(ancestors)
        self.assertEqual(admitted["parentRunID"], "child-19")
        self.assertEqual(admitted["priorChargedUSD"], "0.10")
        self.assertEqual(admitted["remainingUSD"], "0.90")
        self.assertFalse(admitted["liveAuthorized"])
        self.assertFalse(admitted["credentialRead"])

    def test_unknown_cost_is_charged_at_reserved_worst_case(self):
        ancestors = [parent(attempts=[{
            "attemptID": "a", "state": "possiblySent",
            "reservedWorstCaseUSD": "0.25", "actualUSD": None,
        }])]
        self.assertEqual(plan(ancestors)["remainingUSD"], "0.75")
        ambiguous = deepcopy(ancestors)
        ambiguous[0]["attempts"][0]["actualUSD"] = "0.00"
        with self.assertRaisesRegex(ValueError, "possibly sent"):
            plan(ambiguous)
        with self.assertRaisesRegex(ValueError, "never-sent"):
            admit_child(
                root_run_id="root", profile_sha256=PROFILE,
                queue_ids=["a", "b"], hard_limit_usd="1.00",
                parents=ancestors, child_run_id="next",
                child_queue_ids=["a"], child_worst_case_usd={"a": "0.25"},
            )

    def test_tampered_link_profile_and_duplicated_attempt_fail_closed(self):
        started = {"attemptID": "a", "state": "failed",
                   "reservedWorstCaseUSD": "0.25", "actualUSD": None}
        original = [parent(attempts=[started]), parent(run_id="child-1", parent_id="root", parent_hash=HASH)]
        self.assertEqual(plan(original)["parentRunID"], "child-1")
        for field, value in (("parentEvidenceSha256", "c" * 64),
                             ("profileSha256", "c" * 64),
                             ("lineageHardLimitUSD", "2.00"),
                             ("verifiedEvidenceTreeSha256", "invalid")):
            changed = deepcopy(original)
            changed[1][field] = value
            with self.assertRaises(ValueError):
                plan(changed)
        duplicated = deepcopy(original)
        duplicated[1]["attempts"] = [started]
        with self.assertRaisesRegex(ValueError, "replays"):
            plan(duplicated)

    def test_invalid_plan_and_budget_fail_closed(self):
        for amount in ("NaN", "Infinity", "-1", " 1", ""):
            with self.assertRaises(ValueError):
                usd(amount)
        bound = admit_child(
            root_run_id="root", profile_sha256=PROFILE,
            queue_ids=["a", "b"], hard_limit_usd="0.20",
            parents=[parent(cap="0.20")], child_run_id="next",
            child_queue_ids=["a", "b"],
            child_worst_case_usd={"a": "0.20", "b": "0.01"},
        )
        with self.assertRaisesRegex(ValueError, "frozen plan"):
            reserve_next(bound, "b")
        after_first = reserve_next(bound, "a")
        self.assertEqual(after_first["remainingUSD"], "0.00")
        self.assertEqual(after_first["plannedReservationsUSD"]["a"], "0.20")
        with self.assertRaisesRegex(ValueError, "hard limit"):
            reserve_next(after_first, "b")
        with self.assertRaisesRegex(ValueError, "prefix"):
            admit_child(
                root_run_id="root", profile_sha256=PROFILE,
                queue_ids=["a", "b"], hard_limit_usd="1.00",
                parents=[parent()], child_run_id="next",
                child_queue_ids=["b", "a"],
                child_worst_case_usd={"a": "0.25", "b": "0.25"},
            )
        with self.assertRaisesRegex(ValueError, "exceeds lineage cap"):
            plan([parent(attempts=[{
                "attemptID": "a", "state": "possiblySent",
                "reservedWorstCaseUSD": "1.01", "actualUSD": None,
            }])])


if __name__ == "__main__":
    unittest.main()
