/// One metric summed over every function in the project.
class MetricSum {
    metric: Metric,
    sum: bigint,
}

/// What the comment needs of the project as a whole.
class Summary {
    functions: int,
    lines: int,
    /// One entry per metric, in `all_metrics()` order.
    sums: MetricSum[],
}

function summarize(report: Report) -> Summary {
    Summary {
        functions: report.functions.length(),
        lines: report.files.reduce(
            (total, f) -> {
                total + f.lines
            },
            0,
        ),
        sums: all_metrics().map((m) -> {
            MetricSum {
                metric: m,
                sum: report.functions.reduce(
                    (total, f) -> {
                        total + metric_value(f, m)
                    },
                    0n,
                ),
            }
        }),
    }
}

/// The average per function, exactly; null for a project with no functions.
function average(summary: Summary, metric: Metric) -> Ratio? {
    if (summary.functions == 0) {
        null
    } else {
        let sum = summary.sums
            .find((s) -> {
                s.metric == metric
            })
            ?.sum
            ?? 0n;
        Ratio { numerator: sum, denominator: 0n + summary.functions }
    }
}

/// `n` for a reader, as `baml codequality` writes it: digits grouped by
/// thousands up to a million, then one decimal and a suffix (`2.7M`,
/// `273.0B`), then scientific notation past a thousand trillion.
function count(n: bigint) -> string {
    let digits = n.to_string();
    let length = digits.length();
    if (length <= 6) {
        let out = "";
        for (let i in baml.iter.Range.new(0, length)) {
            if (i > 0 && (length - i) % 3 == 0) {
                out = out + ",";
            }
            out = out + (digits.at(i) ?? "");
        }
        return out;
    }
    if (length <= 15) {
        let exponent = if (length <= 9) {
            6
        } else if (length <= 12) {
            9
        } else {
            12
        };
        let suffix = if (length <= 9) {
            "M"
        } else if (length <= 12) {
            "B"
        } else {
            "T"
        };
        let tenths = tenths_of(n, exponent);
        return `${tenths / 10n}.${tenths % 10n}${suffix}`;
    }
    let exponent = length - 1;
    let tenths = tenths_of(n, exponent);
    // Rounding can carry into a new digit: `9.96e18` reads `1.0e19`.
    if (tenths >= 100n) {
        tenths = tenths / 10n;
        exponent = exponent + 1;
    }
    `${tenths / 10n}.${tenths % 10n}e${exponent}`
}

/// `n / 10^exponent` in tenths, rounded half up.
function tenths_of(n: bigint, exponent: int) -> bigint {
    let unit = 10n.pow(0n + exponent - 1);
    (n + unit / 2n) / unit
}
