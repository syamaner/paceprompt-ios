import unittest
from build_classification_diagnostics import measure, MISSING


class ClassificationTests(unittest.TestCase):
    def test_missing_is_false_negative_not_extra_true_class(self):
        r = measure({"a->a": 2, "a->b": 1, f"a->{MISSING}": 1, "b->a": 1, "b->b": 3}, ["a", "b"])
        self.assertEqual(r["accuracy"]["percent"], "62.5000")
        self.assertEqual(r["perClass"]["a"]["recall"]["percent"], "50.0000")
        self.assertEqual(r["perClass"]["a"]["precision"]["percent"], "66.6667")
        c = measure({"a->a": 2, f"a->{MISSING}": 2}, ["a"], conditional=True)
        self.assertEqual(c["accuracy"]["percent"], "100.0000")

    def test_all_missing_and_empty_conditional(self):
        r = measure({f"a->{MISSING}": 2}, ["a"])
        self.assertIsNone(r["perClass"]["a"]["precision"])
        self.assertEqual(r["macroF1"]["percent"], "0.0000")
        self.assertIsNone(measure({f"a->{MISSING}": 2}, ["a"], conditional=True)["accuracy"])

    def test_unknown_and_negative_rejected(self):
        for c in ({"a->unexpected": 1}, {"a->a": -1}):
            with self.assertRaises(ValueError):
                measure(c, ["a"])

    def test_perfect_and_zero_support_class(self):
        r = measure({"a->a": 3, "b->b": 2}, ["a", "b"])
        self.assertEqual(r["macroF1"]["percent"], "100.0000")
        r = measure({"a->a": 3}, ["a", "b"])
        self.assertIsNone(r["perClass"]["b"]["recall"])
        self.assertEqual(r["macroF1"]["percent"], "50.0000")


if __name__ == "__main__":
    unittest.main()
