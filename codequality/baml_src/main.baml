/// The comment body, and whether it is worth posting a new comment for.
class Rendered {
    body: string,
    changed: bool,
}

/// Unparseable base text means the base could not be measured, not that the
/// action failed; unparseable head text is an error.
function render_reports(base_text: string?, head_text: string, ctx: Context) -> Rendered {
    let head = parse_report(head_text);
    let base = match (base_text) {
        null => null,
        let text: string => {
            parse_report(text) catch (e) {
                baml.json.ParseError => null,
                baml.json.DecodeError => null,
            }
        },
    };
    match (base) {
        null => Rendered { body: render(null, ctx), changed: true },
        let b: Report => {
            let comparison = compare(b, head);
            Rendered { body: render(comparison, ctx), changed: changed(comparison) }
        },
    }
}

/// `project_prefix` from `git rev-parse --show-prefix`, which may be `.` or
/// use backslashes on Windows, as `Context.project_prefix` wants it.
function normalize_prefix(prefix: string) -> string {
    let trimmed = prefix.replace_all("\\", "/")
        .split("/")
        .filter((part) -> {
            part != "" && part != "."
        })
        .join("/");
    if (trimmed == "") {
        ""
    } else {
        `${trimmed}/`
    }
}

function read_if_exists(path: string?) -> string? {
    match (path) {
        null => null,
        let p: string => {
            if (baml.fs.exists(p)) {
                baml.fs.read(p)
            } else {
                null
            }
        },
    }
}

/// Writes the comment body comparing two `baml codequality --output-format json`
/// reports to `out`, and prints `changed` or `unchanged` so the caller can skip
/// posting a comment that would only say nothing happened. A missing or
/// unreadable `base` renders as "could not measure".
function main(
    head: string,
    out: string,
    server_url: string,
    repo: string,
    head_sha: string,
    base_label: string,
    base: string? = null,
    project_prefix: string = "",
    project: string = ".",
) -> null {
    let ctx = Context {
        server_url: server_url.trim_end().replace(baml.regex.new("/+$"), ""),
        repo: repo,
        head_sha: head_sha,
        base_label: base_label,
        project_prefix: normalize_prefix(project_prefix),
        project: project,
    };
    let rendered = render_reports(read_if_exists(base), baml.fs.read(head), ctx);
    let _ = baml.fs.write(out, rendered.body);
    baml.io.println(
        if (rendered.changed) {
            "changed"
        } else {
            "unchanged"
        },
    );
    null
}
