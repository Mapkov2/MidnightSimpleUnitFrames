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


class CloneImportPreludeTest(unittest.TestCase):
    def normalized(self, source):
        return s.ratchet.clone_source_lines(s.ratchet.strip_source(source)[1])

    def test_guarded_dotted_imports_are_only_prefix_wiring(self):
        for guard in ('local Style = assert(GF.PreviewStyle, "required provider")',
                      "local Layout = assert(MSUF.GF.PreviewLayout, 'required provider')",
                      'local Style = assert ( GF.PreviewStyle , "required provider" )',
                      'local AuraPainter = assert(MSUF.Require("MSUF_Auras3", "GroupFrames/Preview").MockAuraPainter)',
                      "local AuraPainter = assert(MSUF.Require('MSUF_Auras3', 'owner').MockAuraPainter)"):
            with self.subTest(guard=guard):
                source = 'local _, MSUF = ...\n' + guard + '\nlocal Paint = Style.Paint\nlocal value = 17 + 1\n'
                self.assertEqual(self.normalized(source), [(4, 'local value = 17 + 1')])

    def test_executable_or_mixed_inputs_terminate_the_prefix(self):
        for guard in ('local Style = assert(BuildStyle(), "required provider")',
                      'local Style = assert(GF.PreviewStyle or fallback, "required provider")',
                      'local Style = assert(GF["PreviewStyle"], "required provider")',
                      'local Style = assert(GF.PreviewStyle, message)',
                      'local Style = assert(GF.PreviewStyle, "required" .. suffix)',
                      'local Style = assert(GF.PreviewStyle, "required", extra)',
                      'local Style, other = assert(GF.PreviewStyle, "required")',
                      'local Style = assert(GF.PreviewStyle)',
                      'local Style = assert(GF, "required")',
                      'Style = assert(GF.PreviewStyle, "required")',
                      'local Style = assert(MSUF.Require(name, "owner").Paint)',
                      'local Style = assert(MSUF.Require("Style", owner).Paint)',
                      'local Style = assert(MSUF.Require("Style", "owner"))',
                      'local Style = assert(Other.Require("Style", "owner").Paint)',
                      'local Style = assert(MSUF.Require("Style", "owner").Paint())',
                      'local Style = assert(MSUF.Require("Style", "owner").Paint + 1)',
                      'local Style = assert(MSUF.Require("Style", "owner")["Paint"])',
                      'local Style = assert(MSUF.Require("Style", "owner", extra).Paint)',
                      'local Style = assert(MSUF.Require("Style" .. suffix, "owner").Paint)',
                      'local Style = assert(GF.PreviewStyle, "required"); Paint()'):
            with self.subTest(guard=guard):
                source = 'local _, MSUF = ...\n' + guard + '\nlocal Paint = Style.Paint\n'
                kept = self.normalized(source)
                self.assertTrue(any(number == 2 for number, _ in kept), guard)
                self.assertTrue(any(number == 3 for number, _ in kept), guard)

    def test_real_body_copies_still_form_clone_windows(self):
        body = ('local function Paint(frame)\n'
                '  local a = frame.alpha\n  local b = frame.beta\n  local c = frame.gamma\n'
                '  local d = frame.delta\n  local e = frame.epsilon\n  local f = frame.zeta\n'
                '  return a + b + c + d + e + f\nend\n')
        prelude = 'local Style = assert(GF.PreviewStyle, "required provider")\nlocal Paint = Style.Paint\n'
        kept = self.normalized(prelude + body)
        hashes = s.ratchet.window_hashes([line for _, line in kept])
        self.assertTrue(hashes, 'executable duplicate body disappeared')
        self.assertEqual(hashes, s.ratchet.window_hashes([line for _, line in self.normalized(body)]))
        # An import-looking assertion after feature code is executable too.
        kept = self.normalized('Paint()\n' + prelude)
        self.assertTrue(any(number == 2 for number, _ in kept))

    def test_real_scorecard_rejects_unlisted_executable_copies(self):
        import tempfile
        with tempfile.TemporaryDirectory(prefix='clone-prelude-') as directory:
            root = Path(directory)
            (root / 'tools').mkdir()
            folder = root / 'MidnightSimpleUnitFrames'
            folder.mkdir()
            source = ('local Style = assert(GF.PreviewStyle, "required provider")\n'
                      'local Paint = Style.Paint\nlocal function Paint(frame)\n'
                      'local a = frame.alpha\nlocal b = frame.beta\nlocal c = frame.gamma\n'
                      'local d = frame.delta\nlocal e = frame.epsilon\nlocal f = frame.zeta\n'
                      'return a + b + c + d + e + f\nend\n')
            for name in ('First.lua', 'Second.lua'):
                (folder / name).write_text(source, encoding='utf-8')
            rels = ['MidnightSimpleUnitFrames/First.lua', 'MidnightSimpleUnitFrames/Second.lua']
            with patch.object(s.ratchet, 'product_files', return_value=(rels, set())):
                measured = s.measure(root)
            self.assertGreater(measured[3], 0)
            self.assertEqual(measured[3], measured[4], 'unlisted duplicate body was excused')


if __name__ == "__main__":
    unittest.main()
