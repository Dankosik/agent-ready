# Repository development rules

These rules apply to every change in this repository. Keep the repository safe
for people who run its installers against real machines and real agent configs.

## Scope and design

- Keep the root installer language-independent. Language-specific tools belong
  under `languages/<name>/` with their own Brewfile, installer, and verifier.
- Prefer Bash, standard tools, and existing dependencies. Do not add a helper,
  abstraction, tap, or Action when the repository already has a sufficient path.
- Preserve macOS, Linux, and WSL2 behavior. A platform claim requires a runnable
  check on that platform.
- Homebrew installs must not upgrade existing formulae by default. Upgrades stay
  explicit through `--upgrade`; configuration-only work stays behind
  `--configure-only`.

## Protect user machines

- Treat changes to `install.sh`, `bootstrap.sh`, hooks, MCP configuration, and
  instruction files as security-sensitive migrations.
- Never use `sudo`, delete unrelated user data, replace an entire existing
  config, or write outside the documented config paths.
- Preserve existing content, validate before replacing, use same-directory
  temporary files plus atomic moves, and fail closed on malformed input.
- Installer tests must use an isolated temporary `HOME` and fake executables.
  Never run a development test against real agent configuration.
- Keep repeated installation idempotent. Every new mutation path needs the
  smallest regression check in `test-install.sh`.
- Do not embed real or scanner-shaped credentials in tracked source. Construct
  synthetic scanner fixtures only at runtime. `.gitleaksignore` may contain
  exact reviewed fingerprints only; never add broad path, rule, or commit
  exclusions to make a scan pass.
- Security reports go through the private process in `SECURITY.md`, never a
  public issue before disclosure.

## Worktrees and branches

- Start with `rtk wt list` and confirm the current checkout is understood.
- Never develop directly on `main`. Create an isolated `codex/<short-slug>`
  worktree from the current protected `main`.
- Treat every worktree as a separate CodeGraph project. Check its status and
  initialize only that worktree when needed. This repository is mostly shell,
  YAML, and Markdown, so use `rg` directly when CodeGraph has no useful nodes.
- Preserve unrelated dirty work. Stage explicit paths, never a blind `git add -A`
  in a mixed worktree.
- Do not commit, push, merge, or release unless the task authorizes publication.

## Required local checks

Run the checks that apply to the exact candidate. The full acceptance ladder is:

```bash
rtk bash -n bootstrap.sh install.sh test-install.sh verify.sh languages/go/install.sh languages/go/verify.sh
rtk shellcheck bootstrap.sh install.sh test-install.sh verify.sh languages/go/install.sh languages/go/verify.sh
rtk actionlint
rtk gitleaks dir --redact .
rtk gitleaks git --redact .
rtk ./test-install.sh
rtk ./verify.sh
rtk env HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file Brewfile
rtk env HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file languages/go/Brewfile
rtk ./languages/go/verify.sh
rtk git diff --check
```

Do not claim success for a skipped, failing, or unrun applicable check. The Go
verifier may be omitted only when Go support is untouched and unavailable; say
so explicitly.

## GitHub and pull requests

- `main` is protected. Never push directly or use an administrator bypass.
- Pin every GitHub Action to a full commit SHA. Repository policy allows only
  GitHub-owned Actions; adding another publisher requires explicit approval and
  security review.
- Push the isolated branch and open a draft PR with the problem, user impact,
  exact diff scope, and validation results.
- Before merge, require terminal success for the current PR head from:
  `verify (macos-latest)`, `verify (ubuntu-latest)`, `wsl`, and
  `Analyze (actions)`.
- If `main` moves, update the branch and rerun the required checks. Never reuse
  receipts from another SHA.
- Mark the PR ready only after review of the final diff. Merge by GitHub squash
  so `main` receives one verified, signed commit with linear history.
- Feature-branch signatures are not an acceptance unit. The resulting squash
  commit on `main` must read back as GitHub `verified: true`.
- After merge, wait for the push CI on the exact new `main` SHA. Only then remove
  the remote branch and worktree.

## Releases

- Publishing a release always requires explicit user authorization.
- Use Semantic Versioning tags in the form `vX.Y.Z`. A release candidate must be
  the exact verified commit on protected `main`, with post-merge CI and CodeQL
  terminal-success for that SHA.
- Prepare a release PR that changes every public install URL and matching
  `AGENT_READY_REF` in `README.md` to the same new version. Moving `main` URLs
  are forbidden. Confirm with `rg` before merge.
- Review release notes and the final tree before publishing. Do not release from
  a feature branch, dirty checkout, local-only commit, or merely green PR head.
- Immutable releases are mandatory. Publish `vX.Y.Z` against the exact accepted
  `main` SHA; never move, delete, or reuse a release tag.
- Immediately read back the release and tag through the GitHub API. The release
  must report `immutable: true`, and the tag must resolve to the accepted SHA.
- Run the documented version-pinned `curl | AGENT_READY_REF=... bash` path in an
  isolated temporary `HOME` with fake agent executables. This validates the
  public bootstrap and archive, not just the local checkout.
- A release is complete only when the immutable tag, release readback, isolated
  install proof, and clean post-release repository state all agree.

## Stop conditions

Stop without merging or releasing when any applicable check is red or pending,
the candidate SHA changes, required GitHub protection is missing, unrelated
work is present, or the release/tag/readback identities disagree. Report the
exact blocker instead of weakening a guardrail.
