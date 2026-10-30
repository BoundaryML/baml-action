/// One function in the report of `baml codequality --output-format json`.
/// Fields of the report not listed here are ignored.
class FunctionReport {
    name: string,
    file: string,
    start_line: int,
    end_line: int,
    cognitive: int,
    cyclomatic: int,
    npath: bigint,
    nesting: int,
    exits: int,
}

class Report {
    functions: FunctionReport[],
}

enum Metric {
    Cognitive,
    Cyclomatic,
    NPath,
    Nesting,
    Exits,
}

/// The metrics in the order the comment shows and explains them.
function all_metrics() -> Metric[] {
    [Metric.Cognitive, Metric.Cyclomatic, Metric.NPath, Metric.Nesting, Metric.Exits]
}

function metric_value(report: FunctionReport, metric: Metric) -> bigint {
    match (metric) {
        Metric.Cognitive => 0n + report.cognitive,
        Metric.Cyclomatic => 0n + report.cyclomatic,
        Metric.NPath => report.npath,
        Metric.Nesting => 0n + report.nesting,
        Metric.Exits => 0n + report.exits,
    }
}

function parse_report(text: string) -> Report throws baml.json.ParseError | baml.json.DecodeError {
    let report = baml.json.decode<Report>(text);
    for (let f in report.functions) {
        f.file = f.file.replace_all("\\", "/");
    }
    report
}
