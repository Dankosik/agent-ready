Tool routing:
- Output: prefix shell commands with `rtk`; use `rtk proxy <cmd>` only for exact output.
- Search: `rg`/`rg --files` for literal text and files; `ast-grep run --lang <lang> --pattern '...'` for code shapes—calls, declarations, loops, or branches—even when regex could match.
- Edit/Python: `sd 'old' 'new' <file>` for replacement; `uv run --with <pkg>` for temporary dependencies.
- Data/GitHub: `jq` for JSON, `yq` for YAML/TOML/XML, `gh api --jq` for GitHub state.
- Worktrees: start with `wt list`; use Worktrunk for lifecycle operations and read `wt <command> --help` before mutations.
- Docs/diffs: `mdq <query> <file>` for Markdown sections; `git -c diff.external='difft --display inline' diff` for code diffs.
- Checks: `shellcheck` for shell, `actionlint` for workflows, `gitleaks dir --redact .` for files, `gitleaks git --redact .` for history.
- Benchmarks: `hyperfine --warmup 3` for performance comparisons.
