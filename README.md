<h1 align="center">agent-ready</h1>

<p align="center"><strong>Reliable command-line tools for AI coding agents on macOS and Linux.</strong></p>

<p align="center">
  <img alt="license MIT" src="https://img.shields.io/badge/license-MIT-blue">
  <img alt="platform macOS and Linux" src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey">
  <a href="https://github.com/Dankosik/agent-ready/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/Dankosik/agent-ready/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="17 generic tools" src="https://img.shields.io/badge/generic_tools-17-brightgreen">
</p>

<p align="center">
  <img alt="agent-ready — Better tools. Better agents." src="assets/agent-ready-hero.jpg">
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

Requires at least one supported coding agent, and:

- macOS: [Homebrew](https://brew.sh/)
- Linux or [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install):
  `curl`, `xz`, and `unzip`. No Homebrew and no root needed; see
  [Linux without Homebrew](#linux-without-homebrew).

On Debian or Ubuntu:

```bash
sudo apt-get install -y curl ca-certificates xz-utils unzip
```

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/v1.4.0/bootstrap.sh | AGENT_READY_REF=v1.4.0 bash
```

That's it. The installer adds 17 language-independent tools and configures
Claude Code, Codex, Cursor, Gemini CLI, GitHub Copilot CLI, and Windsurf when it
finds them. Start a new agent session after the command finishes.

On macOS it also installs GNU coreutils, because agents call `timeout` by reflex
and macOS has none. If no `timeout` is on your `PATH`, the installer links
`~/.local/bin/timeout` to `gtimeout`; it never replaces a file already there.

The command is pinned to the immutable `v1.4.0` release. Upgrade by choosing a
newer release version in both places in the command.

> [!NOTE]
> `agent-ready` configures coding agents but does not install them or sign in to
> their services.

On Windows, run the installer inside WSL2. It configures agents installed in the
same WSL environment; native Windows is not supported.

For best performance, keep repositories used by Linux agents in the WSL
filesystem, such as `~/projects`, rather than under `/mnt/c`.

### Linux without Homebrew

On Linux, the tools come from each project's latest GitHub release, not from a
package manager:

- every download is checked against the SHA-256 digest GitHub records for that
  release asset before it is unpacked; a mismatch installs nothing;
- binaries go to `~/.local/bin` (override with `AGENT_READY_BIN_DIR`), so no
  `sudo` is needed, and it also works as root in a container;
- static builds are used where upstream publishes them; `mdq` publishes no
  arm64 Linux build and is skipped there;
- if the latest release lacks the Linux build (for example, its upstream build
  failed), the newest stable release among the last 30 that has it is used, and
  the installer says which one.

If Homebrew is already installed, it is used as before. Pass `--binaries` to use
release binaries anyway. Add `~/.local/bin` to `PATH` if the installer says it
is missing. Go support builds `gopls` with your Go toolchain
(`go install golang.org/x/tools/gopls@latest`) into the same directory.

The installer makes one GitHub API request per tool it installs. If you hit the
anonymous rate limit, set `GITHUB_TOKEN` and run it again.

## Install for one agent

Use one of these commands if you want to configure a specific agent instead of
automatic detection.

<details>
<summary><strong>Codex</strong></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/v1.4.0/bootstrap.sh | AGENT_READY_REF=v1.4.0 bash -s -- codex
```

Routing is added to `~/.codex/AGENTS.md`.

</details>

<details>
<summary><strong>Claude Code</strong></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/v1.4.0/bootstrap.sh | AGENT_READY_REF=v1.4.0 bash -s -- claude
```

Routing is added to `~/.claude/CLAUDE.md`.

</details>

<details>
<summary><strong>Cursor</strong></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/v1.4.0/bootstrap.sh | AGENT_READY_REF=v1.4.0 bash -s -- cursor
```

Routing is added through the global hook in `~/.cursor/hooks.json`.

</details>

<details>
<summary><strong>Gemini CLI</strong></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/v1.4.0/bootstrap.sh | AGENT_READY_REF=v1.4.0 bash -s -- gemini
```

Routing is added to `~/.gemini/GEMINI.md`.

</details>

<details>
<summary><strong>GitHub Copilot CLI</strong></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/v1.4.0/bootstrap.sh | AGENT_READY_REF=v1.4.0 bash -s -- copilot
```

Routing is added to `~/.copilot/copilot-instructions.md`.

</details>

<details>
<summary><strong>Windsurf</strong></summary>

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/v1.4.0/bootstrap.sh | AGENT_READY_REF=v1.4.0 bash -s -- windsurf
```

Routing is added to `~/.codeium/windsurf/memories/global_rules.md`.

</details>

### Additional agents

Replace `opencode` with the selector you need:

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/v1.4.0/bootstrap.sh | AGENT_READY_REF=v1.4.0 bash -s -- opencode
```

| Agent | Selector | Global instructions |
|---|---|---|
| Grok Build | `grok` | `~/.grok/rules/agent-ready.md` |
| OpenCode | `opencode` | `~/.config/opencode/AGENTS.md` |
| Qwen Code | `qwen` | `~/.qwen/QWEN.md` |
| Cline CLI | `cline` | `~/.cline/data/settings/rules/agent-ready.md` |
| Kilo Code | `kilo` | `~/.config/kilo/AGENTS.md` |
| Crush | `crush` | `~/.config/crush/CRUSH.md` |
| goose | `goose` | `~/.config/goose/AGENTS.md` |

OpenCode plugins use OpenCode's instructions. Kilo Code is configured
separately because its OpenCode-based CLI uses its own config directory.

## Go support

Run this after the quick start command if you work with Go:

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/v1.4.0/bootstrap.sh | AGENT_READY_REF=v1.4.0 bash -s -- language go
```

It installs `gopls`, connects `gopls mcp` to detected Codex, Claude Code, and
Cursor installations, and adds the Go routing instructions.

<details>
<summary>Configure Go for one agent</summary>

```bash
# Codex
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/v1.4.0/bootstrap.sh | AGENT_READY_REF=v1.4.0 bash -s -- language go --agent codex

# Claude Code
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/v1.4.0/bootstrap.sh | AGENT_READY_REF=v1.4.0 bash -s -- language go --agent claude

# Cursor
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/v1.4.0/bootstrap.sh | AGENT_READY_REF=v1.4.0 bash -s -- language go --agent cursor
```

</details>

## What's installed

| Job | Tools |
|---|---|
| Code intelligence | [`codegraph`](https://github.com/colbymchenry/codegraph) |
| Compact output | [`rtk`](https://github.com/rtk-ai/rtk) |
| Search and edit | [`ripgrep`](https://github.com/BurntSushi/ripgrep), [`ast-grep`](https://ast-grep.github.io/), [`sd`](https://github.com/chmln/sd) |
| Python and data | [`uv`](https://docs.astral.sh/uv/), [`jq`](https://jqlang.org/), [`yq`](https://mikefarah.gitbook.io/yq/), [`mdq`](https://github.com/yshavit/mdq) |
| Git and GitHub | [`gh`](https://cli.github.com/), [`worktrunk`](https://worktrunk.dev/), [`difftastic`](https://difftastic.wilfred.me.uk/) |
| Local checks | [`gitleaks`](https://github.com/gitleaks/gitleaks), [`osv-scanner`](https://google.github.io/osv-scanner/), [`actionlint`](https://github.com/rhysd/actionlint), [`shellcheck`](https://www.shellcheck.net/), [`hyperfine`](https://github.com/sharkdp/hyperfine) |
| Command time limits (macOS) | [`coreutils`](https://www.gnu.org/software/coreutils/) (`timeout`) |

The generic installer and language installers are separate. Adding Go support
does not change the base tool list.

## Code intelligence

`codegraph` builds a local knowledge graph of a repository and answers
structural questions from it — the source of the symbols involved, the call
paths between them, and what a change would touch — instead of making the agent
grep and read files one at a time.

Upstream publishes no Homebrew formula, so it is installed from its release
archive on macOS and Linux alike — about 60 MB to download and 280 MB unpacked
on the first run; later runs reuse the recorded release. Because that archive is
a self-contained bundle:

- the SHA-256 digest GitHub records for the asset is checked before unpacking;
- versions live under `~/.local/share/agent-ready/codegraph/versions/`, and
  only the launcher is linked into `~/.local/bin` (or `AGENT_READY_BIN_DIR`);
- `--upgrade` updates that copy and prunes older versions; a `codegraph`
  installed with npm or upstream's script is not replaced (MCP wiring and
  telemetry still apply);
- the installer turns anonymous usage telemetry off after wiring. Re-enable it
  with `codegraph telemetry on`.

The graph is per project. Agent Ready installs the CLI; it does not index your
repositories. Run this once in each project you want covered:

```bash
cd your-project
codegraph init
```

That creates a local `.codegraph/` index; a running MCP server keeps it current
as you edit. Without an MCP connection — for example an agent CodeGraph does not
support — run `codegraph sync` after edits to refresh its symbol list; `explore`
still reads the source from disk. Add `.codegraph/` to `.gitignore` rather than
committing it. The shared routing instructions use the index only when that
directory exists. Without one, the agent keeps using `rg`, `ast-grep`, and
`Read`, and does not run `codegraph init` on its own.

The shared entry is deliberately one line: the tool, what it indexes, its two
entry points, when to trust its output, and the no-index rule. The full command
list stays in `codegraph --help`, where it costs nothing until it is needed.

MCP wiring is delegated to CodeGraph's own installer, which knows each agent's
config shape. Automatic installation passes `--target=auto`, so CodeGraph wires
every agent it detects; an explicit `--agent` passes that agent's target. The
command is `codegraph install --yes --target=… --location=global
--no-permissions`, which merges the MCP server entry, may add CodeGraph's own
marker-fenced section to the agent's instruction file, and (for Claude Code)
adds its prompt hook in `settings.json`. CodeGraph writes that section for
Claude Code, Codex, Gemini CLI, and OpenCode, so when `codegraph` is installed
their agent-ready block leaves out its own CodeGraph line rather than repeat the
same rule in every prompt. Other agents keep the line and get the CLI routing.

## Safe to run again

The installers preserve existing configuration and update only the block
between the `agent-ready:start` and `agent-ready:end` markers. Cursor hooks and
MCP configuration are merged instead of replaced.

Each managed block starts with a `<!-- agent-ready vX.Y.Z sha256:… -->` line
that records the release which wrote it and fingerprints the block. If you edit
inside the markers, the next run stops before changing any file and names it;
move the edit outside the markers, or rerun with `--force` to replace the
block. `--dry-run` performs the same detection and checks and reports
`would add`, `would refresh`, `unchanged`, or `blocked` for every target
without installing tools, invoking `rtk` or `codegraph`, or modifying any file.
The installer also records the agents, languages, tool method, and version it
configured in `~/.config/agent-ready/receipt` (or under `$XDG_CONFIG_HOME`).

Release archives are checked against the SHA-256 digest GitHub records for the
`agent-ready-vX.Y.Z.tar.gz` asset before anything inside them runs, and a release
that publishes no such asset is refused. When `gh` is installed and signed in,
the build provenance of the archive is verified too.

Run the same command again whenever you want to refresh the managed
configuration. Installed tools are not upgraded unless you pass `--upgrade`;
with release binaries, `--upgrade` downloads only the tools that have a newer
release, and CodeGraph is upgraded only when Agent Ready installed it. Use
`--configure-only` to skip tool installation entirely:

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/v1.4.0/bootstrap.sh | AGENT_READY_REF=v1.4.0 bash -s -- codex --configure-only
```

To explicitly upgrade the generic tools:

```bash
curl -fsSL https://raw.githubusercontent.com/Dankosik/agent-ready/v1.4.0/bootstrap.sh | AGENT_READY_REF=v1.4.0 bash -s -- --upgrade
```

## Update

`agent-ready update` moves the installed command and the configuration it
manages to the newest release, repeating the install recorded in the receipt:

```bash
agent-ready update           # newest release that is at least 24 hours old
agent-ready update --check   # only report; exits 10 when an update is available
agent-ready update vX.Y.Z    # an explicit release, including a downgrade
```

It repeats the receipt's agents, languages, and tool mode, so an agent you did
not select is never configured and a configure-only install stays
configure-only. Tools are not upgraded unless you pass `--upgrade-tools`.
`--dry-run` runs the new release's installer in dry-run mode and writes
nothing, and `--force` is passed through for a block whose local edits would
otherwise stop the update.

A release is only offered once its archive has been published for 24 hours, so
a broken release can be withdrawn before anyone updates to it; set
`AGENT_READY_MIN_RELEASE_AGE` to a number of hours to change that, or to `0` to
take the newest release immediately. The archive is verified against the
SHA-256 digest GitHub records before anything inside it runs. An install from
v1.3.0 or earlier has no receipt; `update` then assumes automatic agent
detection and reads the tool mode from the machine, and says so.

After the update, start a new agent session to load the updated instructions.
`agent-ready rollback` returns to the previous release when the update is not
what you wanted.

## Uninstall

`agent-ready uninstall` removes the configuration agent-ready wrote and nothing
else:

```bash
agent-ready uninstall           # remove managed configuration and state
agent-ready uninstall --dry-run # report the plan and change nothing
agent-ready uninstall --force   # remove a block that has local edits
```

It targets every agent in the receipt's `configured` list or, without a receipt,
every instruction file that still carries agent-ready markers. For each one it
removes only the block between `agent-ready:start` and `agent-ready:end`; Cursor
loses only its entry in `~/.cursor/hooks.json` and
`~/.cursor/hooks/agent-ready-session-start.json`. It then removes the receipt,
`~/.config/agent-ready/languages/`, the launcher only when it is agent-ready's
own symlink, and `~/.local/share/agent-ready/versions/`. A file agent-ready
created is left in place (empty) rather than deleted, and a block with local
edits stops the run and is named unless you pass `--force`.

Installed tools are not removed. The command lists what is still installed and
prints the exact removal commands, including `rtk init -g --uninstall` for the
RTK integration and `codegraph uninstall` for the CodeGraph MCP wiring; those
belong to those tools. The `binaries` and `codegraph` state files stay while the
tools they describe are installed. From a checkout, `./install.sh --uninstall`
does the same.

## The `agent-ready` command

Installing from a release also leaves a local `agent-ready` command, laid out
like the CodeGraph bundle: every version keeps its own tree, and only a launcher
is on `PATH`.

```text
${XDG_DATA_HOME:-$HOME/.local/share}/agent-ready/versions/vX.Y.Z/
${AGENT_READY_BIN_DIR:-$HOME/.local/bin}/agent-ready -> .../versions/vX.Y.Z/agent-ready
```

An install keeps the version it installed and the one before it and removes
older trees. A launcher you already have is kept unless this installer created
it. The command takes the same arguments as the bootstrap, without downloading
anything:

```bash
agent-ready                        # install with automatic detection
agent-ready codex                  # configure one agent
agent-ready --agent claude,codex   # configure a comma list
agent-ready language go            # add Go support
agent-ready status                 # tree, launcher, receipt, and drift
agent-ready doctor                 # ok/problem for the install and every tool
agent-ready rollback               # reinstall the newest kept older release
agent-ready uninstall              # remove only what agent-ready wrote
```

`status` prints the installed version, the launcher target, the receipt fields,
the kept versions, and what this tree's installer would change. The drift check
repeats the receipt's agents as one `--agent` list and the receipt's tool mode,
so a machine installed with `--configure-only` is compared with `--configure-only`.
`doctor` reports each check as `ok` or `problem` and exits non-zero when
anything fails; `mdq` is only warned about because upstream publishes no arm64
Linux build. Neither `status` nor `doctor` writes anything or uses the network.

`rollback` is offline too. It finds the newest kept version below the receipt's
and reruns that tree's installer with the receipt's agents, so the managed
blocks and the receipt go back to that release; because an install keeps only
two versions, it can go back one release.

The local command appears after an install from a release. A checkout, a
development ref, or an `AGENT_READY_ARCHIVE_URL` archive runs the requested
install but does not install the command.

## Verify

Quick check:

```bash
rtk --version
rg --version
ast-grep --version
codegraph version
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

This applies to macOS. Install Homebrew from [brew.sh](https://brew.sh/), open a
new terminal, and check that `brew --version` works.

</details>

<details>
<summary><code>missing: xz unzip</code></summary>

Install the packages the error names with your distribution's package manager;
the error prints the command for Debian/Ubuntu, Fedora/RHEL, and Alpine. Nothing
was downloaded yet.

</details>

<details>
<summary><code>GitHub API rate limit reached</code></summary>

Anonymous GitHub API requests are limited per IP address, which shared CI
runners and offices hit quickly. Set `GITHUB_TOKEN` (any token works; no scopes
are needed) and run the installer again. Already installed tools are skipped.

</details>

<details>
<summary><code>checksum mismatch</code></summary>

The downloaded file does not match the digest GitHub records for the release
asset, so it was not installed. Run the installer again; if it persists, report
it to the tool's project.

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

<details>
<summary><code>codegraph: command not found after installation</code></summary>

The launcher is linked into `~/.local/bin` (or `AGENT_READY_BIN_DIR`). Add that
directory to `PATH` in your shell profile and open a new terminal. The MCP
configuration uses the `codegraph` name, so the server cannot start until the
command resolves.

</details>

<details>
<summary><code>CodeGraph isn't available here</code></summary>

The project has no `.codegraph/` index. Run `codegraph init` in the repository
root once; a running MCP server picks the new index up without a restart. The
installer does not index repositories; the shared instructions deliberately
leave that decision to you.

On WSL with the repository on a Windows drive, CodeGraph keeps its index in
`.codegraph-wsl/` instead; the command still works there.

</details>

## Project scope

- macOS with Homebrew; Linux with release binaries or Homebrew. CI covers macOS,
  Ubuntu on x86_64 and arm64, and a root-only Ubuntu container, and reruns daily
  against the latest tool releases
- Windows through WSL2; CI smoke-tests Ubuntu on WSL2, while native Windows is
  unsupported
- language-independent tools in the root installer, including CodeGraph, which
  comes from its release bundle because upstream publishes no formula
- language integrations under `languages/<name>/`
- runnable verification for every included tool

## License

[MIT](LICENSE)
