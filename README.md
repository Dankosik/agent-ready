# agent-ready

![license MIT](https://img.shields.io/badge/license-MIT-blue) ![platform macOS](https://img.shields.io/badge/platform-macOS-lightgrey) ![12 tools](https://img.shields.io/badge/tools-12-brightgreen)

**Set up macOS for coding with AI agents — Claude Code, Codex, Cursor — in one command.** Twelve CLI tools installed with Homebrew, each chosen for one reason, each with a proof you can run in under a minute.

```bash
git clone https://github.com/Dankosik/agent-ready && cd agent-ready && brew bundle
```

## Why this exists

An agent asked to rename something reaches for the form it knows:

```console
$ echo hello > /tmp/demo
$ sed -i 's/hello/world/' /tmp/demo    # the GNU form every agent writes
$ cat /tmp/demo
hello
```

The file is unchanged. On macOS, BSD `sed` reads the argument after `-i` as a backup-file suffix, so the substitution became the suffix and your filename became the script. It errors — with a message that depends on your path — and the edit never happens.

That is one entry out of twelve. Every tool here removes a way for an agent to be **confidently wrong**, or measurably changes how well it works. Convenience tools were cut, and [what was rejected](#considered-and-rejected) is listed with reasons.

## What gets installed

The twelve are not equally load-bearing, and a flat list would imply they are.

**Start here.** These four carry most of the value, and none of them depends on you remembering to reach for it at the right moment:

| Tool | Why it is here |
|---|---|
| **rtk** | Filters verbose command output before it reaches the model — automatically, on every command |
| **uv** | `pip install` fails outright on macOS system Python; every fallback the agent picks is worse |
| **sd** | `sed -i` does not edit files on macOS; the alternative is not worse, it is broken |
| **ast-grep** | Structural search; a regex that misses code split across lines reports "no matches" and raises nothing |

**The rest.** Each closes a real case, but a narrower or more situational one:

| Tool | Why it is here |
|---|---|
| **gh** | One typed field instead of half a megabyte of HTML |
| **jq** | Regex over JSON breaks on nesting and escaping |
| **gitleaks** | Agents copy live keys into fixtures and commit them; pushing is irreversible |
| **actionlint** | Workflow edits otherwise cost a push-and-wait round trip per typo |
| **shellcheck** | Shell has no compiler; mistakes surface in CI |
| **difftastic** | Separates reformatting from a real edit |
| **yq** | Line edits drop YAML comments and anchors |
| **hyperfine** | Turns "it got faster" into a measurement |

Expand any entry for the reasoning and a command that checks it.

## Verify it yourself

Do not take the table on faith — the repository ships the proof:

```bash
./verify.sh
```

It runs every tool against the alternative an agent would reach for without it and prints both results side by side. Nothing is installed, removed or configured; fixtures live in a temporary directory deleted on exit.

The `gh` check is included even though it does **not** show a correctness win — scraping returns the right number. A list you can only confirm is not a list worth trusting.

<details>
<summary><b>rtk</b> — token budget is what limits how long an agent stays useful</summary>

An agent's useful lifetime is bounded by how fast it fills its context. A single `git status`, `ls -R` or test run can spend thousands of tokens on output the model does not need in full.

[rtk](https://github.com/rtk-ai/rtk) sits in front of common commands and filters their output. It hooks into Claude Code, Codex, Cursor, Copilot and others, so it applies without changing how you or the agent write commands.

```bash
rtk gain                      # what it has actually saved you so far
rtk hook check "git status"   # dry-run: see how a command gets rewritten
```

Upstream claims 60–90% reduction on common dev commands.

**Treat `rtk gain` as indicative, not as proof.** It reports on the commands it proxied and cannot see the `| head -20` the agent appends afterwards, so its aggregate overstates the saving — one user reports it reading ~100% for exactly that reason. `./verify.sh` measures a single command's output both ways instead, which is the number you can actually stand behind.

Worth knowing before you adopt it: [an end-to-end evaluation of this whole tool category](https://www.peterbaumgartner.com/blog/e2e-evals-agents/) found context-saving tools tend to get *stacked on top of* normal file reads rather than replacing them, and reports rtk occasionally leaving an agent unable to confirm a task was complete. This is the one entry here about capacity rather than correctness, and it is the one to watch.

</details>

<details>
<summary><b>uv</b> — the agent's Python fallbacks are all bad ones</summary>

An agent needs a throwaway script with a third-party library — parse a large JSON dump, generate fixtures, poke an API to check a claim. It writes the command everyone writes:

```console
$ pip3 install humanize
error: externally-managed-environment
× This environment is externally managed
```

That is macOS refusing to let anything install into the system interpreter. The agent now picks one of three bad options: create a venv (state that outlives the session and that nobody cleans up), pass `--break-system-packages` (which does what it says), or give up and write something worse in bash.

```bash
uv run --with humanize report.py
```

Ephemeral environment, nothing installed globally, nothing left behind. `uvx <tool>` does the same for any Python CLI without installing it.

The adoption signal here is unusually strong: independent projects — Armin Ronacher's agent scripts and Trail of Bits' Python skill among them — ship PATH shims that intercept `pip`, `poetry` and `python` and redirect them to `uv`. People are not merely installing it, they are forcing their agents onto it.

</details>

<details>
<summary><b>ast-grep</b> — a regex that finds nothing does not look like a bug</summary>

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
<summary><b>sd</b> — find-and-replace that behaves the same on every machine</summary>

The failure is shown at the top of this README. The cause: BSD `sed` takes the argument after `-i` as a backup-file suffix. What you see next depends on the path — `/tmp/demo` and `/tmp/x` produce two different errors on the same machine, because sed is parsing your path as sed source. Some forms leave a stray `.bak` beside the original instead.

The message varies; the invariant does not. **The edit does not happen**, and nothing about the command's shape suggests that in advance.

```bash
echo hello > /tmp/t && sd hello world /tmp/t && cat /tmp/t   # world
```

No `-i`, no suffix ambiguity, no BRE/ERE guessing, and `-F` for literal strings when the pattern is full of metacharacters.

</details>

<details>
<summary><b>gitleaks</b> — the agent copies a live key into a fixture to make a test pass</summary>

The scenario is specific and it happens: the agent is fixing a failing integration test, sees working values in `.env`, and copies them into the test file. The commit goes through. Nothing complains.

Pushing makes it irreversible in the way that matters — rewriting history does not un-leak a key that was public for ten minutes. It has to be rotated.

```bash
gitleaks detect --source . -v
```

Scans the working tree and the full history, and names the rule, file, line and commit:

```
RuleID: github-pat        config_test.go:6
RuleID: aws-access-token  config_test.go:4
RuleID: generic-api-key   config_test.go:5
```

It is also disciplined about false positives — it deliberately ignores the well-known documentation examples like `AKIAIOSFODNN7EXAMPLE`, which is what keeps it from being switched off after a week.

The agent-era part is documented rather than hypothetical: Claude Code has been [reported reading `.env` despite `.claudeignore`](https://www.theregister.com/2026/01/28/claude_code_ai_secrets_files/), and one measured survey found live secrets in the history of 2.4% of repositories carrying AI-tool config directories. In a pre-commit hook this becomes a feedback loop the agent can correct against by itself.

</details>

<details>
<summary><b>actionlint</b> — a workflow typo costs a push and a wait</summary>

When an agent edits `.github/workflows/*.yml`, its only feedback loop is commit, push, wait for the runner, read the log. Minutes per iteration, and CI minutes burned on typos.

```bash
actionlint
```

On a deliberately broken workflow:

```
ci.yml:7:33  "github.event.issue.title" is potentially untrusted. avoid using it
             directly in inline scripts                            [expression]
ci.yml:9:9   shellcheck reported issue in this script:
             SC2086: Double quote to prevent globbing              [shellcheck]
```

The first is a security class, not a style nit: someone files an issue whose title contains shell metacharacters, and your workflow runs it. The second shows the property that earns it a line here — actionlint invokes **shellcheck** on `run:` blocks, so it extends a tool already on this list into a place that tool could not otherwise reach.

Honest limit: it did not catch a third planted bug, a typo in a context property name. Two out of three.

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
<summary><b>gh</b> — scraping works, right up until the markup changes</summary>

Agents routinely need PR state, review comments, CI results, issue bodies.

Unlike the other entries here, this one is not about being wrong. Scraping the star count off a repository page actually returns the right number — I checked. It costs 522 KB of HTML and a regex pinned to today's markup, against one authenticated call returning a typed field:

```bash
gh api repos/rtk-ai/rtk --jq .stargazers_count
```

The failure is deferred rather than absent. A regex over rendered HTML keeps working until GitHub ships a redesign, and then it starts returning nothing or the wrong element — with no error, because a regex that matches the wrong thing looks exactly like a regex that matches the right thing.

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
<summary><b>A language server, wired as MCP</b> — the highest-leverage item here</summary>

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

<details>
<summary><b>jj, if you are willing to change version control</b> — agents delete untracked work</summary>

The failure is well documented, including a verbatim agent apology: *"I accidentally removed your untracked files with git clean, which wasn't my intention."* Git-based checkpointing cannot undo it, because the files were never tracked. Claude Code's own worktree isolation has [deleted gitignored directories from the main tree](https://github.com/anthropics/claude-code/issues/75490) — gigabytes, unrecoverable for the same reason.

[`jj`](https://github.com/jj-vcs/jj) snapshots the working copy into an operation log on every `jj` command, so `jj undo` reaches work that git never saw. It colocates with an existing git repository.

It is out of the Brewfile because it is a change of version control system, not a utility you install and forget — and because it only snapshots when a `jj` command runs, so unattended agents need a hook to trigger one.

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

## Formula names that install the wrong thing

Found while checking candidates for this list. Each of these is a plausible thing to type after reading a recommendation, and each installs something other than what you meant:

| You type | You get |
|---|---|
| `brew install crystal` | The Crystal programming language — not any agent tool |
| `brew install amp` | A terminal text editor — not Sourcegraph's Amp |
| `brew install trash` | A different utility from `trash-cli`, which is keg-only and conflicts with `macos-trash` |
| `brew install mods` | Archived upstream since early 2026 |

A related habit worth borrowing: **GitHub stars are a poor proxy for whether a tool is used.** Homebrew publishes install counts, and the gap can be enormous — one widely-starred agent sandbox has 4,000 stars and 18 installs a month. Check `https://formulae.brew.sh/api/formula/<name>.json` before believing a recommendation, including the ones on this page.

## Scope and maintenance

<details>
<summary>Platform, neutrality, and what this snapshot promises</summary>

**macOS with Homebrew, for now.** Nothing here is conceptually macOS-only — the tools are cross-platform and the reasoning holds anywhere. Homebrew is simply the shortest path to a working machine today, and shipping one platform that actually works beats three that half-work. Linux and Windows packaging are the obvious next step.

**Language-agnostic on purpose.** Anything tied to one language belongs to your project, not to a machine-setup file. The one exception is the language-server note above, and that is a pointer rather than a package.

**Vendor-neutral on purpose.** Nothing here is written by this project. If an entry stops being the best answer, it gets replaced or removed, not defended.

A Brewfile is not a lockfile — Homebrew formulae roll forward, so this installs current versions rather than the ones recorded here.

**Snapshot: 2026-08-17.** Verified against rtk 0.45.0, uv 0.11.1, sd 1.1.0, ast-grep 0.45.1, gitleaks 8.30.1, actionlint 1.7.12, shellcheck 0.11.0, difftastic 0.70.0, yq 4.53.3, hyperfine 1.20.0.

Treat this as a dated snapshot with its reasoning attached, not a maintained index. PRs adding a tool are welcome when they carry a runnable proof of what it prevents or measurably improves. PRs that only assert a tool is good will be closed with a link to this line — that rule is what keeps the list short enough to be worth reading.

</details>

## License

MIT
