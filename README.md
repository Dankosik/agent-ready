<h1 align="center">agent-ready</h1>

<p align="center"><strong>Reliable command-line tools for AI coding agents on macOS and Linux.</strong></p>

<p align="center">
  <img alt="license MIT" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="platform macOS and Linux" src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey">
  <img alt="15 generic tools" src="https://img.shields.io/badge/generic_tools-15-brightgreen">
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="#install-for-one-agent">Agents</a> ·
  <a href="#go-support">Go</a> ·
  <a href="#whats-installed">Tools</a> ·
  <a href="#verify">Verify</a>
</p>

`agent-ready` installs a practical CLI toolkit and adds the instructions that
help coding agents use it correctly.

## Quick start

Requires macOS, Linux, or WSL2; [Homebrew](https://brew.sh/); and at least one
supported coding agent.

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash
```

That's it. The installer adds 15 language-independent tools and configures
Claude Code, Codex, Cursor, Gemini CLI, GitHub Copilot CLI, and Windsurf when it
finds them. Start a new agent session after the command finishes.

> [!NOTE]
> `agent-ready` configures coding agents but does not install them or sign in to
> their services.

On Windows, run the installer inside WSL2. It configures agents installed in the
same WSL environment; native Windows is not supported.

## Install for one agent

Use one of these commands if you want to configure a specific agent instead of
automatic detection.

<details>
<summary><strong>Codex</strong></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- codex
```

Routing is added to `~/.codex/AGENTS.md`.

</details>

<details>
<summary><strong>Claude Code</strong></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- claude
```

Routing is added to `~/.claude/CLAUDE.md`.

</details>

<details>
<summary><strong>Cursor</strong></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- cursor
```

Routing is added through the global hook in `~/.cursor/hooks.json`.

</details>

<details>
<summary><strong>Gemini CLI</strong></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- gemini
```

Routing is added to `~/.gemini/GEMINI.md`.

</details>

<details>
<summary><strong>GitHub Copilot CLI</strong></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- copilot
```

Routing is added to `~/.copilot/copilot-instructions.md`.

</details>

<details>
<summary><strong>Windsurf</strong></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- windsurf
```

Routing is added to `~/.codeium/windsurf/memories/global_rules.md`.

</details>

## Go support

Run this after the quick start command if you work with Go:

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- language go
```

It installs `gopls`, connects `gopls mcp` to detected Codex, Claude Code, and
Cursor installations, and adds the Go routing instructions.

<details>
<summary>Configure Go for one agent</summary>

```bash
# Codex
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- language go --agent codex

# Claude Code
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- language go --agent claude

# Cursor
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- language go --agent cursor
```

</details>

## What's installed

| Job | Tools |
|---|---|
| Compact output | [`rtk`](https://github.com/rtk-ai/rtk) |
| Search and edit | [`ripgrep`](https://github.com/BurntSushi/ripgrep), [`ast-grep`](https://ast-grep.github.io/), [`sd`](https://github.com/chmln/sd) |
| Python and data | [`uv`](https://docs.astral.sh/uv/), [`jq`](https://jqlang.org/), [`yq`](https://mikefarah.gitbook.io/yq/), [`mdq`](https://github.com/yshavit/mdq) |
| Git and GitHub | [`gh`](https://cli.github.com/), [`worktrunk`](https://worktrunk.dev/), [`difftastic`](https://difftastic.wilfred.me.uk/) |
| Local checks | [`gitleaks`](https://github.com/gitleaks/gitleaks), [`actionlint`](https://github.com/rhysd/actionlint), [`shellcheck`](https://www.shellcheck.net/), [`hyperfine`](https://github.com/sharkdp/hyperfine) |

The generic installer and language installers are separate. Adding Go support
does not change the base tool list.

## Safe to run again

The installers preserve existing configuration and update only the block
between the `agent-ready:start` and `agent-ready:end` markers. Cursor hooks and
MCP configuration are merged instead of replaced.

Run the same command again whenever you want to refresh the managed
configuration. Use `--configure-only` to skip Homebrew:

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- codex --configure-only
```

## Verify

Quick check:

```bash
rtk --version
rg --version
ast-grep --version
```

<details>
<summary>Run the full local verification</summary>

```bash
git clone https://github.com/Dankosik/agent-ready.git
cd agent-ready

./verify.sh
./test-install.sh
./languages/go/verify.sh # after installing Go support
```

`verify.sh` and `test-install.sh` use temporary fixtures and do not edit your
real agent configuration.

</details>

## Troubleshooting

<details>
<summary><code>Homebrew is required</code></summary>

Install Homebrew from [brew.sh](https://brew.sh/), open a new terminal, and
check that `brew --version` works. On Linux or WSL2, also follow Homebrew's
printed `brew shellenv` instructions before retrying.

</details>

<details>
<summary><code>No supported harness found</code></summary>

Install your coding agent or choose it explicitly from the agent list above.

</details>

<details>
<summary><code>malformed agent-ready markers</code></summary>

Open the file printed in the error. It must contain either no agent-ready
markers or one start marker followed by one end marker. Fix duplicate or
unmatched markers and run the installer again.

</details>

<details>
<summary><code>Cursor MCP config is not valid JSON</code></summary>

Fix the JSON in `~/.cursor/mcp.json`, then run the Go installer again. The
installer leaves an invalid file unchanged.

</details>

## Project scope

- macOS, Linux, and WSL2 with Homebrew
- native Windows is not supported
- language-independent tools in the root installer
- language integrations under `languages/<name>/`
- runnable verification for every included tool

## License

[MIT](LICENSE)
