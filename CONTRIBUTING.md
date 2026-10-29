# Contributing

Before opening a pull request, run:

```sh
python3 -m unittest discover -s test
shellcheck scripts/*.sh
actionlint
```

Pull requests run the action against the fixture projects in `test/fixtures` on Linux, macOS, and Windows. The Linux run posts the code quality comment on the pull request itself.

Installing and selecting BAML belongs in [`setup-baml`](https://github.com/BoundaryML/setup-baml). To pick up a change there, update the pinned commit in `action.yml`; Dependabot proposes these updates monthly.
