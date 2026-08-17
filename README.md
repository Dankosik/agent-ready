# agent-ready

You just opened a fresh machine and you want to code with AI agents on it. This is what to install, and why.

```bash
git clone https://github.com/Dankosik/agent-ready && cd agent-ready && brew bundle
```

Nine tools. Each one either prevents a class of result that is **wrong and quiet**, or measurably changes how well an agent works. Convenience tools were cut, and [what was rejected](#considered-and-rejected) is listed with reasons.

Expand any entry below for the reasoning and a command you can run to check it yourself.

## What gets installed

<details>
<summary><b>rtk</b> — cuts verbose command output before it reaches the model</summary>

An agent's useful lifetime is bounded by how fast it fills its context. A single `git status`, `ls -R` or test run can spend thousands of tokens on output the model does not need in full.

[rtk](https://github.com/rtk-ai/rtk) sits in front of common commands and filters their output. It hooks into Claude Code, Codex, Cursor, Copilot and others, so it applies without changing how you or the agent write commands.

```bash
rtk gain                      # what it has actually saved you so far
rtk hook check "git status"   # dry-run: see how a command gets rewritten
```

Upstream claims 60–90% reduction on common dev commands; `rtk gain` is how you check that against your own history rather than taking the number on faith.

This is the one entry about capacity rather than correctness, and it earns the line: everything else here only matters while the agent still has room to think.

</details>

<details>
<summary><b>ast-grep</b> — regex silently misses code split across lines</summary>

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

</details>

<details>
<summary><b>sd</b> — <code>sed -i</code> silently does nothing on macOS</summary>

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

</details>

<details>
<summary><b>shellcheck</b> — shell has no compiler, so mistakes surface in CI</summary>

An unquoted variable, a `[[ ]]` that silently returns true under an older bash, a subshell that swallows an exit code — all run fine until the one input that breaks them, usually in CI, usually on someone else's branch.

```bash
shellcheck yourscript.sh
```

This is the same tool the pinned `koalaman/shellcheck` CI images run. Having it locally moves the check inside the edit loop instead of at the gate.

</details>

<details>
<summary><b>difftastic</b> — tells reformatting apart from a real edit</summary>

Review of agent output is where you catch what tests do not. Line diffs make that harder: reordered imports, a reflowed argument list, a moved brace all render as changes.

```bash
git -c diff.external=difft diff
```

Compares syntax trees, so formatting churn collapses and the actual edit stands out. No global config needed — the `-c` form is per-invocation.

</details>

<details>
<summary><b>yq</b> — line edits drop YAML comments and anchors</summary>

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

</details>

<details>
<summary><b>jq</b> — regex over JSON breaks on nesting and escaping</summary>

Agents read JSON constantly: `gh` output, API responses, tool manifests. A regex that works on one response breaks on the next when a field nests, a string escapes a quote, or key order changes — and it breaks differently each time.

</details>

<details>
<summary><b>gh</b> — structured GitHub data instead of scraped HTML</summary>

Agents routinely need PR state, review comments, CI results, issue bodies. With `gh` that is one authenticated call returning structured data. Without it they fetch HTML or invent the answer.

</details>

<details>
<summary><b>hyperfine</b> — turns "it got faster" into a measurement</summary>

One `time` run is noise. hyperfine repeats, warms up, reports mean and deviation, and exports Markdown you can paste into a PR.

```bash
hyperfine --warmup 3 'make check'
```

</details>

## Not in the Brewfile, still worth doing

<details>
<summary><b>A language server for your language, wired as MCP</b> — the highest-leverage item here</summary>

For Go that is `gopls`, which since v0.20 speaks MCP directly:

```bash
claude mcp add gopls -- gopls mcp
```

Deliberately outside the Brewfile: it is per-language, and registering it as MCP matters more than installing it.

As an MCP server its tools appear in the agent's tool schema — the agent cannot fail to know it exists, which is not true of anything you write in an instruction file.

</details>

<details>
<summary><b>A sandbox</b> — most people run agents with full access and no prompt</summary>

[`@anthropic-ai/sandbox-runtime`](https://github.com/anthropic-experimental/sandbox-runtime) applies OS-level filesystem and network restrictions with a domain allowlist, no container required. Not a brew formula, so not in the Brewfile.

</details>

<details>
<summary><b>Spend visibility</b> — you cannot see what a session costs</summary>

[`ccusage`](https://github.com/ccusage/ccusage) reads local session logs. No account, no API key, no network:

```bash
npx ccusage@latest
```

</details>

## Considered and rejected

<details>
<summary>Eight tools that did not make the list, and why</summary>

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

</details>

## Scope and maintenance

<details>
<summary>Platform, neutrality, and what this snapshot promises</summary>

**macOS with Homebrew, for now.** Nothing here is conceptually macOS-only — the tools are cross-platform and the reasoning holds anywhere. Homebrew is simply the shortest path to a working machine today, and shipping one platform that actually works beats three that half-work. Linux and Windows packaging are the obvious next step.

**Language-agnostic on purpose.** Anything tied to one language belongs to your project, not to a machine-setup file. The one exception is the language-server note above, and that is a pointer rather than a package.

**Vendor-neutral on purpose.** Nothing here is written by this project. If an entry stops being the best answer, it gets replaced or removed, not defended.

A Brewfile is not a lockfile — Homebrew formulae roll forward, so this installs current versions rather than the ones recorded here.

**Snapshot: 2026-08-17.** Verified against rtk 0.45.0, ast-grep 0.45.1, sd 1.1.0, shellcheck 0.11.0, difftastic 0.70.0, yq 4.53.3, hyperfine 1.20.0.

Treat this as a dated snapshot with its reasoning attached, not a maintained index. PRs adding a tool are welcome when they carry a runnable proof of what it prevents or measurably improves. PRs that only assert a tool is good will be closed with a link to this line — that rule is what keeps the list short enough to be worth reading.

</details>

## License

MIT
