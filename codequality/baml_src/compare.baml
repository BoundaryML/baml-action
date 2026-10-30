class MetricChange {
    metric: Metric,
    before: bigint,
    after: bigint,
}

/// One table row: a function and every metric of it that changed.
class FunctionChange {
    report: FunctionReport,
    changes: MetricChange[],
}

class Comparison {
    worse: FunctionChange[],
    better: FunctionChange[],
    added: FunctionReport[],
    removed: int,
    before: Summary,
    after: Summary,
}

/// An exact fraction, because NPath can be too large for a float.
class Ratio {
    numerator: bigint,
    denominator: bigint,
}

function function_key(report: FunctionReport) -> string {
    `${report.file}\n${report.name}`
}

/// Functions by key, keeping the first of any duplicates.
function functions_by_key(report: Report) -> map<string, FunctionReport> {
    let functions: map<string, FunctionReport> = {};
    for (let f in report.functions) {
        let _ = functions.get_or_insert(function_key(f), f);
    }
    functions
}

function ratio(numerator: bigint, denominator: bigint) -> Ratio {
    Ratio {
        numerator: numerator,
        denominator: if (denominator < 1n) {
            1n
        } else {
            denominator
        },
    }
}

function compare_ratios(a: Ratio, b: Ratio) -> baml.ops.Ordering {
    (a.numerator * b.denominator).cmp(b.numerator * a.denominator)
}

/// How much the function's most-changed metric grew (for a worse function)
/// or shrank (for a better one).
function largest_ratio(change: FunctionChange, worse: bool) -> Ratio {
    let largest = ratio(0n, 1n);
    for (let c in change.changes) {
        let r = if (worse) {
            ratio(c.after, c.before)
        } else {
            ratio(c.before, c.after)
        };
        if (compare_ratios(r, largest) == baml.ops.Ordering.Greater) {
            largest = r;
        }
    }
    largest
}

/// Biggest change first, then by name and file so the order is stable.
function sort_changes(changes: FunctionChange[], worse: bool) -> FunctionChange[] {
    changes.sort_by((a, b) -> {
        let by_ratio = compare_ratios(largest_ratio(b, worse), largest_ratio(a, worse));
        if (by_ratio != baml.ops.Ordering.Equal) {
            by_ratio
        } else if (a.report.name != b.report.name) {
            a.report.name.cmp(b.report.name)
        } else {
            a.report.file.cmp(b.report.file)
        }
    })
}

/// A function is worse if any metric went up, and better if metrics only went down.
function compare(base: Report, head: Report) -> Comparison {
    let base_functions = functions_by_key(base);
    let head_functions = functions_by_key(head);
    let worse: FunctionChange[] = [];
    let better: FunctionChange[] = [];
    let added: FunctionReport[] = [];

    for (let after in head_functions.values()) {
        let before = base_functions.get(function_key(after));
        if (before == null) {
            added.push(after);
            continue;
        }
        let changes: MetricChange[] = [];
        for (let metric in all_metrics()) {
            let old = metric_value(before, metric);
            let new = metric_value(after, metric);
            if (old != new) {
                changes.push(MetricChange { metric: metric, before: old, after: new });
            }
        }
        if (
            changes.some((c) -> {
                c.after > c.before
            })
        ) {
            worse.push(FunctionChange { report: after, changes: changes });
        } else if (changes.length() > 0) {
            better.push(FunctionChange { report: after, changes: changes });
        }
    }

    added.sort_by((a, b) -> {
        if (a.cognitive != b.cognitive) {
            b.cognitive.cmp(a.cognitive)
        } else {
            a.name.cmp(b.name)
        }
    });
    Comparison {
        worse: sort_changes(worse, true),
        better: sort_changes(better, false),
        added: added,
        removed: base_functions.keys()
            .filter((key) -> {
                !head_functions.has(key)
            })
            .length(),
        before: summarize(base),
        after: summarize(head),
    }
}

function changed(comparison: Comparison) -> bool {
    comparison.worse.length() > 0
        || comparison.better.length() > 0
        || comparison.added.length() > 0
        || comparison.removed > 0
}
