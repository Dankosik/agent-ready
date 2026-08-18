<h1 align="center">agent-ready</h1>

<p align="center"><strong>Reliable command-line tooling for AI coding agents on macOS.</strong></p>

<p align="center">
  <img alt="license MIT" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="platform macOS" src="https://img.shields.io/badge/platform-macOS-lightgrey">
  <img alt="15 generic tools" src="https://img.shields.io/badge/generic_tools-15-brightgreen">
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#what-the-installer-changes">What it changes</a> ·
  <a href="#whats-included">Tools</a> ·
  <a href="#optional-go-support">Go support</a> ·
  <a href="#verification">Verification</a>
</p>

`agent-ready` installs a practical CLI toolkit and teaches your coding agents
when to use it. Agents can search, edit, validate, and inspect repositories
without common macOS command incompatibilities or unnecessarily verbose
output.

Most setup scripts stop after installing tools. Agents then keep reaching for
familiar commands such as GNU-style `sed`, noisy `grep`, or regex for parsed
code. `agent-ready` solves both halves: **the tools and the routing rules**.

## Quick start

> [!NOTE]
> Requires macOS and [Homebrew](https://brew.sh/).

```bash
git clone https://github.com/Dankosik/agent-ready.git
cd agent-ready
./install.sh
```

## What the installer changes

- **Installs** 15 language-independent CLI tools.
- **Detects** Claude Code, Codex, Cursor, Gemini CLI, GitHub Copilot CLI, and Windsurf.
- **Configures** each detected agent with concise tool-routing rules.

Existing configuration is preserved. Managed instructions are updated in
place when you run the installer again.

If the tools are already installed and you only want to refresh agent
configuration:

```bash
./install.sh --configure-only
```

## What's included

| Task | Tools |
|---|---|
| Compact command output | [`rtk`](https://github.com/rtk-ai/rtk) |
| Search and edit | [`ripgrep`](https://github.com/BurntSushi/ripgrep), [`ast-grep`](https://ast-grep.github.io/), [`sd`](https://github.com/chmln/sd) |
| Python and structured data | [`uv`](https://docs.astral.sh/uv/), [`jq`](https://jqlang.org/), [`yq`](https://mikefarah.gitbook.io/yq/), [`mdq`](https://github.com/yshavit/mdq) |
| Git and GitHub | [`gh`](https://cli.github.com/), [`worktrunk`](https://worktrunk.dev/), [`difftastic`](https://difftastic.wilfred.me.uk/) |
| Local checks | [`gitleaks`](https://github.com/gitleaks/gitleaks), [`actionlint`](https://github.com/rhysd/actionlint), [`shellcheck`](https://www.shellcheck.net/), [`hyperfine`](https://github.com/sharkdp/hyperfine) |

The exact instructions added to supported agents live in
[`agent-routing.md`](agent-routing.md).

## Optional Go support

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

## Verification

```bash
./verify.sh
./test-install.sh
./languages/go/verify.sh # after installing Go support
```

`verify.sh` demonstrates why each generic tool is included. `test-install.sh`
checks installation and repeated updates in an isolated home directory; it
does not modify your real agent configuration.

## Project scope

- macOS with Homebrew is the only supported platform.
- The root installer contains only language-independent tools.
- Language integrations live under `languages/<name>/`.
- Homebrew installs current formula versions; the Brewfiles are not lockfiles.

New tools should prevent a reproducible failure or provide a measurable
improvement, with a local verification case.

## License

[MIT](LICENSE)
