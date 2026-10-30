# Contributing

Before opening a pull request, run:

```sh
baml --project codequality test
shellcheck scripts/*.sh
actionlint
```

The code quality comment is rendered by the BAML project in `codequality`, which pins its own toolchain in `codequality/baml.toml` so a user's toolchain choice can't break it. Bump that pin when the renderer needs a newer BAML.

Pull requests run the action against the fixture projects in `test/fixtures` on Linux, macOS, and Windows. The Linux run posts the code quality comment on the pull request itself.

Installing and selecting BAML belongs in [`setup-baml`](https://github.com/BoundaryML/setup-baml). To pick up a change there, update the pinned commit in `action.yml`; Dependabot proposes these updates monthly.
