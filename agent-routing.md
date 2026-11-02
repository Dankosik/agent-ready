Tool routing (use instead of defaults):
- Shell: prefix commands with `rtk`; `rtk proxy <cmd>` for exact output.
- Search: `rg` text, `rg --files` files; code structure (calls, declarations, loops, branches): `ast-grep run -l <lang> -p '<pattern>'`, even where a regex fits.
- Edit: `sd 'old' 'new' <file>`; temporary Python deps: `uv run --with <pkg>`.
- Data: `jq` JSON, `yq` YAML/TOML/XML, `gh api --jq` GitHub.
- Worktrees: `wt list` first, then Worktrunk; `wt <cmd> --help` before mutating.
- Read: `mdq <query> <file>` Markdown sections; `git -c diff.external='difft --display inline' diff` code diffs.
- Check: `shellcheck` shell, `actionlint` workflows, `gitleaks dir|git --redact .` files|history.
- Timing: `hyperfine --warmup 3`.
- Code graph: index of symbols, calls, imports. With `.codegraph/`, first ask `codegraph_explore` (MCP) or `codegraph explore "<question>"` how code works, who calls what, what a change affects; trust its source unless flagged stale. No index: normal routing; never `codegraph init` unasked.
