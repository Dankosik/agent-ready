# agent-ready

**A practical macOS toolchain for AI coding agents.**

`agent-ready` installs reliable command-line tools and teaches your coding
agents when to use them. It helps agents search, edit, validate, and inspect a
repository without common macOS command incompatibilities or unnecessarily
verbose output.

It supports Claude Code, Codex, Cursor, Gemini CLI, GitHub Copilot CLI, and
Windsurf.

## Install

Requirements: macOS and [Homebrew](https://brew.sh/).

```bash
git clone https://github.com/Dankosik/agent-ready.git
cd agent-ready
./install.sh
```

The installer:

1. installs 15 language-independent CLI tools;
2. detects the coding agents already installed on your machine;
3. adds concise tool-routing rules to their global configuration.

Existing configuration is preserved. Managed instructions are updated in
place when you run the installer again.

If the tools are already installed and you only want to refresh agent
configuration:

```bash
./install.sh --configure-only
```

## What you get

| Task | Tools |
|---|---|
| Compact command output | [`rtk`](https://github.com/rtk-ai/rtk) |
| Search and edit | [`ripgrep`](https://github.com/BurntSushi/ripgrep), [`ast-grep`](https://ast-grep.github.io/), [`sd`](https://github.com/chmln/sd) |
| Python and structured data | [`uv`](https://docs.astral.sh/uv/), [`jq`](https://jqlang.org/), [`yq`](https://mikefarah.gitbook.io/yq/), [`mdq`](https://github.com/yshavit/mdq) |
| Git and GitHub | [`gh`](https://cli.github.com/), [`worktrunk`](https://worktrunk.dev/), [`difftastic`](https://difftastic.wilfred.me.uk/) |
| Local checks | [`gitleaks`](https://github.com/gitleaks/gitleaks), [`actionlint`](https://github.com/rhysd/actionlint), [`shellcheck`](https://www.shellcheck.net/), [`hyperfine`](https://github.com/sharkdp/hyperfine) |

Installing tools alone is not enough: agents tend to reuse familiar commands
such as `grep` and GNU-style `sed`, even when those commands are noisy or
incompatible with macOS. The bundled [routing rules](agent-routing.md) direct
each task to the appropriate tool.

## Go support

Go tooling is optional and has a separate installer:

```bash
./languages/go/install.sh
```

It installs the official [`gopls`](https://go.dev/gopls/features/mcp) language
server and registers `gopls mcp` with supported agents. This gives agents
compiler-aware symbol search, references, diagnostics, and vulnerability
checks.

To configure an existing `gopls` installation without Homebrew:

```bash
./languages/go/install.sh --configure-only
```

The gopls MCP interface is experimental and may run Go commands, download
modules, or query the vulnerability database when requested.

## Verify

```bash
./verify.sh
./test-install.sh
./languages/go/verify.sh # after installing Go support
```

`verify.sh` demonstrates why each generic tool is included. `test-install.sh`
checks installation and repeated updates in an isolated home directory; it
does not modify your real agent configuration.

## Scope

- macOS with Homebrew is the only supported platform.
- The root installer contains only language-independent tools.
- Language integrations live under `languages/<name>/`.
- Homebrew installs current formula versions; the Brewfiles are not lockfiles.

New tools should prevent a reproducible failure or provide a measurable
improvement, with a local verification case.

## License

[MIT](LICENSE)
