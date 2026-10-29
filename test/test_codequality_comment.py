import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

import codequality_comment as cq  # noqa: E402


def function(name, file="baml_src/main.baml", start=1, end=3, **metrics):
    values = {"cognitive": 0, "cyclomatic": 1, "npath": 1, "nesting": 0, "exits": 1}
    values.update(metrics)
    return {
        "name": name,
        "file": file,
        "start_line": start,
        "end_line": end,
        "lines": end - start + 1,
        "params": 0,
        "fan_in": 0,
        "fan_out": 0,
        **values,
    }


def report(*functions):
    return {"functions": list(functions), "files": []}


CTX = cq.Context(
    server_url="https://github.com",
    repo="acme/app",
    head_sha="a41c9e2f00000000000000000000000000000000",
    base_label="canary",
    project_prefix="",
    project=".",
)


def compare(base, head):
    return cq.compare(cq.load_functions(base), cq.load_functions(head))


class CompareTest(unittest.TestCase):
    def test_unchanged_reports_nothing(self):
        r = report(function("a", cognitive=3))
        comparison = compare(r, r)
        self.assertEqual((comparison.worse, comparison.better, comparison.new, comparison.removed), ([], [], [], 0))
        self.assertFalse(cq.changed(comparison))

    def test_each_changed_metric_is_a_row(self):
        comparison = compare(
            report(function("a", cognitive=2, nesting=1, exits=3)),
            report(function("a", cognitive=5, nesting=2, exits=1)),
        )
        self.assertEqual([(c.metric, c.before, c.after) for c in comparison.worse], [("cognitive", 2, 5), ("nesting", 1, 2)])
        self.assertEqual([(c.metric, c.before, c.after) for c in comparison.better], [("exits", 3, 1)])
        self.assertEqual(cq.distinct_functions(comparison.worse), 1)

    def test_worse_sorted_by_relative_increase(self):
        comparison = compare(
            report(function("small", cognitive=10), function("big", cognitive=1)),
            report(function("small", cognitive=12), function("big", cognitive=4)),
        )
        self.assertEqual([c.function.name for c in comparison.worse], ["big", "small"])

    def test_increase_from_zero_is_worse(self):
        comparison = compare(report(function("a", cognitive=0)), report(function("a", cognitive=1)))
        self.assertEqual([(c.before, c.after) for c in comparison.worse], [(0, 1)])

    def test_same_name_in_different_files_are_different_functions(self):
        comparison = compare(
            report(function("a", file="x.baml", cognitive=1)),
            report(function("a", file="x.baml", cognitive=1), function("a", file="y.baml", cognitive=9)),
        )
        self.assertEqual([f.file for f in comparison.new], ["y.baml"])
        self.assertEqual(comparison.worse, [])

    def test_new_and_removed(self):
        comparison = compare(report(function("gone")), report(function("fresh", cognitive=4)))
        self.assertEqual([f.name for f in comparison.new], ["fresh"])
        self.assertEqual(comparison.removed, 1)
        self.assertTrue(cq.changed(comparison))

    def test_npath_beyond_float_range(self):
        huge = 10**400
        comparison = compare(
            report(function("a", npath=huge), function("b", npath=2)),
            report(function("a", npath=huge * 3), function("b", npath=4)),
        )
        self.assertEqual([c.function.name for c in comparison.worse], ["a", "b"])

    def test_windows_paths_match_posix_paths(self):
        comparison = compare(
            report(function("a", file="baml_src/main.baml")),
            report(function("a", file="baml_src\\main.baml")),
        )
        self.assertEqual(comparison.new, [])


class RenderTest(unittest.TestCase):
    def test_mockup_shape(self):
        comparison = compare(
            report(
                function("Router.dispatch", start=10, end=40, cognitive=9),
                function("Pipeline.run", cognitive=22),
            ),
            report(
                function("Router.dispatch", start=10, end=42, cognitive=18),
                function("Pipeline.run", cognitive=8),
            ),
        )
        body = cq.render(comparison, CTX)
        self.assertTrue(body.startswith("<!-- baml-action:codequality:. -->\n### Complexity check\n"))
        self.assertIn("**1 function got worse.** 1 got better.", body)
        self.assertIn(
            "| [`Router.dispatch`](https://github.com/acme/app/blob/"
            "a41c9e2f00000000000000000000000000000000/baml_src/main.baml#L10-L42) | Cognitive | 9 | 18 |",
            body,
        )
        self.assertIn("<summary>1 function got better</summary>", body)
        self.assertIn("#### What these mean", body)
        self.assertIn("Compared `a41c9e2` with `canary` using `baml codequality`.", body)

    def test_nothing_worse(self):
        comparison = compare(report(function("a", cognitive=5)), report(function("a", cognitive=1)))
        self.assertIn("**No function got worse.** 1 function got better.", cq.render(comparison, CTX))

    def test_project_prefix_in_links(self):
        ctx = cq.Context(**{**CTX.__dict__, "project_prefix": "services/agent/", "project": "services/agent"})
        comparison = compare(report(), report(function("a")))
        body = cq.render(comparison, ctx)
        self.assertIn("/blob/a41c9e2f00000000000000000000000000000000/services/agent/baml_src/main.baml#L1-L3", body)
        self.assertTrue(body.startswith("<!-- baml-action:codequality:services/agent -->"))

    def test_unmeasured_base(self):
        body = cq.render(None, CTX)
        self.assertIn("Could not measure `canary`", body)
        self.assertNotIn("What these mean", body)
        self.assertTrue(cq.changed(None))

    def test_rows_are_capped(self):
        count = cq.MAX_ROWS + 3
        comparison = compare(
            report(*[function(f"f{i}", cognitive=1) for i in range(count)]),
            report(*[function(f"f{i}", cognitive=2) for i in range(count)]),
        )
        body = cq.render(comparison, CTX)
        self.assertIn("...and 3 more.", body)
        self.assertEqual(body.count("| Cognitive | 1 | 2 |"), cq.MAX_ROWS)


class MainTest(unittest.TestCase):
    def run_main(self, base, head, *extra):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "head.json").write_text(json.dumps(head))
            args = ["--head", str(tmp / "head.json"), "--out", str(tmp / "out.md")]
            if base is not None:
                (tmp / "base.json").write_text(base if isinstance(base, str) else json.dumps(base))
                args += ["--base", str(tmp / "base.json")]
            args += [
                "--server-url", "https://github.com/",
                "--repo", "acme/app",
                "--head-sha", "a41c9e2",
                "--base-label", "canary",
                *extra,
            ]
            captured = io.StringIO()
            with contextlib.redirect_stdout(captured):
                self.assertEqual(cq.main(args), 0)
            return captured.getvalue().strip(), (tmp / "out.md").read_text()

    def test_unchanged(self):
        r = report(function("a"))
        status, body = self.run_main(r, r)
        self.assertEqual(status, "unchanged")
        self.assertIn("**No function changed complexity.**", body)

    def test_missing_base_is_unmeasured(self):
        status, body = self.run_main(None, report(function("a")))
        self.assertEqual(status, "changed")
        self.assertIn("Could not measure", body)

    def test_garbage_base_is_unmeasured(self):
        status, body = self.run_main("error: not json", report(function("a")))
        self.assertEqual(status, "changed")
        self.assertIn("Could not measure", body)

    def test_dot_prefix_is_root(self):
        _, body = self.run_main(report(), report(function("a")), "--project-prefix", ".")
        self.assertIn("/blob/a41c9e2/baml_src/main.baml#L1-L3", body)


if __name__ == "__main__":
    unittest.main()
