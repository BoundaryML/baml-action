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

function table_header() -> string[] {
    let labels = all_metrics().map((m) -> {
        m.to_string()
    });
    [
        `| Function | ${labels.join(" | ")} |`,
        `| --- |${all_metrics().map((m) -> { " ---: |" }).join("")}`,
    ]
}

function overflow(count: int) -> string[] {
    if (count > max_rows()) {
        [`...and ${count - max_rows()} more.`, ""]
    } else {
        []
    }
}

function change_cell(change: FunctionChange, metric: Metric) -> string {
    match (
        change.changes.find((c) -> {
            c.metric == metric
        })
    ) {
        let c: MetricChange => `${c.before} **&rarr;** ${c.after}`,
        null => "",
    }
}

function change_table(changes: FunctionChange[], ctx: Context) -> string[] {
    let lines = table_header();
    for (let change in changes.slice(0, max_rows())) {
        let cells = all_metrics().map((m) -> {
            change_cell(change, m)
        });
        lines.push(`| ${function_link(change.report, ctx)} | ${cells.join(" | ")} |`);
    }
    lines.push("");
    lines.concat(overflow(changes.length()))
}

function added_table(functions: FunctionReport[], ctx: Context) -> string[] {
    let lines = table_header();
    for (let f in functions.slice(0, max_rows())) {
        let cells = all_metrics().map((m) -> {
            metric_value(f, m).to_string()
        });
        lines.push(`| ${function_link(f, ctx)} | ${cells.join(" | ")} |`);
    }
    lines.push("");
    lines.concat(overflow(functions.length()))
}

function collapsed(summary: string, body: string[]) -> string[] {
    ["<details>", `<summary>${summary}</summary>`, ""].concat(body).concat(["</details>", ""])
}

function headline(comparison: Comparison) -> string {
    if (!changed(comparison)) {
        return "**No function changed complexity.**";
    }
    let worse = comparison.worse.length();
    let better = comparison.better.length();
    let parts: string[] = [];
    if (worse > 0) {
        parts.push(`**${plural(worse, "function")} got worse.**`);
    } else {
        parts.push("**No function got worse.**");
    }
    if (better > 0) {
        parts.push(
            if (worse > 0) {
                `${better} got better.`
            } else {
                `${plural(better, "function")} got better.`
            },
        );
    }
    if (comparison.added.length() > 0) {
        parts.push(`${plural(comparison.added.length(), "new function")}.`);
    }
    if (comparison.removed > 0) {
        parts.push(`${plural(comparison.removed, "function")} removed.`);
    }
    parts.join(" ")
}

function marker(project: string) -> string {
    `<!-- baml-action:codequality:${project} -->`
}

/// The comment body. A null comparison means the base could not be measured.
function render(comparison: Comparison?, ctx: Context) -> string {
    let lines = [marker(ctx.project), "### Complexity check", ""];
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
            if (c.worse.length() > 0) {
                lines = lines.concat(change_table(c.worse, ctx));
            }
            if (c.better.length() > 0) {
                lines
                    = lines.concat(
                        collapsed(
                            `${plural(c.better.length(), "function")} got better`,
                            change_table(c.better, ctx),
                        ),
                    );
            }
            if (c.added.length() > 0) {
                lines
                    = lines.concat(
                        collapsed(plural(c.added.length(), "new function"), added_table(c.added, ctx)),
                    );
            }
            lines.push(explanations());
            lines.push("");
        },
    }
    lines.push(
        `<sub>Compared \`${ctx.head_sha.slice(0, 7)}\` with \`${ctx.base_label}\` using \`baml codequality\`. This comment updates on every push.</sub>`,
    );
    lines.join("\n") + "\n"
}
