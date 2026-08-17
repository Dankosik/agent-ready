# agent-ready — set up a machine for coding with AI agents.
# Install:  brew bundle
#
# Every entry earns its line: it either prevents a class of wrong-but-quiet
# result, or measurably changes how well an agent works. Tools that only save
# a human keystrokes were left out. The reasoning and a runnable proof for each
# one live in README.md, along with what was rejected and why.

# Proxy that filters verbose command output before it reaches the model.
# Token cost is the binding constraint on how long an agent can stay useful.
brew "rtk"

# Structural search and rewrite over a parsed syntax tree.
# Regex silently misses code split across lines and silently matches comments.
brew "ast-grep"

# Find-and-replace with literal and PCRE modes.
# BSD sed on macOS rejects the GNU `sed -i 's/…/…/' file` form every agent writes.
brew "sd"

# Static analysis for shell.
# Agent-written shell fails late, in production, on the branch nobody reran.
brew "shellcheck"

# Diff by syntax tree instead of by line.
# Reformatting and import reordering are indistinguishable from real edits otherwise.
brew "difftastic"

# YAML/TOML/XML processor that preserves comments and anchors.
# Line-based edits to config files drop comments or produce valid-but-different files.
brew "yq"

# JSON processor.
# Agents parse JSON tool output constantly; regex over JSON breaks on nesting and escapes.
brew "jq"

# GitHub CLI.
# Agents reach for PRs, issues and CI status; without it they scrape HTML or guess.
brew "gh"

# Statistical command-line benchmarking.
# "It got faster" without a measurement is a claim, not a result.
brew "hyperfine"
