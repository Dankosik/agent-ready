<h1 align="center">agent-ready</h1>

<p align="center"><strong>Reliable command-line setup for AI coding agents on macOS.</strong></p>

<p align="center">
  <img alt="license MIT" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="platform macOS" src="https://img.shields.io/badge/platform-macOS-lightgrey">
  <img alt="15 generic tools" src="https://img.shields.io/badge/generic_tools-15-brightgreen">
</p>

<p align="center">
  <a href="#install-for-your-agent">Install</a> ·
  <a href="#add-go-support">Go</a> ·
  <a href="#what-the-installer-changes">What changes</a> ·
  <a href="#check-the-installation">Check</a> ·
  <a href="#troubleshooting">Troubleshooting</a>
</p>

`agent-ready` installs a small set of command-line tools and tells your coding
agent when to use them. This avoids common macOS problems such as GNU-style
`sed` commands that do not work, recursive searches through `.git`, regex used
to inspect parsed code, and large command output filling the agent's context.

Most people need one command. Pick the agent you use and copy its command from
the next section. If you work with Go, run one additional command afterward.

> [!IMPORTANT]
> `agent-ready` does not install Codex, Claude Code, Cursor, or another coding
> agent. Install and sign in to your agent first. This project installs the
> supporting CLI tools and configures the agent to use them.

## Before you start

You need:

- macOS
- [Homebrew](https://brew.sh/) available as the `brew` command
- at least one supported coding agent

Check Homebrew before running the installer:

```bash
brew --version
```

If the command is not found, install Homebrew from [brew.sh](https://brew.sh/),
then open a new terminal and run `brew --version` again.

## Install for your agent

Choose one command. The installer configures only the agent named at the end.

### Codex

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- codex
```

### Claude Code

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- claude
```

### Cursor

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- cursor
```

### Gemini CLI

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- gemini
```

### GitHub Copilot CLI

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- copilot
```

### Windsurf

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- windsurf
```

### Configure every agent found on the machine

Use this form if you regularly switch between several supported agents:

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash
```

Without an agent name, the installer keeps the original behavior: it detects
supported agents and configures each one it finds.

In each command, `curl` downloads `bootstrap.sh` from this repository. Bash
runs that script and receives the agent name after `--`. The bootstrap then
downloads the rest of the repository and calls the appropriate installer.

When the command finishes, start a new agent session. You do not need to paste
the routing rules into prompts. The agent loads them from its normal global
configuration.

## Add Go support

The base installer contains only language-independent tools. Go support has a
separate installer because not every user needs `gopls` or its MCP connection.

Run the base installer first. Then choose one of the commands below.

### Go for Codex

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- language go --agent codex
```

### Go for Claude Code

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- language go --agent claude
```

### Go for Cursor

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- language go --agent cursor
```

### Go for every supported agent found on the machine

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- language go
```

The Go installer adds the official [`gopls`](https://go.dev/gopls/features/mcp)
language server and registers `gopls mcp` with Codex, Claude Code, or Cursor.
It also adds one short Go routing rule to the instructions managed by the base
installer. Existing `gopls` MCP entries are left unchanged.

The MCP interface is experimental. When an agent asks it to, `gopls` may run Go
commands, download modules into the Go cache, or query the vulnerability
database.

## What the installer changes

The bootstrap downloads the repository archive to a temporary directory, runs
the selected installer, and removes the download when it exits. The installer
uses Homebrew to install missing tools from the appropriate `Brewfile`. It then
configures the selected agent, or every detected agent if none was named.

For agents with file-based global instructions, the base installer writes a
managed routing block between these markers:

```text
<!-- agent-ready:start -->
...
<!-- agent-ready:end -->
```

Anything outside that block stays in place. Re-running the installer replaces
the existing block instead of adding another copy. A file with no markers is
fine: the installer appends a new block. If it finds only one marker, duplicate
markers, or markers in the wrong order, it stops rather than guessing how to
edit the file.

### Agent configuration locations

| Agent | Main agent-ready location |
|---|---|
| Codex | `~/.codex/AGENTS.md` |
| Claude Code | `~/.claude/CLAUDE.md` |
| Cursor | `~/.cursor/hooks.json` and `~/.cursor/hooks/agent-ready-session-start.json` |
| Gemini CLI | `~/.gemini/GEMINI.md` |
| GitHub Copilot CLI | `~/.copilot/copilot-instructions.md` |
| Windsurf | `~/.codeium/windsurf/memories/global_rules.md` |

Custom installations can set `CODEX_HOME`, `CLAUDE_CONFIG_DIR`, or
`COPILOT_HOME`. The installer uses those directories instead of the defaults
shown in the table.

The installer also asks `rtk` to set up its native integration for the selected
agent. Cursor receives routing context through a global `sessionStart` hook.
Existing Cursor hooks remain in the file.

The Go installer uses the native Codex and Claude MCP commands. For Cursor, it
merges the `gopls` server into `~/.cursor/mcp.json`. It refuses to edit a Cursor
MCP file that is not valid JSON.

## Run it again

The installers are safe to run more than once. A later run installs any missing
Homebrew formulae and refreshes the managed configuration without duplicating
it.

If the CLI tools are already installed, skip Homebrew and refresh only the
configuration:

```bash
# One agent
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- codex --configure-only

# Go for one agent
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/main/bootstrap.sh | bash -s -- language go --agent codex --configure-only
```

Homebrew installs current formula versions. The Brewfiles are not lockfiles,
and re-running `brew bundle` does not promise that every installed formula will
be upgraded.

## Inspect before running

If you do not want to pipe a downloaded script into Bash, clone the repository
and inspect it first:

```bash
git clone https://github.com/Dankosik/agent-ready.git
cd agent-ready

less bootstrap.sh
less install.sh
less agent-routing.md

./install.sh --agent codex
```

The equivalent local commands are:

```bash
./install.sh                         # every detected agent
./install.sh --agent codex           # only Codex
./install.sh --configure-only        # detected agents, no Homebrew

./languages/go/install.sh            # Go for detected agents
./languages/go/install.sh --agent codex
./languages/go/install.sh --configure-only
```

## Check the installation

For a quick check, confirm that the main commands are available:

```bash
rtk --version
rg --version
ast-grep --version
```

The repository also contains runnable comparisons for every generic tool and
an isolated installer test:

```bash
./verify.sh
./test-install.sh
```

Both scripts use temporary fixtures. They do not edit your real agent
configuration.

After installing Go support, verify `gopls` and its agent connections:

```bash
./languages/go/verify.sh
```

The Go verifier reads your current setup and reports how many supported agent
connections it found.

## Troubleshooting

### `Homebrew is required`

Run `brew --version`. If the command is missing, install Homebrew or fix your
shell `PATH`, then retry the same agent-ready command.

### `No supported harness found`

This message appears only in automatic detection mode. Name the agent
explicitly, for example:

```bash
./install.sh --agent codex --configure-only
```

### `rtk is not installed`

Run the installer without `--configure-only` first. That allows Homebrew to
install `rtk` before agent configuration begins.

### `malformed agent-ready markers`

Open the path printed in the error. It must contain either no agent-ready
markers or exactly one start marker followed by one end marker. Fix only the
duplicate or unmatched markers, keep the surrounding instructions, and run the
installer again.

### `Cursor MCP config is not valid JSON`

Open `~/.cursor/mcp.json` and correct the JSON before retrying the Go installer.
The installer leaves the invalid file unchanged.

### `gopls v0.20 or newer is required for MCP`

Upgrade `gopls`, then refresh the Go configuration:

```bash
brew upgrade gopls
./languages/go/install.sh --configure-only
```

### The agent still uses the old instructions

Finish the current agent session and start a new one. Codex, Claude Code, and
the other supported tools load global instructions when a session starts.

## What's included

| Job | Tools | Why they are here |
|---|---|---|
| Compact command output | [`rtk`](https://github.com/rtk-ai/rtk) | Reduces verbose shell output before the agent reads it |
| Search and replacement | [`ripgrep`](https://github.com/BurntSushi/ripgrep), [`ast-grep`](https://ast-grep.github.io/), [`sd`](https://github.com/chmln/sd) | Handles repository search, syntax-aware search, and macOS-safe replacement |
| Python and structured data | [`uv`](https://docs.astral.sh/uv/), [`jq`](https://jqlang.org/), [`yq`](https://mikefarah.gitbook.io/yq/), [`mdq`](https://github.com/yshavit/mdq) | Runs temporary Python dependencies and reads structured files without regex |
| Git and GitHub | [`gh`](https://cli.github.com/), [`worktrunk`](https://worktrunk.dev/), [`difftastic`](https://difftastic.wilfred.me.uk/) | Reads typed GitHub data, shows worktree state, and produces syntax-aware diffs |
| Local checks | [`gitleaks`](https://github.com/gitleaks/gitleaks), [`actionlint`](https://github.com/rhysd/actionlint), [`shellcheck`](https://www.shellcheck.net/), [`hyperfine`](https://github.com/sharkdp/hyperfine) | Finds secrets and workflow or shell errors, and measures command performance |

The exact generic instructions live in [`agent-routing.md`](agent-routing.md).
Go-specific instructions live in
[`languages/go/agent-routing.md`](languages/go/agent-routing.md).

## Remove the managed configuration

There is no automated uninstaller yet. The installed CLI tools are ordinary
Homebrew formulae and may be useful outside this project, so removing them
automatically would be unsafe.

To remove only the routing instructions, delete the block between the
`agent-ready:start` and `agent-ready:end` markers from the agent configuration
file listed above. For Cursor, also remove the `sessionStart` entry whose
command is `cat ./hooks/agent-ready-session-start.json`, then remove
`~/.cursor/hooks/agent-ready-session-start.json`.

This removes the routing owned by agent-ready. It does not remove RTK's native
agent integration.

Review your agent's MCP configuration separately before removing `gopls`. Do
not delete another MCP entry with the same name unless you know agent-ready
created it.

## Project scope

- macOS with Homebrew is the only supported platform.
- The root installer contains only language-independent tools.
- Language integrations live under `languages/<name>/` and keep their own
  installer, Brewfile, routing instructions, and verification.
- A new tool must prevent a reproducible failure or provide a measurable
  improvement with a local verification case.

## License

[MIT](LICENSE)
