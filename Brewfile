# agent-toolkit — CLI tools that stop coding agents from failing silently.
# Install:  brew bundle
#
# Every entry below prevents a class of wrong-but-quiet result, not a class of
# inconvenience. The reasoning and a reproducible proof for each one live in
# README.md. Tools that only save keystrokes were deliberately left out; see
# "Considered and rejected" there.

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
