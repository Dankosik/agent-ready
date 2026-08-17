# agent-ready — set up a machine for coding with AI agents.
# Install:  brew bundle
#
# Every entry earns its line: it either prevents a class of wrong-but-quiet
# result, or measurably changes how well an agent works. Tools that only save
# a human keystrokes were left out. The reasoning and a runnable proof for each
# one live in README.md, along with what was rejected and why.
#
# Run ./verify.sh to watch each one beat the alternative on your own machine.

# ---------------------------------------------------------------- start here
# These five carry most of the value. None depends on the agent remembering to
# reach for it at the right moment.

# Proxy that filters verbose command output before it reaches the model.
# Token cost is the binding constraint on how long an agent can stay useful.
brew "rtk"

# Python package and script runner.
# `pip install` into macOS system Python fails outright (externally-managed).
# The agent's fallbacks are all bad: a leaking venv, --break-system-packages,
# or giving up. `uv run --with X` is ephemeral and leaves nothing behind.
brew "uv"

# Find-and-replace with literal and PCRE modes.
# BSD sed on macOS rejects the GNU `sed -i 's/…/…/' file` form every agent writes.
brew "sd"

# Repository-aware recursive text search.
# BSD grep walks into .git and ignored files, and rejects common PCRE forms.
brew "ripgrep"

# Structural search and rewrite over a parsed syntax tree.
# Regex silently misses code split across lines and silently matches comments.
brew "ast-grep"

# ------------------------------------------------------------------ the rest
# Each closes a real case, but a narrower or more situational one.

# GitHub CLI.
# One typed field instead of half a megabyte of markup-pinned HTML.
brew "gh"

# JSON processor.
# Agents parse JSON tool output constantly; regex over JSON breaks on nesting and escapes.
brew "jq"

# Secret scanner for the working tree and full git history.
# Agents copy live values out of .env into fixtures to make a test pass, then
# commit them. Irreversible once pushed — the key has to be rotated, not removed.
brew "gitleaks"

# Static checker for GitHub Actions workflows.
# Without it the agent's only feedback on a workflow edit is push, wait, read CI.
# Also runs shellcheck over `run:` blocks, so it composes with the entry below.
brew "actionlint"

# Static analysis for shell.
# Agent-written shell fails late, in production, on the branch nobody reran.
brew "shellcheck"

# Diff by syntax tree instead of by line.
# Reformatting and import reordering are indistinguishable from real edits otherwise.
brew "difftastic"

# YAML/TOML/XML processor that preserves comments and anchors.
# Line-based edits to config files drop comments or produce valid-but-different files.
brew "yq"

# Markdown query tool.
# Heading-based reads survive line shifts and return one semantic section.
brew "mdq"

# Statistical command-line benchmarking.
# "It got faster" without a measurement is a claim, not a result.
brew "hyperfine"
