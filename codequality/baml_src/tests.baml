function fn_report(
    name: string,
    file: string = "baml_src/main.baml",
    start_line: int = 1,
    end_line: int = 3,
    cognitive: int = 0,
    cyclomatic: int = 1,
    npath: bigint = 1n,
    nesting: int = 0,
    exits: int = 1,
) -> FunctionReport {
    FunctionReport {
        name: name,
        file: file,
        start_line: start_line,
        end_line: end_line,
        cognitive: cognitive,
        cyclomatic: cyclomatic,
        npath: npath,
        nesting: nesting,
        exits: exits,
    }
}

function report_of(functions: FunctionReport[]) -> Report {
    Report { functions: functions, files: [] }
}

function test_context() -> Context {
    Context {
        server_url: "https://github.com",
        repo: "acme/app",
        head_sha: "a41c9e2f00000000000000000000000000000000",
        base_label: "canary",
        project_prefix: "",
        project: ".",
    }
}

function names(changes: FunctionChange[]) -> string[] {
    changes.map((c) -> {
        c.report.name
    })
}

testset "compare" {
    test "unchanged reports nothing" {
        let r = report_of([fn_report("a", cognitive = 3)]);
        let comparison = compare(r, r);
        assert.equal(comparison.worse, []);
        assert.equal(comparison.better, []);
        assert.equal(comparison.added, []);
        assert.equal(comparison.removed, 0);
        assert.equal(changed(comparison), false)
    }

    test "one row per function with every changed metric" {
        let comparison = compare(
            report_of([fn_report("a", cognitive = 2, nesting = 1, exits = 3)]),
            report_of([fn_report("a", cognitive = 5, nesting = 2, exits = 1)]),
        );
        assert.equal(comparison.worse.length(), 1);
        assert.equal(comparison.better, []);
        assert.equal(
            comparison.worse[0].changes,
            [
                MetricChange { metric: Metric.Cognitive, before: 2n, after: 5n },
                MetricChange { metric: Metric.Nesting, before: 1n, after: 2n },
                MetricChange { metric: Metric.Exits, before: 3n, after: 1n },
            ],
        )
    }

    test "only improvements is better" {
        let comparison = compare(report_of([fn_report("a", cognitive = 5)]), report_of([fn_report("a", cognitive = 1)]));
        assert.equal(comparison.worse, []);
        assert.equal(names(comparison.better), ["a"])
    }

    test "worse sorted by relative increase" {
        let comparison = compare(
            report_of([fn_report("small", cognitive = 10), fn_report("big", cognitive = 1)]),
            report_of([fn_report("small", cognitive = 12), fn_report("big", cognitive = 4)]),
        );
        assert.equal(names(comparison.worse), ["big", "small"])
    }

    test "worse sorted by the largest metric increase" {
        let comparison = compare(
            report_of(
                [
                    fn_report("steady", cognitive = 10, nesting = 1),
                    fn_report("spiky", cognitive = 10, nesting = 1),
                ],
            ),
            report_of(
                [
                    fn_report("steady", cognitive = 15, nesting = 1),
                    fn_report("spiky", cognitive = 11, nesting = 4),
                ],
            ),
        );
        assert.equal(names(comparison.worse), ["spiky", "steady"])
    }

    test "increase from zero is worse" {
        let comparison = compare(report_of([fn_report("a", cognitive = 0)]), report_of([fn_report("a", cognitive = 1)]));
        assert.equal(
            comparison.worse[0].changes,
            [MetricChange { metric: Metric.Cognitive, before: 0n, after: 1n }],
        )
    }

    test "same name in different files are different functions" {
        let comparison = compare(
            report_of([fn_report("a", file = "x.baml", cognitive = 1)]),
            report_of(
                [
                    fn_report("a", file = "x.baml", cognitive = 1),
                    fn_report("a", file = "y.baml", cognitive = 9),
                ],
            ),
        );
        assert.equal(
            comparison.added.map((f) -> {
                f.file
            }),
            ["y.baml"],
        );
        assert.equal(comparison.worse, [])
    }

    test "added and removed" {
        let comparison = compare(report_of([fn_report("gone")]), report_of([fn_report("fresh", cognitive = 4)]));
        assert.equal(
            comparison.added.map((f) -> {
                f.name
            }),
            ["fresh"],
        );
        assert.equal(comparison.removed, 1);
        assert.is_true(changed(comparison))
    }

    test "npath beyond float range" {
        let huge = 10n.pow(400n);
        let comparison = compare(
            report_of([fn_report("a", npath = huge), fn_report("b", npath = 2n)]),
            report_of([fn_report("a", npath = huge * 3n), fn_report("b", npath = 4n)]),
        );
        assert.equal(names(comparison.worse), ["a", "b"])
    }
}

testset "parse_report" {
    test "decodes npath exactly and ignores other fields" {
        let report = parse_report(
            `{"functions": [{"name": "a", "file": "baml_src\\\\main.baml", "start_line": 1, "end_line": 3, "lines": 3, "params": 0, "cognitive": 0, "cyclomatic": 1, "npath": 123456789012345678901234567890, "nesting": 0, "exits": 1, "fan_in": 0, "fan_out": 0}], "files": []}`,
        );
        assert.equal(report.functions[0].npath, 123456789012345678901234567890n);
        assert.equal(report.functions[0].file, "baml_src/main.baml")
    }
}

testset "render" {
    test "significant functions are one row each, worse first" {
        let comparison = compare(
            report_of(
                [
                    fn_report("Router.dispatch", start_line = 10, end_line = 40, cognitive = 9, nesting = 2),
                    fn_report("Pipeline.run", cognitive = 22),
                ],
            ),
            report_of(
                [
                    fn_report("Router.dispatch", start_line = 10, end_line = 42, cognitive = 18, nesting = 1),
                    fn_report("Pipeline.run", cognitive = 8),
                ],
            ),
        );
        let body = render(comparison, test_context());
        assert.is_true(
            body.starts_with(
                "<!-- baml-action:codequality:. -->\n**1 function got worse**, 1 got better.\n",
            ),
        );
        assert.contains(
            body,
            "| [`Router.dispatch`](https://github.com/acme/app/blob/a41c9e2f00000000000000000000000000000000/baml_src/main.baml#L10-L42) | **Worse**: cognitive 9 &rarr; 18, nesting 2 &rarr; 1 |\n| [`Pipeline.run`]",
        );
        assert.contains(body, "| **Better**: cognitive 22 &rarr; 8 |");
        assert.contains(body, "<summary>What these mean</summary>");
        assert.contains(body, "Compared `a41c9e2` with `canary` using `baml codequality`.")
    }

    test "headline" {
        let one = report_of([fn_report("a", cognitive = 5)]);
        assert.equal(headline(compare(one, one)), "**No function changed complexity.**");
        assert.equal(
            headline(compare(one, report_of([fn_report("a", cognitive = 1)]))),
            "**No function got worse**, 1 got better.",
        );
        assert.equal(
            headline(
                compare(
                    Report {
                        functions: [fn_report("a"), fn_report("b")],
                        files: [file_report("x.baml", 35)],
                    },
                    Report {
                        functions: [fn_report("a"), fn_report("c")],
                        files: [file_report("x.baml", 42)],
                    },
                ),
            ),
            "**No function got worse**. 1 new, 1 removed. Lines 35 &rarr; 42.",
        )
    }

    test "small changes are left out" {
        let comparison = compare(
            report_of([fn_report("small", cognitive = 2), fn_report("big", cognitive = 2)]),
            report_of([fn_report("small", cognitive = 4), fn_report("big", cognitive = 5)]),
        );
        let body = render(comparison, test_context());
        assert.contains(body, "**2 functions got worse**.");
        assert.contains(body, "[`big`]");
        assert.is_true(!body.includes("[`small`]"))
    }

    test "no table when nothing changed significantly" {
        let comparison = compare(report_of([fn_report("a", cognitive = 2)]), report_of([fn_report("a", cognitive = 3)]));
        assert.is_true(!render(comparison, test_context()).includes("| Function |"))
    }

    test "project prefix in links and marker" {
        let ctx = test_context();
        ctx.project_prefix = "services/agent/";
        ctx.project = "services/agent";
        let body = render(compare(report_of([fn_report("a")]), report_of([fn_report("a", cognitive = 5)])), ctx);
        assert.contains(
            body,
            "/blob/a41c9e2f00000000000000000000000000000000/services/agent/baml_src/main.baml#L1-L3",
        );
        assert.is_true(body.starts_with("<!-- baml-action:codequality:services/agent -->"))
    }

    test "unmeasured base" {
        let body = render(null, test_context());
        assert.contains(body, "Could not measure `canary`");
        assert.is_true(!body.includes("What these mean"))
    }

    test "rows are capped" {
        let count = max_rows() + 3;
        let base = report_of(
            baml.Array.generate(count, (i) -> {
                fn_report(`f${i}`, cognitive = 1)
            }),
        );
        let head = report_of(
            baml.Array.generate(count, (i) -> {
                fn_report(`f${i}`, cognitive = 5)
            }),
        );
        let body = render(compare(base, head), test_context());
        assert.contains(body, "...and 3 more.");
        assert.equal(body.split("\n| [`f").length() - 1, max_rows())
    }
}

testset "render_reports" {
    let head = `{"functions": [{"name": "a", "file": "baml_src/main.baml", "start_line": 1, "end_line": 3, "cognitive": 0, "cyclomatic": 1, "npath": 1, "nesting": 0, "exits": 1}], "files": []}`;

    test "unchanged" {
        let rendered = render_reports(head, head, test_context());
        assert.equal(rendered.changed, false);
        assert.contains(rendered.body, "**No function changed complexity.**")
    }

    test "missing base is unmeasured" {
        let rendered = render_reports(null, head, test_context());
        assert.is_true(rendered.changed);
        assert.contains(rendered.body, "Could not measure")
    }

    test "garbage base is unmeasured" {
        let rendered = render_reports("error: not json", head, test_context());
        assert.is_true(rendered.changed);
        assert.contains(rendered.body, "Could not measure")
    }

    test "normalize_prefix" {
        assert.equal(normalize_prefix(""), "");
        assert.equal(normalize_prefix("."), "");
        assert.equal(normalize_prefix("services/agent/"), "services/agent/");
        assert.equal(normalize_prefix("services\\agent\\"), "services/agent/")
    }
}

function file_report(file: string, lines: int) -> FileReport {
    FileReport { file: file, lines: lines }
}

testset "summary" {
    test "summarize" {
        let summary = summarize(
            Report {
                functions: [
                    fn_report("a", cognitive = 3, nesting = 1, npath = 3n),
                    fn_report("b", cognitive = 12, nesting = 3, npath = 36n),
                ],
                files: [file_report("x.baml", 30), file_report("y.baml", 12)],
            },
        );
        assert.equal(summary.functions, 2);
        assert.equal(summary.lines, 42);
        assert.equal(average(summary, Metric.Cognitive), Ratio { numerator: 15n, denominator: 2n });
        assert.equal(average(summarize(report_of([])), Metric.NPath), null)
    }

    test "count reads as baml codequality writes it" {
        let max_u64 = 18446744073709551615n;
        assert.equal(
            [
                0n,
                999n,
                3170n,
                999999n,
                2700000n,
                273049159680n,
                9960000000000000000n,
                max_u64,
                max_u64 * 1000000000n,
            ]
                .map((n) -> {
                    count(n)
                }),
            ["0", "999", "3,170", "999,999", "2.7M", "273.0B", "1.0e19", "1.8e19", "1.8e28"],
        )
    }
}

testset "radar" {
    test "radar shows health relative to the base and capped" {
        let comparison = compare(
            report_of([fn_report("a", cognitive = 4, npath = 20n, nesting = 1)]),
            report_of([fn_report("a", cognitive = 8, npath = 2n, nesting = 0)]),
        );
        assert.equal(health_percent(comparison, Metric.Cognitive), 50n);
        assert.equal(health_percent(comparison, Metric.NPath), 1000n);
        assert.equal(health_percent(comparison, Metric.Nesting), null);
        assert.equal(health_percent(comparison, Metric.Exits), 100n);
        let body = render(comparison, test_context());
        assert.contains(
            body,
            `  axis cognitive["Readable 50%"], cyclomatic["Few branches 100%"], npath["Few paths 1,000%"], nesting["Flat >300%"], exits["Few exits 100%"]`,
        );
        assert.contains(body, `  curve before["canary"]{100, 100, 100, 100, 100}`);
        assert.contains(body, `  curve after["a41c9e2"]{50, 100, 300, 300, 100}`);
        assert.contains(body, "  max 300")
    }

    test "radar leaves room above the base" {
        let comparison = compare(report_of([fn_report("a", cognitive = 4)]), report_of([fn_report("a", cognitive = 8)]));
        assert.contains(render(comparison, test_context()), "  max 150")
    }

    test "no radar when no average moved or the base had no functions" {
        let same = report_of([fn_report("a", cognitive = 3)]);
        assert.is_true(!render(compare(same, same), test_context()).includes("mermaid"));
        assert.is_true(!render(compare(report_of([]), same), test_context()).includes("mermaid"))
    }
}

testset "significance" {
    test "npath must double" {
        assert.is_true(
            !significant_change(MetricChange { metric: Metric.NPath, before: 8n, after: 12n }),
        );
        assert.is_true(
            significant_change(MetricChange { metric: Metric.NPath, before: 8n, after: 16n }),
        );
        assert.is_true(
            !significant_change(MetricChange { metric: Metric.NPath, before: 1n, after: 2n }),
        );
        assert.is_true(
            significant_change(MetricChange { metric: Metric.NPath, before: 36n, after: 4n }),
        )
    }

    test "nesting and exits need two" {
        assert.is_true(
            !significant_change(MetricChange { metric: Metric.Nesting, before: 1n, after: 2n }),
        );
        assert.is_true(
            significant_change(MetricChange { metric: Metric.Exits, before: 3n, after: 1n }),
        )
    }
}
