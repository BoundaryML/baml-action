class Context {
    server_url: string,
    repo: string,
    head_sha: string,
    base_label: string,
    /// Project directory relative to the repository root: empty, or ending in `/`.
    project_prefix: string,
    /// The `project` input, which keys the comment marker.
    project: string,
}

function max_rows() -> int {
    50
}

function plural(count: int, word: string) -> string {
    if (count == 1) {
        `${count} ${word}`
    } else {
        `${count} ${word}s`
    }
}

function function_link(report: FunctionReport, ctx: Context) -> string {
    let path = `${ctx.project_prefix}${report.file}`;
    let url = `${ctx.server_url}/${ctx.repo}/blob/${ctx.head_sha}/${path}#L${report.start_line}-L${report.end_line}`;
    `[\`${report.name}\`](${url})`
}

function marker(project: string) -> string {
    `<!-- baml-action:codequality:${project} -->`
}

/// The first line: how many functions moved, and the size of the project.
function headline(c: Comparison) -> string {
    let worse = c.worse.length();
    let better = c.better.length();
    let parts: string[] = [];
    if (!changed(c)) {
        parts.push("**No function changed complexity.**");
    } else {
        let first = if (worse > 0) {
            `**${plural(worse, "function")} got worse**`
        } else {
            "**No function got worse**"
        };
        if (better > 0) {
            parts.push(`${first}, ${better} got better.`);
        } else {
            parts.push(`${first}.`);
        }
        let others: string[] = [];
        if (c.added.length() > 0) {
            others.push(`${c.added.length()} new`);
        }
        if (c.removed > 0) {
            others.push(`${c.removed} removed`);
        }
        if (others.length() > 0) {
            parts.push(`${others.join(", ")}.`);
        }
    }
    if (c.before.lines != c.after.lines) {
        parts.push(`Lines ${count(0n + c.before.lines)} &rarr; ${count(0n + c.after.lines)}.`);
    }
    parts.join(" ")
}

/// A metric's name inside a sentence.
function metric_word(metric: Metric) -> string {
    match (metric) {
        Metric.NPath => "NPath",
        _ => metric.to_string().to_lower_case(),
    }
}

/// Every metric of the function that moved, after whether it got worse.
function change_summary(change: FunctionChange, worse: bool) -> string {
    let direction = if (worse) {
        "**Worse**"
    } else {
        "**Better**"
    };
    let moves = change.changes.map((m) -> {
        `${metric_word(m.metric)} ${count(m.before)} &rarr; ${count(m.after)}`
    });
    `${direction}: ${moves.join(", ")}`
}

/// One row per function whose change is significant, worse first. Empty when
/// none is.
function function_table(c: Comparison, ctx: Context) -> string[] {
    let rows: string[] = [];
    for (
        let change in c.worse.filter((f) -> {
            significant(f)
        })
    ) {
        rows.push(`| ${function_link(change.report, ctx)} | ${change_summary(change, true)} |`);
    }
    for (
        let change in c.better.filter((f) -> {
            significant(f)
        })
    ) {
        rows.push(`| ${function_link(change.report, ctx)} | ${change_summary(change, false)} |`);
    }
    if (rows.length() == 0) {
        return [];
    }
    let lines = ["| Function | What changed |", "| --- | --- |"].concat(rows.slice(0, max_rows()));
    lines.push("");
    if (rows.length() > max_rows()) {
        lines.push(`...and ${rows.length() - max_rows()} more.`);
        lines.push("");
    }
    lines
}

/// The largest radius the radar draws, as a percentage of the base. Larger
/// values are drawn at the edge; the axis label still gives the real figure.
function radar_cap() -> bigint {
    300n
}

/// The base's average for `metric` divided by the head's, as a rounded
/// percentage: above 100 when the head is simpler. Null when the head's
/// average is zero and the base's is not, which no percentage expresses.
function health_percent(c: Comparison, metric: Metric) -> bigint? {
    let before = average(c.before, metric) ?? ratio(0n, 1n);
    let after = average(c.after, metric) ?? ratio(0n, 1n);
    if (after.numerator == 0n) {
        if (before.numerator == 0n) {
            100n
        } else {
            null
        }
    } else {
        let denominator = after.numerator * before.denominator;
        (before.numerator * after.denominator * 100n + denominator / 2n) / denominator
    }
}

/// What a metric rewards, so that a bigger value on the radar reads as better.
function health_name(metric: Metric) -> string {
    match (metric) {
        Metric.Cognitive => "Readable",
        Metric.Cyclomatic => "Few branches",
        Metric.NPath => "Few paths",
        Metric.Nesting => "Flat",
        Metric.Exits => "Few exits",
    }
}

/// A Mermaid radar of code health per function, with the base at 100% on
/// every axis so metrics of very different sizes share one chart. Empty when
/// the base has no functions or no average moved.
function radar(c: Comparison, ctx: Context) -> string[] {
    if (c.before.functions == 0) {
        return [];
    }
    let percents = all_metrics().map((m) -> {
        health_percent(c, m)
    });
    if (
        percents.every((p) -> {
            p == 100n
        })
    ) {
        return [];
    }
    let axes: string[] = [];
    let values: string[] = [];
    let largest = 150n;
    for (let i in baml.iter.Range.new(0, all_metrics().length())) {
        let m = all_metrics()[i];
        let p = percents[i];
        let label = match (p) {
            null => `${health_name(m)} >${radar_cap()}%`,
            let v: bigint => `${health_name(m)} ${count(v)}%`,
        };
        let drawn = match (p) {
            null => radar_cap(),
            let v: bigint => {
                if (v > radar_cap()) {
                    radar_cap()
                } else {
                    v
                }
            },
        };
        if (drawn > largest) {
            largest = drawn;
        }
        axes.push(`${m.to_string().to_lower_case()}["${label}"]`);
        values.push(drawn.to_string());
    }
    let top = (largest + 49n) / 50n * 50n;
    let base_label = ctx.base_label.replace_all("\"", "'");
    [
        `Code health per function vs \`${ctx.base_label}\` (bigger is better, \`${ctx.base_label}\` = 100%):`,
        "",
        "```mermaid",
        // Mermaid's default radar is 600px square, taller than the tables
        // around it.
        "---",
        "config:",
        "  radar:",
        "    width: 280",
        "    height: 280",
        "    marginTop: 30",
        "    marginBottom: 30",
        "    marginLeft: 70",
        "    marginRight: 70",
        "    graticule: polygon",
        "    curveTension: 0",
        // Brand colors (BoundaryML/brand design.md): Pasture 300 for the
        // base, Clover 200 for the head, both legible on light and dark.
        // Mid-grey hairlines keep the grid faint in either theme.
        "  themeVariables:",
        "    cScale0: \"#82B571\"",
        "    cScale1: \"#CAAAF2\"",
        "    radar:",
        "      graticuleOpacity: 0",
        "      graticuleColor: \"#828280\"",
        "      axisColor: \"#828280\"",
        "      graticuleStrokeWidth: 0.5",
        "      axisStrokeWidth: 0.5",
        "      curveOpacity: 0.3",
        "---",
        "radar-beta",
        `  axis ${axes.join(", ")}`,
        `  curve before["${base_label}"]{${all_metrics().map((m) -> { "100" }).join(", ")}}`,
        `  curve after["${ctx.head_sha.slice(0, 7)}"]{${values.join(", ")}}`,
        `  max ${top}`,
        "  min 0",
        "  ticks 3",
        "```",
        "",
    ]
}

/// Whether a metric moved enough to be worth a reviewer's attention: by
/// `significant_step()` for cognitive and cyclomatic, by 2 for nesting and
/// exits, and by half or double for NPath, which multiplies rather than adds.
function significant_change(change: MetricChange) -> bool {
    let smaller = if (change.before < change.after) {
        change.before
    } else {
        change.after
    };
    let larger = if (change.before < change.after) {
        change.after
    } else {
        change.before
    };
    match (change.metric) {
        Metric.NPath => larger >= smaller * 2n && larger - smaller >= 4n,
        Metric.Nesting => larger - smaller >= 2n,
        Metric.Exits => larger - smaller >= 2n,
        _ => larger - smaller >= significant_step(),
    }
}

/// The smallest change in cognitive or cyclomatic complexity shown outright.
function significant_step() -> bigint {
    3n
}

function significant(change: FunctionChange) -> bool {
    change.changes.some((m) -> {
        significant_change(m)
    })
}

/// The comment body. A null comparison means the base could not be measured.
function render(comparison: Comparison?, ctx: Context) -> string {
    let lines = [marker(ctx.project)];
    match (comparison) {
        null => {
            lines.push(
                `Could not measure \`${ctx.base_label}\`, so there is nothing to compare against.`,
            );
            lines.push("");
        },
        let c: Comparison => {
            lines.push(headline(c));
            lines.push("");
            lines = lines.concat(radar(c, ctx)).concat(function_table(c, ctx));
            lines.push(explanations());
            lines.push("");
        },
    }
    lines.push(
        `<sub>Compared \`${ctx.head_sha.slice(0, 7)}\` with \`${ctx.base_label}\` using \`baml codequality\`. This comment updates on every push.</sub>`,
    );
    lines.join("\n") + "\n"
}
