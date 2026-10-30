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
        let r = Report { functions: [fn_report("a", cognitive = 3)] };
        let comparison = compare(r, r);
        assert.equal(comparison, Comparison { worse: [], better: [], added: [], removed: 0 });
        assert.equal(changed(comparison), false)
    }

    test "one row per function with every changed metric" {
        let comparison = compare(
            Report { functions: [fn_report("a", cognitive = 2, nesting = 1, exits = 3)] },
            Report { functions: [fn_report("a", cognitive = 5, nesting = 2, exits = 1)] },
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
        let comparison = compare(
            Report { functions: [fn_report("a", cognitive = 5)] },
            Report { functions: [fn_report("a", cognitive = 1)] },
        );
        assert.equal(comparison.worse, []);
        assert.equal(names(comparison.better), ["a"])
    }

    test "worse sorted by relative increase" {
        let comparison = compare(
            Report {
                functions: [fn_report("small", cognitive = 10), fn_report("big", cognitive = 1)],
            },
            Report {
                functions: [fn_report("small", cognitive = 12), fn_report("big", cognitive = 4)],
            },
        );
        assert.equal(names(comparison.worse), ["big", "small"])
    }

    test "worse sorted by the largest metric increase" {
        let comparison = compare(
            Report {
                functions: [
                    fn_report("steady", cognitive = 10, nesting = 1),
                    fn_report("spiky", cognitive = 10, nesting = 1),
                ],
            },
            Report {
                functions: [
                    fn_report("steady", cognitive = 15, nesting = 1),
                    fn_report("spiky", cognitive = 11, nesting = 4),
                ],
            },
        );
        assert.equal(names(comparison.worse), ["spiky", "steady"])
    }

    test "increase from zero is worse" {
        let comparison = compare(
            Report { functions: [fn_report("a", cognitive = 0)] },
            Report { functions: [fn_report("a", cognitive = 1)] },
        );
        assert.equal(
            comparison.worse[0].changes,
            [MetricChange { metric: Metric.Cognitive, before: 0n, after: 1n }],
        )
    }

    test "same name in different files are different functions" {
        let comparison = compare(
            Report { functions: [fn_report("a", file = "x.baml", cognitive = 1)] },
            Report {
                functions: [
                    fn_report("a", file = "x.baml", cognitive = 1),
                    fn_report("a", file = "y.baml", cognitive = 9),
                ],
            },
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
        let comparison = compare(
            Report { functions: [fn_report("gone")] },
            Report { functions: [fn_report("fresh", cognitive = 4)] },
        );
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
            Report { functions: [fn_report("a", npath = huge), fn_report("b", npath = 2n)] },
            Report { functions: [fn_report("a", npath = huge * 3n), fn_report("b", npath = 4n)] },
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
    test "worse function is one row with an arrow per changed metric" {
        let comparison = compare(
            Report {
                functions: [
                    fn_report("Router.dispatch", start_line = 10, end_line = 40, cognitive = 9, nesting = 2),
                    fn_report("Pipeline.run", cognitive = 22),
                ],
            },
            Report {
                functions: [
                    fn_report("Router.dispatch", start_line = 10, end_line = 42, cognitive = 18, nesting = 1),
                    fn_report("Pipeline.run", cognitive = 8),
                ],
            },
        );
        let body = render(comparison, test_context());
        assert.is_true(
            body.starts_with("<!-- baml-action:codequality:. -->\n### Complexity check\n"),
        );
        assert.contains(body, "**1 function got worse.** 1 got better.");
        assert.contains(
            body,
            "| [`Router.dispatch`](https://github.com/acme/app/blob/a41c9e2f00000000000000000000000000000000/baml_src/main.baml#L10-L42) | 9 **&rarr;** 18 |  |  | 2 **&rarr;** 1 |  |",
        );
        assert.contains(body, "<summary>1 function got better</summary>");
        assert.contains(body, "#### What these mean");
        assert.contains(body, "Compared `a41c9e2` with `canary` using `baml codequality`.")
    }

    test "nothing worse" {
        let comparison = compare(
            Report { functions: [fn_report("a", cognitive = 5)] },
            Report { functions: [fn_report("a", cognitive = 1)] },
        );
        assert.contains(
            render(comparison, test_context()),
            "**No function got worse.** 1 function got better.",
        )
    }

    test "project prefix in links and marker" {
        let ctx = test_context();
        ctx.project_prefix = "services/agent/";
        ctx.project = "services/agent";
        let body = render(compare(Report { functions: [] }, Report { functions: [fn_report("a")] }), ctx);
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
        let base = Report {
            functions: baml.Array.generate(count, (i) -> {
                fn_report(`f${i}`, cognitive = 1)
            }),
        };
        let head = Report {
            functions: baml.Array.generate(count, (i) -> {
                fn_report(`f${i}`, cognitive = 2)
            }),
        };
        let body = render(compare(base, head), test_context());
        assert.contains(body, "...and 3 more.");
        assert.equal(body.split("| 1 **&rarr;** 2 |").length() - 1, max_rows())
    }
}

testset "render_reports" {
    let head = `{"functions": [{"name": "a", "file": "baml_src/main.baml", "start_line": 1, "end_line": 3, "cognitive": 0, "cyclomatic": 1, "npath": 1, "nesting": 0, "exits": 1}]}`;

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
