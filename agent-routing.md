Tool routing:
- Output: prefix shell commands with `rtk`; use `rtk proxy <cmd>` only for exact output.
- Search: `rg`/`rg --files` for text/files; `ast-grep --lang <lang> --pattern '...'` for structural or multiline code.
- Edit/Python: `sd 'old' 'new' <file>` for replacement; `uv run --with <pkg>` for temporary dependencies.
- Data/GitHub: `jq` for JSON, `yq` for YAML/TOML/XML, `gh api --jq` for GitHub state.
- Docs/diffs: `mdq <query> <file>` for Markdown sections; `git -c diff.external='difft --display inline' diff` for code diffs.
- Checks: `shellcheck` for shell, `actionlint` for workflows, `gitleaks dir --redact .` for files, `gitleaks git --redact .` for history.
- Benchmarks: `hyperfine --warmup 3` for performance comparisons.
