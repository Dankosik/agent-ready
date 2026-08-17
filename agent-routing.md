Tool routing. These are installed and measurably better than the default choice:

- Structural code search or rewrite: `ast-grep --lang <lang> --pattern '...'`. A regex misses code split across lines and reports "no matches" without erroring.
- Text search: `rg`, not `grep`. Plain `grep -r` descends into `.git` and ignored files.
- In-place replace: `sd 'old' 'new' <file>`. On macOS `sed -i 's/…/…/' file` does not edit the file.
- Python with third-party packages: `uv run --with <pkg> script.py`. `pip install` fails on macOS system Python, and every workaround leaves state behind.
- Reading diffs: `git -c diff.external='difft --display inline' diff`. Smaller output than plain `git diff` whatever the diff looks like; the bare `difft` default is the opposite.
- Structured data: `jq` for JSON, `yq` for YAML and TOML. Never a regex — both break on nesting, escaping and key order.
- GitHub state: `gh api <path> --jq <filter>`. Do not fetch and scrape HTML.
- Before calling a shell script done: `shellcheck <file>`. Before calling a workflow done: `actionlint <file>`.
