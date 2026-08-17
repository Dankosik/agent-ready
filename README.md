# agent-ready

![license MIT](https://img.shields.io/badge/license-MIT-blue)
![platform macOS](https://img.shields.io/badge/platform-macOS-lightgrey)
![13 generic tools](https://img.shields.io/badge/generic_tools-13-brightgreen)

Reliable command-line tooling for Claude Code, Codex, and Cursor on macOS.

`agent-ready` installs a small, language-independent CLI toolkit and adds the routing instructions that make coding agents use it. Each generic tool must prevent a real failure or produce a measurable improvement, with a local comparison you can run.

```bash
git clone https://github.com/Dankosik/agent-ready.git
cd agent-ready
./install.sh
```

Requirements: macOS and [Homebrew](https://brew.sh/).

## The problem

Coding agents usually choose familiar commands, not the best command available on the machine. On macOS, a familiar Linux command can fail even when it looks correct:

```console
$ echo hello > /tmp/demo
$ sed -i 's/hello/world/' /tmp/demo 2>/dev/null; echo $?
1
$ cat /tmp/demo
hello
```

The GNU-style `sed -i` form that agents commonly write exits with an error and leaves the file unchanged with BSD `sed`. Other failures are less visible: recursive `grep` searches Git metadata and ignored files, regex misses code split across lines, and large command output consumes context without helping the task.

Installing better tools solves only half of the problem. In the transcript sample used for this repository, across 277,325 shell commands from 1,125 agent sessions, agents used `grep` 21,878 times and `rg` 8,117 times even when ripgrep was available.

The agent needs both the tool and an instruction that routes the right task to it.

## How it works

`./install.sh` performs two jobs:

1. Homebrew installs 13 generic tools from the root [`Brewfile`](Brewfile).
2. The installer adds the routing rules from [`agent-routing.md`](agent-routing.md) to every supported agent it finds.

The managed rules are written to:

```text
~/.claude/CLAUDE.md
~/.codex/AGENTS.md
~/.cursor/AGENTS.md
```

They live between `<!-- agent-ready:start -->` and `<!-- agent-ready:end -->`. Existing content outside those markers stays untouched. Run the installer again to update the tools and refresh the managed block without duplicating it.

To refresh only the instructions:

```bash
./install.sh --configure-only
```

`rtk` needs no routing rule because it hooks shell calls directly. Language servers register through their own adapters.

## What gets installed

The first five cover the broadest and most common failure modes.

| Tool | Job |
|---|---|
| [`rtk`](https://github.com/rtk-ai/rtk) | Filters verbose command output before it reaches the model |
| [`uv`](https://docs.astral.sh/uv/) | Runs Python scripts with temporary dependencies instead of modifying system Python |
| [`sd`](https://github.com/chmln/sd) | Replaces text without the BSD/GNU `sed -i` mismatch |
| [`ripgrep`](https://github.com/BurntSushi/ripgrep) | Searches repository content while respecting ignore rules |
| [`ast-grep`](https://ast-grep.github.io/) | Searches and rewrites parsed code instead of matching source text with regex |

The remaining tools cover narrower safety, feedback, and measurement cases.

| Tool | Job |
|---|---|
| [`gh`](https://cli.github.com/) | Reads typed GitHub data instead of scraping HTML |
| [`jq`](https://jqlang.org/) | Reads and transforms JSON safely |
| [`gitleaks`](https://github.com/gitleaks/gitleaks) | Detects secrets in the working tree and Git history before they are pushed |
| [`actionlint`](https://github.com/rhysd/actionlint) | Checks GitHub Actions workflows locally |
| [`shellcheck`](https://www.shellcheck.net/) | Finds shell errors before runtime or CI |
| [`difftastic`](https://difftastic.wilfred.me.uk/) | Produces syntax-aware diffs with less irrelevant output |
| [`yq`](https://mikefarah.gitbook.io/yq/) | Reads and edits YAML, TOML, and XML without line-based parsing |
| [`hyperfine`](https://github.com/sharkdp/hyperfine) | Benchmarks commands with warmups and repeated runs |

This is intentionally a short list. Convenience alone is not enough for a tool to enter the generic `Brewfile`.

## Verify the claims

Run the tools against the alternatives an agent would normally choose:

```bash
./verify.sh
```

The script creates temporary fixtures, prints both results, and removes the fixtures when it exits. It does not install, remove, or configure anything.

Examples covered by the verification script include:

| Without the tool | With the tool |
|---|---|
| `grep -R` mixes source, ignored files, and Git metadata | `rg` returns repository content |
| regex matches a comment and misses a multiline call | `ast-grep` returns both real calls |
| `sed -i` leaves a macOS file unchanged | `sd` performs the replacement |
| a secret enters Git history | `gitleaks` identifies the rule, file, and commit |
| a workflow typo requires a push and CI run | `actionlint` reports it locally |

The `gh` check is included even though HTML scraping returns the correct value in its fixture. It demonstrates the difference between a typed API field and a large response tied to current page markup.

### Difftastic needs one explicit option

Use its inline display for agent output:

```bash
git -c diff.external='difft --display inline' diff
```

The default side-by-side view is designed for a human terminal and can be larger than `git diff`. `./verify.sh` reports the raw, default, and inline sizes for its current fixture.

### rtk reports an estimate

`rtk gain` measures commands it proxied, but it cannot see later shell filters such as `| head -20`. Treat the aggregate as indicative. `./verify.sh` compares raw and filtered output for one controlled command instead.

## Language adapters

Language-specific tools stay outside the generic `Brewfile`. Each adapter has its own installer and verification command.

### Go

```bash
./languages/go/install.sh
./languages/go/verify.sh
```

The Go adapter installs the official [`gopls`](https://go.dev/gopls/features/mcp) language server and registers `gopls mcp` with each supported agent it finds. It gives the agent compiler-backed workspace discovery, diagnostics, references, rename, code search, and vulnerability checks.

The MCP surface is experimental and may change. It can run Go commands, download modules into the Go cache, and query the vulnerability database when requested, so give it the same access you would give local project tooling.

To register an existing `gopls` installation without running Homebrew:

```bash
./languages/go/install.sh --configure-only
```

## Scope

- macOS with Homebrew is the only supported platform today.
- The root installer contains only language-independent tools. Language integrations live under `languages/<name>/`.
- The project owns no tools in the list. A tool can be replaced or removed when a better option has evidence behind it.
- A Brewfile is not a lockfile. Homebrew installs current formula versions.

Generic snapshot checked on 2026-08-17: rtk 0.45.0, uv 0.11.1, sd 1.1.0, ripgrep 15.2.0, ast-grep 0.45.1, gitleaks 8.30.1, actionlint 1.7.12, shellcheck 0.11.0, difftastic 0.70.0, yq 4.53.3, and hyperfine 1.20.0. The Go adapter was checked with gopls 0.23.0.

Pull requests that add a tool should include a runnable proof of the failure it prevents or the improvement it makes.

<details>
<summary>Considered and rejected</summary>

| Tool | Why it is not included |
|---|---|
| `comby` | Deprecated upstream; `ast-grep` covers the use case |
| `watchexec` | An agent runs commands explicitly and does not consume background watcher output |
| `scc`, `tokei` | Repository statistics do not prevent a common failure |
| `delta` | Improves human diff presentation but adds no actionable information for an agent |
| `files-to-prompt` | Agents already read files directly |
| `claude-code-otel` | Claude Code exports OTLP natively |
| `packnplay` | The repository has no license that grants reuse |
| `semgrep` | Overlaps the project-specific linters that should remain the source of truth |

</details>

## License

[MIT](LICENSE)
