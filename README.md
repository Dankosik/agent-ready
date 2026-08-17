<h1 align="center">agent-ready</h1>

<p align="center"><strong>Reliable command-line tooling for popular coding agents on macOS.</strong></p>

<p align="center">
  <img alt="license MIT" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="platform macOS" src="https://img.shields.io/badge/platform-macOS-lightgrey">
  <img alt="15 generic tools" src="https://img.shields.io/badge/generic_tools-15-brightgreen">
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#why-it-exists">Why it exists</a> ·
  <a href="#how-it-works">How it works</a> ·
  <a href="#tools">Tools</a> ·
  <a href="#verification">Verification</a> ·
  <a href="#go-adapter">Go adapter</a>
</p>

`agent-ready` installs a small, language-independent CLI toolkit and adds the routing instructions that make coding agents use it. Each generic tool must prevent a real failure or produce a measurable improvement, with a local comparison you can run.

## Quick start

> [!NOTE]
> Requires macOS and [Homebrew](https://brew.sh/).

```bash
git clone https://github.com/Dankosik/agent-ready.git
cd agent-ready
./install.sh
```

Run the included comparisons after installation:

```bash
./verify.sh
```

## Why it exists

### Familiar commands can fail on macOS

An agent writes the GNU-style command it has seen most often:

```console
$ echo hello > /tmp/demo
$ sed -i 's/hello/world/' /tmp/demo 2>/dev/null; echo $?
1
$ cat /tmp/demo
hello
```

BSD `sed` exits with an error and leaves the file unchanged. Other failures are less obvious:

- recursive `grep` searches Git metadata and ignored files;
- regex misses code split across lines;
- verbose command output consumes context without helping the task.

### Installed tools can sit unused

Coding agents usually choose the command they already know. In the transcript sample used for this repository, 1,125 agent sessions produced 277,325 shell commands:

| Tool available | Agent used it | Familiar fallback | Agent used it |
|---|---:|---|---:|
| `ripgrep` | 8,117 times | `grep` | 21,878 times |

> [!IMPORTANT]
> A useful setup needs both the tools and instructions that route tasks to them. `agent-ready` installs both.

## How it works

```text
./install.sh
├── Brewfile
│   └── installs 15 generic tools
├── rtk init
│   └── installs each detected agent's native RTK integration
└── agent-routing.md
    ├── ~/.claude/CLAUDE.md
    ├── ~/.codex/AGENTS.md
    ├── ~/.gemini/GEMINI.md
    ├── ~/.copilot/copilot-instructions.md
    ├── ~/.codeium/windsurf/memories/global_rules.md
    └── ~/.cursor/hooks.json (sessionStart context)
```

The installer detects Claude Code, Codex, Cursor, Gemini CLI, GitHub Copilot CLI, and Windsurf. Routing rules live between `<!-- agent-ready:start -->` and `<!-- agent-ready:end -->`; existing content outside those markers stays untouched. Running the installer again refreshes the managed block instead of duplicating it. Cursor uses its documented global `sessionStart` hook because `AGENTS.md` is project-scoped there.

> [!TIP]
> If the tools are already installed, run `./install.sh --configure-only` to refresh only the instructions.

`rtk` is configured through its own agent-specific `rtk init` commands. Language servers register through their language adapters.

## Tools

### Core tools

These five cover the broadest failure modes.

| Tool | What it changes |
|---|---|
| [`rtk`](https://github.com/rtk-ai/rtk) | Filters verbose command output before it reaches the model |
| [`uv`](https://docs.astral.sh/uv/) | Runs Python scripts with temporary dependencies instead of modifying system Python |
| [`sd`](https://github.com/chmln/sd) | Replaces text without the BSD/GNU `sed -i` mismatch |
| [`ripgrep`](https://github.com/BurntSushi/ripgrep) | Searches repository content while respecting ignore rules |
| [`ast-grep`](https://ast-grep.github.io/) | Searches and rewrites parsed code instead of matching source text with regex |

### Safety and local feedback

| Tool | What it catches |
|---|---|
| [`gitleaks`](https://github.com/gitleaks/gitleaks) | Secrets in the working tree and Git history before they are pushed |
| [`actionlint`](https://github.com/rhysd/actionlint) | GitHub Actions errors before a CI run |
| [`shellcheck`](https://www.shellcheck.net/) | Shell errors before runtime or CI |

### Data, GitHub, worktrees, and measurement

| Tool | What it changes |
|---|---|
| [`gh`](https://cli.github.com/) | Reads typed GitHub data instead of scraping HTML |
| [`worktrunk`](https://worktrunk.dev/) | Shows worktree state and manages safe create, switch, merge, and removal workflows |
| [`jq`](https://jqlang.org/) | Reads and transforms JSON safely |
| [`yq`](https://mikefarah.gitbook.io/yq/) | Reads and edits YAML, TOML, and XML without line-based parsing |
| [`mdq`](https://github.com/yshavit/mdq) | Reads Markdown sections by heading instead of stale line ranges |
| [`difftastic`](https://difftastic.wilfred.me.uk/) | Produces syntax-aware diffs with less irrelevant output |
| [`hyperfine`](https://github.com/sharkdp/hyperfine) | Benchmarks commands with warmups and repeated runs |

Convenience alone is not enough for a tool to enter the generic [`Brewfile`](Brewfile).

## Verification

```bash
./verify.sh
./test-install.sh
```

`verify.sh` compares each tool with its familiar fallback. `test-install.sh` runs the installer twice against an isolated home directory and checks preservation, replacement, deduplication, symlink handling, malformed-marker safety, Cursor hook merging, and RTK initialization. Neither script changes your real agent configuration.

| Without the tool | With the tool |
|---|---|
| `grep -R` mixes source, ignored files, and Git metadata | `rg` returns repository content |
| regex matches a comment and misses a multiline call | `ast-grep` returns both real calls |
| `sed -i` leaves a macOS file unchanged | `sd` performs the replacement |
| a secret enters Git history | `gitleaks` identifies the rule, file, and commit |
| a workflow typo requires a push and CI run | `actionlint` reports it locally |
| `git worktree list` omits dirty and divergence state | `wt list` returns one structured worktree inventory |
| a shifted Markdown file makes a cached line range read the wrong text | `mdq` selects the complete section by heading |

<details>
<summary><strong>Verification notes for gh, difftastic, and rtk</strong></summary>

### GitHub CLI

The `gh` check is included even though HTML scraping returns the correct value in its fixture. It compares a typed API field with a large response tied to current page markup.

### Difftastic

Use the inline display for agent output:

```bash
git -c diff.external='difft --display inline' diff
```

The default side-by-side view is designed for a human terminal and can be larger than `git diff`. `./verify.sh` reports the raw, default, and inline sizes for its current fixture.

### rtk

`rtk gain` measures commands it proxied, but it cannot see later shell filters such as `| head -20`. Treat the aggregate as indicative. `./verify.sh` compares raw and filtered output for one controlled command instead.

</details>

## Go adapter

Language-specific tools stay outside the generic `Brewfile`. The Go adapter has its own installation and verification path:

```bash
./languages/go/install.sh
./languages/go/verify.sh
```

It installs the official [`gopls`](https://go.dev/gopls/features/mcp) language server and registers `gopls mcp` with each supported agent it finds. This gives the agent compiler-backed workspace discovery, symbol search, file and package context, references, diagnostics, and vulnerability checks.

`gopls` does not publish its model instructions automatically. Installing the Go adapter enables its own managed routing line; the language-independent installer does not load language instructions. The route stays concise: use gopls for build-aware Go semantics, `rg` for literal text, and `ast-grep` for syntax shapes.

To register an existing `gopls` installation without running Homebrew:

```bash
./languages/go/install.sh --configure-only
```

> [!NOTE]
> The MCP surface is experimental and may change. It can run Go commands, download modules into the Go cache, and query the vulnerability database when requested. Give it the same access you would give local project tooling.

## Project boundaries

- macOS with Homebrew is the only supported platform today.
- The root installer contains only language-independent tools. Language integrations live under `languages/<name>/`.
- The project owns no tools in the list. A tool can be replaced or removed when a better option has evidence behind it.
- A Brewfile is not a lockfile. Homebrew installs current formula versions.

Pull requests that add a tool should include a runnable proof of the failure it prevents or the improvement it makes.

<details>
<summary><strong>Verified versions, 2026-08-18</strong></summary>

Generic tools: rtk 0.45.0, uv 0.11.1, sd 1.1.0, ripgrep 15.2.0, ast-grep 0.45.1, gitleaks 8.30.1, actionlint 1.7.12, shellcheck 0.11.0, difftastic 0.70.0, yq 4.53.3, mdq 0.10.0, worktrunk 0.74.0, and hyperfine 1.20.0.

Go adapter: gopls 0.23.0.

</details>

<details>
<summary><strong>Considered and rejected</strong></summary>

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
