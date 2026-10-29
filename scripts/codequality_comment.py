"""Render a `baml codequality` comparison between two commits as Markdown.

Reads the JSON reports of `baml codequality --output-format json` for the
base and head of a pull request, writes the comment body to --out, and prints
`changed` or `unchanged` on stdout so the caller can skip posting a comment
that would only say nothing happened.
"""

import argparse
import json
import sys
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Metrics explained in the comment, in the order they're explained.
METRICS = [
    ("cognitive", "Cognitive"),
    ("cyclomatic", "Cyclomatic"),
    ("npath", "NPath"),
    ("nesting", "Nesting"),
    ("exits", "Exits"),
]

MAX_ROWS = 50

MARKER_PREFIX = "<!-- baml-action:codequality"


@dataclass(frozen=True)
class Function:
    name: str
    file: str
    start_line: int
    end_line: int
    metrics: Dict[str, int]


@dataclass(frozen=True)
class Change:
    function: Function
    metric: str
    before: int
    after: int


@dataclass
class Comparison:
    worse: List[Change]
    better: List[Change]
    new: List[Function]
    removed: int


@dataclass(frozen=True)
class Context:
    server_url: str
    repo: str
    head_sha: str
    base_label: str
    project_prefix: str
    project: str


def load_functions(report: dict) -> Dict[Tuple[str, str], Function]:
    functions = {}
    for raw in report["functions"]:
        function = Function(
            name=raw["name"],
            file=raw["file"].replace("\\", "/"),
            start_line=raw["start_line"],
            end_line=raw["end_line"],
            metrics={key: raw[key] for key, _ in METRICS},
        )
        functions.setdefault((function.file, function.name), function)
    return functions


def ratio(numerator: int, denominator: int) -> Fraction:
    # Exact, because NPath can exceed float range.
    return Fraction(numerator, max(denominator, 1))


def compare(
    base: Dict[Tuple[str, str], Function], head: Dict[Tuple[str, str], Function]
) -> Comparison:
    worse = []
    better = []
    new = []
    for key, after in head.items():
        before = base.get(key)
        if before is None:
            new.append(after)
            continue
        for metric, _ in METRICS:
            old, cur = before.metrics[metric], after.metrics[metric]
            if cur > old:
                worse.append(Change(after, metric, old, cur))
            elif cur < old:
                better.append(Change(after, metric, old, cur))
    worse.sort(key=lambda c: (-ratio(c.after, c.before), c.function.name, c.metric))
    better.sort(key=lambda c: (-ratio(c.before, c.after), c.function.name, c.metric))
    new.sort(key=lambda f: (-f.metrics["cognitive"], f.name))
    removed = sum(1 for key in base if key not in head)
    return Comparison(worse, better, new, removed)


def distinct_functions(changes: List[Change]) -> int:
    return len({(c.function.file, c.function.name) for c in changes})


def plural(count: int, word: str) -> str:
    return f"{count} {word}" if count == 1 else f"{count} {word}s"


def function_link(function: Function, ctx: Context) -> str:
    path = f"{ctx.project_prefix}{function.file}"
    url = (
        f"{ctx.server_url}/{ctx.repo}/blob/{ctx.head_sha}/{path}"
        f"#L{function.start_line}-L{function.end_line}"
    )
    return f"[`{function.name}`]({url})"


def metric_label(metric: str) -> str:
    return dict(METRICS)[metric]


def change_table(changes: List[Change], ctx: Context) -> List[str]:
    lines = [
        "| Function | Metric | Before | After |",
        "| --- | --- | ---: | ---: |",
    ]
    for change in changes[:MAX_ROWS]:
        lines.append(
            f"| {function_link(change.function, ctx)} | {metric_label(change.metric)}"
            f" | {change.before} | {change.after} |"
        )
    lines.append("")
    if len(changes) > MAX_ROWS:
        lines += [f"...and {len(changes) - MAX_ROWS} more.", ""]
    return lines


def new_table(functions: List[Function], ctx: Context) -> List[str]:
    header = " | ".join(label for _, label in METRICS)
    lines = [
        f"| Function | {header} |",
        "| --- |" + " ---: |" * len(METRICS),
    ]
    for function in functions[:MAX_ROWS]:
        values = " | ".join(str(function.metrics[key]) for key, _ in METRICS)
        lines.append(f"| {function_link(function, ctx)} | {values} |")
    lines.append("")
    if len(functions) > MAX_ROWS:
        lines += [f"...and {len(functions) - MAX_ROWS} more.", ""]
    return lines


def collapsed(summary: str, body: List[str]) -> List[str]:
    return ["<details>", f"<summary>{summary}</summary>", ""] + body + ["</details>", ""]


def headline(comparison: Comparison) -> str:
    if not changed(comparison):
        return "**No function changed complexity.**"
    worse = distinct_functions(comparison.worse)
    better = distinct_functions(comparison.better)
    parts = []
    if worse:
        parts.append(f"**{plural(worse, 'function')} got worse.**")
    else:
        parts.append("**No function got worse.**")
    if better:
        parts.append(f"{better} got better." if worse else f"{plural(better, 'function')} got better.")
    if comparison.new:
        parts.append(f"{plural(len(comparison.new), 'new function')}.")
    if comparison.removed:
        parts.append(f"{plural(comparison.removed, 'function')} removed.")
    return " ".join(parts)


EXPLANATIONS = """\
#### What these mean

<details>
<summary>Cognitive: how hard the function is to follow</summary>

Each branch or loop adds 1, plus 1 more for every level it is nested inside. Deep nesting costs the most.

Scores 7:

```baml
function capped_total(scores: int[]) -> int {
    let total = 0;
    for (let s in scores) {        // +1
        if (s > 0) {               // +2, nested once
            if (s > 100) {         // +3, nested twice
                total += 100;
            } else {               // +1
                total += s;
            }
        }
    }
    total
}
```

Scores 1, with the branching moved into `cap`:

```baml
function capped_total(scores: int[]) -> int {
    let total = 0;
    for (let s in scores) {        // +1
        total += cap(s);
    }
    total
}
```

</details>

<details>
<summary>Cyclomatic: how many decisions the function makes</summary>

1, plus 1 for each `if`, `else if`, loop, `&&` and `||`. Nesting does not matter. Scores 5:

```baml
function shipping(region: string, heavy: bool) -> int {
    if (region == "us") {          // +1
        if (heavy) {               // +1
            15
        } else {
            8
        }
    } else if (region == "eu") {   // +1
        if (heavy) {               // +1
            20
        } else {
            12
        }
    } else {
        30
    }
}
```

</details>

<details>
<summary>NPath: how many paths a test would need to cover</summary>

Branches in a row multiply. Three independent `if`s give 2 x 2 x 2 = 8 paths, even though cyclomatic is only 4.

```baml
function flags(a: bool, b: bool, c: bool) -> string {
    let s = "";
    if (a) {        // x2
        s += "a";
    }
    if (b) {        // x2
        s += "b";
    }
    if (c) {        // x2
        s += "c";
    }
    s
}
```

</details>

<details>
<summary>Nesting: how deep the deepest block goes</summary>

The most blocks open at once. Early returns and helper functions flatten it. Depth 3:

```baml
function total_size(rows: Row[]) -> int {
    let count = 0;
    for (let row in rows) {                // 1
        if (row.active) {                  // 2
            for (let cell in row.cells) {  // 3
                count += cell.size;
            }
        }
    }
    count
}
```

</details>

<details>
<summary>Exits: how many places the function can return</summary>

Each `return` and `throw`, plus the final expression. More exits mean more places to check when reading what a function gives back.

</details>
"""


def marker(project: str) -> str:
    return f"{MARKER_PREFIX}:{project} -->"


def render(comparison: Optional[Comparison], ctx: Context) -> str:
    lines = [marker(ctx.project), "### Complexity check", ""]
    if comparison is None:
        lines += [
            f"Could not measure `{ctx.base_label}`, so there is nothing to compare against.",
            "",
        ]
    else:
        lines += [headline(comparison), ""]
        if comparison.worse:
            lines += change_table(comparison.worse, ctx)
        if comparison.better:
            summary = f"{plural(distinct_functions(comparison.better), 'function')} got better"
            lines += collapsed(summary, change_table(comparison.better, ctx))
        if comparison.new:
            lines += collapsed(plural(len(comparison.new), "new function"), new_table(comparison.new, ctx))
        lines += [EXPLANATIONS]
    lines.append(
        f"<sub>Compared `{ctx.head_sha[:7]}` with `{ctx.base_label}` using `baml codequality`."
        " This comment updates on every push.</sub>"
    )
    return "\n".join(lines) + "\n"


def changed(comparison: Optional[Comparison]) -> bool:
    if comparison is None:
        return True
    return bool(comparison.worse or comparison.better or comparison.new or comparison.removed)


def read_report(path: Optional[Path]) -> Optional[dict]:
    if path is None or not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except ValueError:
        return None


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, help="base report; missing or unreadable means unmeasured")
    parser.add_argument("--head", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--server-url", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--head-sha", required=True)
    parser.add_argument("--base-label", required=True)
    parser.add_argument("--project-prefix", default="", help="project directory relative to the repo root")
    parser.add_argument("--project", default=".", help="project input, keys the comment marker")
    args = parser.parse_args(argv)

    prefix = args.project_prefix.replace("\\", "/").strip("/")
    ctx = Context(
        server_url=args.server_url.rstrip("/"),
        repo=args.repo,
        head_sha=args.head_sha,
        base_label=args.base_label,
        project_prefix=f"{prefix}/" if prefix and prefix != "." else "",
        project=args.project,
    )
    head = load_functions(json.loads(args.head.read_text(encoding="utf-8")))
    base_report = read_report(args.base)
    comparison = None if base_report is None else compare(load_functions(base_report), head)

    args.out.write_text(render(comparison, ctx), encoding="utf-8")
    print("changed" if changed(comparison) else "unchanged")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
