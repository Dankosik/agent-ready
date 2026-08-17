# agent-ready

You just opened a fresh machine and you want to code with AI agents on it. This is what to install, and why.

```bash
git clone https://github.com/Dankosik/agent-ready && cd agent-ready && brew bundle
```

## What this is, and what it is not

This is not a list of nice tools. Nine entries survived one filter:

> Does it prevent a class of result that is **wrong and quiet**, or does it measurably change how well an agent works — as opposed to saving a human keystrokes?

Convenience tools were cut. So were tools that duplicate something an agent already has. What was rejected, and why, is at the bottom — it is the part most such lists omit, and it is the reason this one is short enough to read before you run it.

Almost every claim below comes with a command you can run in under a minute. If a proof does not reproduce on your machine, that entry does not deserve your disk space.

You are also welcome to read the Brewfile first. It is thirty lines. That is the point.

## Why each tool

### rtk — token budget is the real constraint

An agent's useful lifetime is bounded by how fast it fills its context. A single `git status`, `ls -R` or test run can spend thousands of tokens on output the model does not need in full.

[rtk](https://github.com/rtk-ai/rtk) sits in front of common commands and filters their output before it reaches the model. It hooks into Claude Code, Codex, Cursor, Copilot and others, so it applies without changing how you or the agent write commands.

```bash
rtk gain          # what it has actually saved you so far
rtk hook check "git status"   # dry-run: see how a command gets rewritten
```

Upstream claims 60–90% reduction on common dev commands; `rtk gain` is how you check that on your own history rather than taking the number on faith. This is the one entry here that is about capacity rather than correctness, and it earns the line: everything else on this list only matters while the agent still has room to think.

### ast-grep — regex reads text; code has structure

An agent asked to find every `foo(1, 2)` writes a regex. Here is a six-line file:

```js
// legacy: foo(1, 2) was removed
const a = foo(1, 2);
const b = foo(
  1,
  2
);
```

```bash
rg -F -n 'foo(1, 2)' example.js
ast-grep --lang js --pattern 'foo(1, 2)' example.js
```

`rg` returns lines 1 and 2. `ast-grep` returns line 2 and lines 3–6.

Both return two results, and neither set is correct for the other's reason: `rg` **matches the comment** (a false positive) and **misses the call split across lines** (a false negative). A formatter put that line break there; the agent never sees it happen.

The failure mode is the dangerous one. A regex that returns nothing does not error — it reports "no occurrences", and the agent proceeds as if there were none.

### sd — `sed -i` does not work on macOS

Every agent knows the GNU form. On macOS it does this:

```bash
echo hello > /tmp/demo && sed -i 's/hello/world/' /tmp/demo && cat /tmp/demo
```

The file still contains `hello`.

BSD `sed` reads the argument after `-i` as a backup-file suffix, so `s/hello/world/` becomes the suffix and the *filename* becomes the script. What you see next depends on the path: `/tmp/demo` and `/tmp/x` produce two different errors on the same machine, because sed is parsing your path as sed source. Some forms leave a stray `.bak` beside the original instead.

The message varies; the invariant does not. **The edit does not happen**, and nothing about the command's shape suggests that in advance.

```bash
echo hello > /tmp/t && sd hello world /tmp/t && cat /tmp/t   # world
```

No `-i`, no suffix ambiguity, no BRE/ERE guessing, and `-F` for literal strings when the pattern is full of metacharacters.

### shellcheck — agent-written shell fails late

Shell has no compiler. An unquoted variable, a `[[ ]]` that silently returns true under an older bash, a subshell that swallows an exit code — all run fine until the one input that breaks them, usually in CI, usually on someone else's branch.

```bash
shellcheck yourscript.sh
```

This is the same tool the pinned `koalaman/shellcheck` CI images run. Having it locally moves the check inside the edit loop instead of at the gate.

### difftastic — reformatting is not a change

Review of agent output is where you catch what tests do not. Line diffs make that harder: reordered imports, a reflowed argument list, a moved brace all render as changes.

```bash
git -c diff.external=difft diff
```

Compares syntax trees, so formatting churn collapses and the actual edit stands out. No global config needed — the `-c` form is per-invocation.

### yq — line edits corrupt YAML quietly

Config files carry comments and anchors. Line-based edits drop them, or produce a file that is still valid YAML and no longer means the same thing.

```yaml
# important comment
name: old   # trailing
list:
  - a
```

```bash
yq -i '.name = "new"' t.yml
```

Both comments survive. Reach for this for reads too: `yq '.jobs.build.steps[0].uses' workflow.yml` beats a regex that happens to work on today's indentation.

### jq — JSON is not lines

Agents read JSON constantly: `gh` output, API responses, tool manifests. Regex over JSON breaks on nesting, escaping and key order, and it breaks differently each time.

### gh — the alternative is scraping or guessing

Agents routinely need PR state, review comments, CI results, issue bodies. With `gh` that is one authenticated call returning structured data. Without it they fetch HTML or invent the answer.

### hyperfine — "faster" is a claim until measured

One `time` run is noise. hyperfine repeats, warms up, reports mean and deviation, and exports Markdown you can paste into a PR.

```bash
hyperfine --warmup 3 'make check'
```

## Not in the Brewfile, still worth doing

**A language server for your language, wired as MCP.** For Go that is `gopls`, which since v0.20 speaks MCP directly:

```bash
claude mcp add gopls -- gopls mcp
```

This is the highest-leverage item here and it is deliberately outside the Brewfile: it is per-language, and registering it as MCP matters more than installing it. As an MCP server its tools appear in the agent's tool schema — the agent cannot fail to know it exists, which is not true of anything you write in an instruction file.

**A sandbox.** Many people run agents with full filesystem and network access and no approval prompt. [`@anthropic-ai/sandbox-runtime`](https://github.com/anthropic-experimental/sandbox-runtime) applies OS-level restrictions with a domain allowlist, no container required. Not a brew formula, so not in the Brewfile.

**Spend visibility.** [`ccusage`](https://github.com/ccusage/ccusage) reads local session logs — no account, no API key, no network:

```bash
npx ccusage@latest
```

## Considered and rejected

| Tool | Why not |
|---|---|
| `comby` | Deprecated upstream (no OCaml 5 support); `ast-grep` covers it |
| `watchexec` | Useful to the human watching; an agent runs commands explicitly and never sees a background watcher's output |
| `scc`, `tokei` | Repository size and language stats answer a question agents rarely need to ask |
| `delta` | Prettier diffs for humans; adds nothing an agent can act on |
| `files-to-prompt` | Last release February 2025; superseded by agents that read files directly |
| `claude-code-otel` | Unmaintained since June 2025, and Claude Code exports OTLP natively — that is configuration, not a dependency |
| `packnplay` | No license file; cannot be used legally |
| `semgrep` | Overlaps whatever linter your project already gates on; a second linter is a second source of truth |

## Scope

**macOS with Homebrew, for now.** Nothing here is conceptually macOS-only — the tools are cross-platform and the reasoning holds anywhere. Homebrew is simply the shortest path to a working machine today, and shipping one platform that actually works beats three that half-work. Linux and Windows packaging are the obvious next step.

**Language-agnostic on purpose.** Anything tied to one language belongs to your project, not to a machine-setup file. The one exception is the language-server note above, and that is a pointer rather than a package.

**Vendor-neutral on purpose.** Nothing here is written by this project. If an entry stops being the best answer, it gets replaced or removed, not defended.

A Brewfile is not a lockfile — Homebrew formulae roll forward, so this installs current versions rather than the ones recorded below.

## Maintenance

**Snapshot: 2026-08-17.** Verified against rtk 0.45.0, ast-grep 0.45.1, sd 1.1.0, shellcheck 0.11.0, difftastic 0.70.0, yq 4.53.3, hyperfine 1.20.0.

Treat this as a dated snapshot with its reasoning attached, not a maintained index. PRs adding a tool are welcome when they carry a runnable proof of what it prevents or measurably improves. PRs that only assert a tool is good will be closed with a link to this line — that rule is what keeps the list short enough to be worth reading.

## License

MIT
