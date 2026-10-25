"""Exercise the real scorecard verdict with independent clocks and content rows."""
from collections import Counter
import contextlib
import io
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import scorecard as s


class ScorecardTimingTest(unittest.TestCase):
    def run_card(self, wall, cpu, metric=None):
        totals = Counter()
        if metric in ("client_guards", "fallback_lambdas", "semicolon_lines", "long_lines"):
            totals[metric] = 1
        measured = (totals, 1 if metric == "long" else 0, 1 if metric == "long" else 0,
                    1 if metric == "clones" else 0, 1 if metric == "clones" else 0, [])
        globals_ = (0, 0, 0, ["extra"] if metric == "globals" else [], [], 0, [])
        preview = Counter(pending_sites=1 if metric == "preview" else 0)
        menu = (1, 1, [], 1, ["stale"] if metric == "schema" else [])
        output = io.StringIO()
        with patch.object(sys, "argv", ["scorecard.py"]), contextlib.redirect_stdout(output), \
                patch.object(s, "measure", return_value=measured), \
                patch.object(s, "global_counts", return_value=globals_), \
                patch.object(s, "preview_render_census", return_value=preview), \
                patch.object(s, "menu_coverage", return_value=menu), \
                patch.object(s.time, "perf_counter", side_effect=[0, wall]), \
                patch.object(s.time, "process_time", side_effect=[0, cpu]):
            result = s.main()
        return result, output.getvalue()

    def test_load_delayed_wall_clock_does_not_fail_content_or_cpu_budget(self):
        for wall in (8.710, 11.935, 100):
            with self.subTest(wall=wall):
                result, output = self.run_card(wall, 8)
                self.assertEqual(result, 0, output)
                self.assertIn("static wall time\t%.3f s\tinformational\tINFO" % wall, output)
                self.assertIn("static CPU time\t8.000 s\t< 10 s\tPASS", output)

    def test_cpu_budget_still_fails_at_the_boundary(self):
        for cpu in (10, 11.935):
            result, output = self.run_card(1, cpu)
            self.assertEqual(result, 1, output)
            self.assertIn("static CPU time\t%.3f s\t< 10 s\tFAIL" % cpu, output)

    def test_every_content_failure_stays_hard(self):
        for metric in ("client_guards", "fallback_lambdas", "semicolon_lines", "long_lines",
                       "long", "clones", "globals", "preview", "schema"):
            with self.subTest(metric=metric):
                result, output = self.run_card(100, 1, metric)
                self.assertEqual(result, 1, output)
                self.assertIn("scorecard: 1 failed", output)


if __name__ == "__main__":
    unittest.main()
