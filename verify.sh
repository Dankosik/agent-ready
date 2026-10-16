#!/usr/bin/env bash
# verify.sh — reproduce every claim in README.md on your own machine.
#
# Each check is a small, realistic situation an agent runs into: a repository
# with build output, a Helm values file with a pinned tag, a formatter commit
# that hides one real change, a secret that was "removed" in the next commit.
# The tool is run against the alternative an agent actually reaches for
# without it, and both results are measured, not described.
#
# Every verdict is computed from the output above it, and every claim is
# asserted: if a tool stops beating its alternative, this script fails.
# Nothing is installed, removed or configured; all fixtures live in a
# temporary directory that is deleted on exit.

set -euo pipefail

work="$(mktemp -d)"
cleanup() { [ -n "${work:-}" ] && rm -rf "${work}"; }
trap cleanup EXIT

pass=0 skip=0 fail=0
rule() { printf '\n── %s %s\n' "$1" "$(printf '%.0s─' $(seq 1 $((60 - ${#1}))))"; }
row() { printf '  %-9s %s\n' "$1" "$2"; }
have() {
	if command -v "$1" >/dev/null 2>&1; then
		return 0
	fi
	rule "$1"
	row "skipped" "not installed"
	skip=$((skip + 1))
	return 1
}
bytes() { wc -c | tr -d ' '; }
lines() { grep -c . || true; }
percent() { awk -v r="$1" -v f="$2" 'BEGIN{ if (r > 0) printf "%.0f%%", (1 - f / r) * 100; else print "n/a" }'; }
gitc() { git -c user.email=v@v -c user.name=v -c commit.gpgsign=false "$@"; }

# A claim the check's verdict depends on. Failing claims are reported and make
# the whole run fail, so a verdict is never printed over evidence against it.
claims_ok=1
lacks() { ! grep -q "$1" <<<"$2"; }
claim() {
	local what="$1"
	shift
	if ! "$@" >/dev/null 2>&1; then
		row "FAILED" "${what}"
		claims_ok=0
	fi
}
start() { rule "$1"; claims_ok=1; row "scenario" "$2"; }
finish() {
	if [ "${claims_ok}" -eq 1 ]; then
		pass=$((pass + 1))
	else
		fail=$((fail + 1))
	fi
}

# rtk keeps usage history and tee files in its data directory; point it at the
# fixture directory so this script leaves nothing behind.
rtk_isolated() { HOME="${work}/rtk-home" XDG_DATA_HOME="${work}/rtk-home" XDG_CONFIG_HOME="${work}/rtk-home" rtk "$@"; }

# ---------------------------------------------------------------- rtk
check_rtk() {
	have rtk || return 0
	start rtk "the inner loop: status, log, tests — run dozens of times per task"
	local repo="${work}/rtk-repo" i raw out
	mkdir -p "${repo}"
	git -C "${repo}" init -q -b main
	for i in $(seq 1 30); do
		printf '%s\n' "${i}" >>"${repo}/orders.go"
		git -C "${repo}" add orders.go
		gitc -C "${repo}" commit -qm "feat(orders): change ${i}" \
			-m "Explain why change ${i} was needed; see INC-${i}." \
			-m "Co-authored-by: Reviewer <reviewer@example.com>"
	done
	for i in $(seq 1 40); do : >"${repo}/migration_${i}.sql"; done
	printf 'edit\n' >>"${repo}/orders.go"

	raw=$(git -C "${repo}" log -n 20 | bytes)
	out=$(cd "${repo}" && rtk_isolated git log -n 20)
	row "git log" "${raw} → $(printf '%s' "${out}" | bytes) bytes ($(percent "${raw}" "$(printf '%s' "${out}" | bytes)") saved)"
	claim "rtk git log kept the latest subject" grep -q 'change 30' <<<"${out}"

	raw=$(git -C "${repo}" status | bytes)
	out=$(cd "${repo}" && rtk_isolated git status)
	row "git stat" "${raw} → $(printf '%s' "${out}" | bytes) bytes ($(percent "${raw}" "$(printf '%s' "${out}" | bytes)") saved)"
	claim "rtk git status listed all 40 untracked files" test "$(grep -c 'migration_' <<<"${out}")" -eq 40

	if command -v go >/dev/null 2>&1; then
		local mod="${work}/rtk-go" p
		mkdir -p "${mod}"
		printf 'module example.com/shop\n\ngo 1.21\n' >"${mod}/go.mod"
		for p in cart checkout pricing inventory users auth orders payments shipping tax; do
			mkdir -p "${mod}/${p}"
			printf 'package %s\n\nfunc Add(a, b int) int { return a + b }\n' "${p}" >"${mod}/${p}/${p}.go"
			{
				printf 'package %s\n\nimport "testing"\n' "${p}"
				for i in $(seq 1 15); do
					printf 'func TestAdd%d(t *testing.T) { if Add(%d, 1) != %d { t.Fatal("bad") } }\n' "${i}" "${i}" "$((i + 1))"
				done
			} >"${mod}/${p}/${p}_test.go"
		done
		cat >>"${mod}/tax/tax_test.go" <<'EOF'
func TestVATRounding(t *testing.T) {
	if got, want := Add(19, 0), 20; got != want {
		t.Errorf("VAT for 99.99 EUR: got %d cents, want %d cents", got, want)
	}
}
EOF
		raw=$(cd "${mod}" && go test ./... 2>&1 | bytes || true)
		out=$(cd "${mod}" && rtk_isolated go test ./... 2>&1 || true)
		row "go test" "${raw} → $(printf '%s' "${out}" | bytes) bytes ($(percent "${raw}" "$(printf '%s' "${out}" | bytes)") saved)"
		claim "rtk go test kept the failing assertion" grep -q 'got 19 cents, want 20 cents' <<<"${out}"
		raw=$(cd "${mod}" && go test -v ./... 2>&1 | bytes || true)
		out=$(cd "${mod}" && rtk_isolated go test -v ./... 2>&1 || true)
		row "go test -v" "${raw} → $(printf '%s' "${out}" | bytes) bytes ($(percent "${raw}" "$(printf '%s' "${out}" | bytes)") saved)"
		claim "rtk go test -v kept the failing assertion" grep -q 'got 19 cents, want 20 cents' <<<"${out}"
	else
		row "go test" "skipped: go not installed"
	fi
	row "verdict" "savings scale with how chatty the command is; the failure that matters survives"
	finish
}

# ----------------------------------------------------------------- uv
check_uv() {
	have uv || return 0
	start uv "a one-off script needs a library the system Python does not have"
	cat >"${work}/report.py" <<'EOF'
import humanize, datetime
print("build took", humanize.naturaldelta(datetime.timedelta(seconds=4271)))
EOF
	# --dry-run so this check never installs anything, on any platform.
	local pipout out
	pipout=$(pip3 install --dry-run humanize 2>&1 | head -1 || true)
	row "without" "pip3 install humanize → ${pipout}"
	if ! out=$(uv run --quiet --with humanize "${work}/report.py" 2>&1); then
		row "skipped" "uv could not fetch humanize (offline?)"
		skip=$((skip + 1))
		return 0
	fi
	row "with" "uv run --with humanize → $(tail -1 <<<"${out}")"
	claim "uv run produced the report" grep -q 'build took' <<<"${out}"
	if python3 -c 'import humanize' >/dev/null 2>&1; then
		row "note" "humanize was already importable here, so isolation is not shown"
	else
		row "after" "python3 -c 'import humanize' still fails — nothing leaked into the system"
	fi
	if grep -q 'externally-managed' <<<"${pipout}"; then
		row "verdict" "system Python refuses; the fallbacks are venv sprawl or --break-system-packages"
	else
		row "verdict" "this interpreter allows pip — the refusal above is PEP 668 specific"
	fi
	finish
}

# ----------------------------------------------------------------- sd
check_sd() {
	have sd || return 0
	start sd "add ?sslmode=require&connect_timeout=5 to DATABASE_URL in .env"
	local old='postgres://db.internal:5432/shop'
	local new='postgres://db.internal:5432/shop?sslmode=require&connect_timeout=5'
	printf 'DATABASE_URL=%s\n' "${old}" >"${work}/sed.env"
	printf 'DATABASE_URL=%s\n' "${old}" >"${work}/sd.env"
	# The natural sed command: '|' as delimiter so the slashes need no escaping.
	sed "s|${old}|${new}|" "${work}/sed.env" >"${work}/sed.out"
	sd -F "${old}" "${new}" "${work}/sd.env"
	row "without" "sed 's|…|…&connect_timeout=5|' → $(cut -d= -f2- "${work}/sed.out")"
	row "with" "sd -F … → $(cut -d= -f2- "${work}/sd.env")"
	claim "sd wrote the URL exactly" test "$(cat "${work}/sd.env")" = "DATABASE_URL=${new}"
	claim "sed did not" test "$(cat "${work}/sed.out")" != "DATABASE_URL=${new}"
	row "verdict" "sed expanded the unescaped & into the matched text; exit 0, no warning"
	if [ "$(uname)" = "Darwin" ]; then
		printf 'image: app:v1\n' >"${work}/deploy.yml"
		(cd "${work}" && sed -i -e 's/app:v1/app:v2/' deploy.yml)
		row "macOS" "sed -i -e … also left a stray deploy.yml-e next to the file (BSD -i ate -e as a suffix)"
		claim "BSD sed -i -e left a backup file" test -e "${work}/deploy.yml-e"
	fi
	finish
}

# ------------------------------------------------------------- ripgrep
check_ripgrep() {
	have rg || return 0
	start ripgrep "find where fetchWithRetry is used in a built web app"
	local repo="${work}/webapp" raw rgout grep_files rg_files
	mkdir -p "${repo}/src/api" "${repo}/dist" "${repo}/coverage/lcov-report"
	git -C "${repo}" init -q
	printf 'node_modules/\ndist/\ncoverage/\n' >"${repo}/.gitignore"
	cat >"${repo}/src/api/http.ts" <<'EOF'
export async function fetchWithRetry(url: string, opts: { retries: number }) {
  for (let i = 0; i <= opts.retries; i++) {
    try { return await fetch(url); } catch (e) { if (i === opts.retries) throw e; }
  }
}
EOF
	cat >"${repo}/src/api/orders.ts" <<'EOF'
import { fetchWithRetry } from "./http";
export const loadOrders = (userId: string) =>
  fetchWithRetry(`/users/${userId}/orders`, { retries: 3 });
EOF
	# What a build leaves behind: a one-line minified bundle, its source map,
	# and a coverage report that embeds the source.
	awk 'BEGIN { for (i = 0; i < 6000; i++) printf "function a%d(t,e){return t+e*%d};", i, i
		printf "async function fetchWithRetry(u,o){for(let i=0;i<=o.retries;i++)try{return await fetch(u)}catch(e){if(i===o.retries)throw e}};"
		for (i = 0; i < 6000; i++) printf "function b%d(t,e){return t-e*%d};", i, i; print "" }' >"${repo}/dist/app.min.js"
	awk 'BEGIN { printf "{\"version\":3,\"sources\":[\"src/api/http.ts\"],\"names\":[\"fetchWithRetry\"],\"mappings\":\""
		for (i = 0; i < 20000; i++) printf "AAAA,"; print "\"}" }' >"${repo}/dist/app.min.js.map"
	for _ in $(seq 1 20); do cat "${repo}/src/api/http.ts"; done >"${repo}/coverage/lcov-report/http.ts.html"
	git -C "${repo}" add .gitignore src
	gitc -C "${repo}" commit -qm "api: add fetchWithRetry"

	raw=$(cd "${repo}" && grep -rn fetchWithRetry . | bytes)
	grep_files=$(cd "${repo}" && grep -rl fetchWithRetry . | lines)
	rgout=$(cd "${repo}" && rg -n fetchWithRetry .)
	rg_files=$(cd "${repo}" && rg -l fetchWithRetry . | lines)
	row "without" "grep -rn → ${grep_files} files, ${raw} bytes (bundle, source map, coverage, .git)"
	row "with" "rg -n → ${rg_files} files, $(printf '%s\n' "${rgout}" | bytes) bytes"
	claim "rg returned exactly the two source files" test "${rg_files}" -eq 2
	claim "grep returned build output too" test "${grep_files}" -gt 2
	row "verdict" "one minified line was enough to put ~$((raw / 1024)) KB of noise into context"
	finish
}

# ------------------------------------------------------------ ast-grep
# shellcheck disable=SC2016 # $NAME and $PROPS are ast-grep metavariables
check_ast_grep() {
	have ast-grep || return 0
	start ast-grep "migrate analytics.track(name, props) → analytics.track({ event, properties })"
	local src="${work}/checkout.ts"
	cat >"${src}" <<'EOF'
import { analytics } from "./analytics";

// analytics.track(name, props) is deprecated: use analytics.track({ event, properties })
export function onCheckout(cart: Cart, user: User) {
  analytics.track("checkout_started", { items: cart.items.length });
  const hint = "call analytics.track(name, props) once per step";
  analytics.track(
    "checkout_completed",
    { orderId: cart.id, total: cart.total, currency: cart.currency, coupon: cart.coupon ?? null }
  );
  if (user.isFirstOrder) {
    analytics.track("first_order", {
      userId: user.id,
      channel: user.signupChannel,
    });
  }
  player.track("intro.mp3", { loop: false });
}
EOF
	local rg_hits sed_done ag_done left
	rg_hits=$(rg -n 'analytics\.track\(' "${src}" | cut -d: -f1 | paste -sd' ' -)
	sed -E 's/analytics\.track\(("[^"]*"), (\{[^}]*\})\)/analytics.track({ event: \1, properties: \2 })/' \
		"${src}" >"${work}/checkout.sed.ts"
	sed_done=$(grep -c 'track({ event:' "${work}/checkout.sed.ts" || true)
	cp "${src}" "${work}/checkout.ag.ts"
	ast-grep run --lang ts -p 'analytics.track($NAME, $PROPS)' \
		-r 'analytics.track({ event: $NAME, properties: $PROPS })' -U "${work}/checkout.ag.ts" >/dev/null 2>&1
	ag_done=$(grep -c 'track({ event:' "${work}/checkout.ag.ts" || true)
	left=$(ast-grep run --lang ts -p 'analytics.track($NAME, $PROPS)' --json=compact "${work}/checkout.ag.ts" | jq length || true)
	row "find" "rg → lines ${rg_hits} (3 calls + a comment + a string)"
	row "without" "sed -E rewrite → ${sed_done} of 3 calls migrated; the two wrapped calls kept the old API"
	row "with" "ast-grep -p … -r … → ${ag_done} of 3 migrated, ${left} old calls left"
	claim "ast-grep migrated all three calls" test "${ag_done}" -eq 3
	claim "no old-style call is left" test "${left}" -eq 0
	claim "the comment, the string and player.track were not touched" \
		test "$(grep -c 'track(name, props)\|player.track("intro' "${work}/checkout.ag.ts")" -eq 3
	claim "sed missed the calls a formatter wrapped" test "${sed_done}" -lt 3
	row "verdict" "Prettier wraps long calls; a line-based rewrite misses exactly those, silently"
	finish
}

# ----------------------------------------------------------------- gh
check_gh() {
	have gh || return 0
	start gh "did the last finished CI run on main pass, and for which commit?"
	local html matches api
	if ! html=$(curl -sfL https://github.com/Dankosik/agent-ready/actions 2>/dev/null); then
		row "skipped" "no network"
		skip=$((skip + 1))
		return 0
	fi
	if ! api=$(gh run list -R Dankosik/agent-ready -w CI -b main -s completed -L 1 \
		--json conclusion,headSha --jq '.[0] | "\(.conclusion) at \(.headSha[0:7])"' 2>/dev/null); then
		row "skipped" "gh is not authenticated"
		skip=$((skip + 1))
		return 0
	fi
	matches=$(printf '%s' "${html}" | grep -o 'completed successfully\|failed' | sort | uniq -c | awk '{c=$1; $1=""; printf "%s×%s ", c, substr($0, 2)}')
	row "without" "$(printf '%s' "${html}" | bytes) bytes of HTML, grep → ${matches:-nothing}"
	row "with" "gh run list -w CI -b main -s completed --json → ${api}"
	claim "gh returned a conclusion tied to a commit" grep -Eq '^[a-z_]+ at [0-9a-f]{7}$' <<<"${api}"
	row "verdict" "the page mixes every workflow and branch; the API answers the question asked"
	finish
}

# ---------------------------------------------------------- worktrunk
check_worktrunk() {
	have wt || return 0
	start worktrunk "clean up worktrees whose work already landed on main"
	local repo="${work}/wt/repo" merged json
	mkdir -p "${repo}"
	git -C "${repo}" init -q -b main
	printf 'base\n' >"${repo}/tracked.txt"
	git -C "${repo}" add tracked.txt
	gitc -C "${repo}" commit -qm init
	# squashed: merged through a GitHub-style squash merge.
	git -C "${repo}" worktree add -q -b squashed "${work}/wt/squashed"
	printf 'a\n' >"${work}/wt/squashed/feature.txt"
	git -C "${work}/wt/squashed" add feature.txt
	gitc -C "${work}/wt/squashed" commit -qm "feature part 1"
	printf 'b\n' >>"${work}/wt/squashed/feature.txt"
	gitc -C "${work}/wt/squashed" commit -qam "feature part 2"
	git -C "${repo}" merge -q --squash squashed >/dev/null
	gitc -C "${repo}" commit -qm "feature (#12)"
	# wip: no commits of its own, but uncommitted work in the tree.
	git -C "${repo}" worktree add -q -b wip "${work}/wt/wip"
	printf 'half-done\n' >>"${work}/wt/wip/tracked.txt"

	merged=$(git -C "${repo}" branch --merged main | tr -d '*+ ' | grep -v '^main$' | paste -sd' ' -)
	json=$(wt -C "${repo}" list --format=json --config-set list.json-schema=2)
	row "without" "git branch --merged main → ${merged:-none}"
	row "with" "wt list → $(jq -r '[.items[] | select(.branch != "main") | "\(.branch)=\(.display.state // "no-commits")\(if .worktree.changes.modified then "+dirty" else "" end)"] | join(" ")' <<<"${json}")"
	claim "git calls wip merged" grep -qw wip <<<"${merged}"
	claim "git misses the squash-merged branch" lacks squashed "${merged}"
	claim "wt sees the squash merge" jq -e '.items[] | select(.branch == "squashed") | .display.state == "integrated"' <<<"${json}"
	claim "wt sees the uncommitted work" jq -e '.items[] | select(.branch == "wip") | .worktree.changes.modified' <<<"${json}"
	row "verdict" "git's answer is backwards for squash-merge repos: keeps the done branch, offers the dirty one"
	finish
}

# ----------------------------------------------------------------- jq
check_jq() {
	have jq || return 0
	start jq "which CI jobs failed, and at which step? (GitHub jobs API, minified)"
	local f="${work}/jobs.json" n
	# Key order follows the real API: a job's status and conclusion come before
	# its name, and every step carries its own conclusion.
	{
		printf '{"total_count":4,"jobs":['
		n=0
		for job in "lint:success:golangci-lint" "unit-tests:failure:go test ./..." \
			"integration:failure:docker compose up" "build:success:go build"; do
			IFS=: read -r name concl failing <<<"${job}"
			[ "${n}" -gt 0 ] && printf ','
			n=$((n + 1))
			printf '{"id":%d,"run_id":7,"head_branch":"main","status":"completed","conclusion":"%s","name":"%s","steps":[' \
				"${n}" "${concl}" "${name}"
			printf '{"name":"Set up job","status":"completed","conclusion":"success","number":1},'
			printf '{"name":"Checkout","status":"completed","conclusion":"success","number":2},'
			printf '{"name":"%s","status":"completed","conclusion":"%s","number":3}]}' "${failing}" "${concl}"
		done
		printf ']}\n'
	} >"${f}"
	local grepped jqout
	grepped=$(grep -o '"conclusion":"failure"' "${f}" | lines)
	jqout=$(jq -r '.jobs[] | select(.conclusion == "failure") | "\(.name) at \"\(.steps[] | select(.conclusion == "failure") | .name)\""' "${f}" | paste -sd';' -)
	row "without" "grep -o '\"conclusion\":\"failure\"' | wc -l → ${grepped} failures"
	row "with" "jq … → ${jqout}"
	claim "grep double-counted job and step failures" test "${grepped}" -eq 4
	claim "jq named both failed jobs and their steps" \
		test "${jqout}" = 'unit-tests at "go test ./...";integration at "docker compose up"'
	row "verdict" "on one-line JSON a match has no owner; the count was wrong and the names unreachable"
	finish
}

# ----------------------------------------------------------- gitleaks
check_gitleaks() {
	have gitleaks || return 0
	start gitleaks "a key went into a test fixture, then 'was removed' in the next commit"
	local repo="${work}/secrets" tree dir hist
	mkdir -p "${repo}"
	git -C "${repo}" init -q
	{
		printf '%s\n' 'package config' '' '// fixture: copied from .env so the integration test passes'
		printf 'const %s = "%s%s"\n' 'awsKeyID' 'AKIA4X7QZP2NVBW' 'K3TLM'
		printf 'const %s = "%s%s"\n' 'ghToken' 'ghp_9fK2mQ7xR4tL8wZ1nB5v' 'C3jH6yD0sA4gT2eU'
	} >"${repo}/config_test.go"
	git -C "${repo}" add -A
	gitc -C "${repo}" commit -qm "add integration fixture"
	printf 'package config\n\n// fixture values come from the environment\n' >"${repo}/config_test.go"
	gitc -C "${repo}" commit -qam "remove secrets from fixture"

	tree=$( (rg -l 'AKIA|ghp_' "${repo}" || true) | lines)
	dir=$(gitleaks dir --no-banner --report-format json --report-path "${work}/dir.json" "${repo}" >/dev/null 2>&1 || true; jq length "${work}/dir.json")
	hist=$(gitleaks git --no-banner --report-format json --report-path "${work}/git.json" "${repo}" >/dev/null 2>&1 || true; jq -r '[.[].RuleID] | unique | join(" ")' "${work}/git.json")
	row "without" "rg over the working tree → ${tree} files; the cleanup commit looks complete"
	row "also" "gitleaks dir (tree only) → ${dir} findings"
	row "with" "gitleaks git → ${hist:-nothing}"
	claim "the working tree is clean" test "${tree}" -eq 0
	claim "history scan found both keys" test "$(jq length "${work}/git.json")" -eq 2
	row "verdict" "deleting the line does not delete the commit; once pushed, rotate the key"
	finish
}

# ---------------------------------------------------------- actionlint
check_actionlint() {
	have actionlint || return 0
	start actionlint "an issue-triage workflow written by an agent"
	mkdir -p "${work}/.github/workflows"
	local wf="${work}/.github/workflows/triage.yml" out
	cat >"${wf}" <<'EOF'
name: triage
on:
  issues:
    types: [opened]
jobs:
  label:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-dept: 0
      - name: Label bugs
        run: |
          if echo "${{ github.event.issue.title }}" | grep -qi bug; then
            gh issue edit ${{ github.event.issue.number }} --add-label bug
          fi
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
EOF
	row "without" "yq parses it → $(yq '.jobs.label.steps | length' "${wf}") steps; YAML is valid, so nothing to fix until it runs"
	# actionlint exits non-zero when it finds anything, which is the normal case here.
	out=$(actionlint -no-color -oneline "${wf}" 2>/dev/null || true)
	row "with" "actionlint → $(printf '%s\n' "${out}" | lines) findings, locally, in milliseconds"
	printf '%s\n' "${out}" | sed -E 's|^[^ ]+ ||; s/(.{68}).*/\1…/; s/^/            /'
	claim "found the script injection" grep -q 'potentially untrusted' <<<"${out}"
	claim "found the misspelled input" grep -q 'fetch-dept' <<<"${out}"
	row "verdict" "an issue title can run code with GITHUB_TOKEN; the typo would be ignored at runtime"
	finish
}

# --------------------------------------------------------- shellcheck
check_shellcheck() {
	have shellcheck || return 0
	start shellcheck "a deploy script; the build-dir file is missing on a fresh runner"
	local script="${work}/deploy.sh" out
	cat >"${script}" <<'EOF'
#!/usr/bin/env bash
set -e
BUILD_DIR=$(cat .build-dir 2>/dev/null || true)
echo "cleaning previous build"
rm -rf "$BUILD_DIR"/*
EOF
	row "without" "bash -n → $(bash -n "${script}" 2>&1 && echo 'syntax OK')"
	# Show what rm would receive with BUILD_DIR empty — without running rm.
	local BUILD_DIR=""
	local targets=("${BUILD_DIR}"/*)
	row "runtime" "with BUILD_DIR empty, rm gets ${#targets[@]} paths: $(printf '%s ' "${targets[@]:0:3}")…"
	out=$(shellcheck -f gcc "${script}" 2>/dev/null || true)
	row "with" "$(grep SC2115 <<<"${out}" | sed 's|.*: warning: ||')"
	claim "shellcheck flagged the rm" grep -q SC2115 <<<"${out}"
	claim "the glob really expands under /" test "${targets[0]#/}" != "${targets[0]}"
	row "verdict" "same bug class that wiped home directories in the Steam for Linux launcher (2015)"
	finish
}

# --------------------------------------------------------- difftastic
check_difftastic() {
	have difft || return 0
	start difftastic "review a 'run prettier' commit — did anything besides formatting change?"
	local repo="${work}/review" plain changed out
	mkdir -p "${repo}"
	git -C "${repo}" init -q
	cat >"${repo}/order.ts" <<'EOF'
export async function createOrder(client: ApiClient, cart: Cart, user: User): Promise<Order> {
  const total = cart.items.reduce((sum, item) => sum + item.price * item.quantity, 0);
  if (total > user.creditLimit) { throw new CreditLimitError(user.id, total); }
  return client.post("/orders", { userId: user.id, items: cart.items, total: total, currency: cart.currency });
}
EOF
	git -C "${repo}" add -A
	gitc -C "${repo}" commit -qm init
	cat >"${repo}/order.ts" <<'EOF'
export async function createOrder(
  client: ApiClient,
  cart: Cart,
  user: User
): Promise<Order> {
  const total = cart.items.reduce(
    (sum, item) => sum + item.price * item.quantity,
    0
  );
  if (total > user.creditLimit) {
    throw new CreditLimitError(user.id, total);
  }
  return client.post("/orders", {
    userId: user.id,
    items: cart.items,
    total: total,
    currency: cart.currency
  });
}
EOF
	git -C "${repo}" show HEAD:order.ts >"${work}/order.old.ts"
	plain=$(git -C "${repo}" diff -w | grep -c '^[-+][^-+]' || true)
	out=$(difft --check-only --exit-code "${work}/order.old.ts" "${repo}/order.ts" 2>&1 || true)
	row "pure fmt" "git diff -w → ${plain} changed lines; difft --check-only → $(grep -o 'No syntactic changes\|Has syntactic changes' <<<"${out}")"
	claim "difft recognised a formatting-only change" grep -q 'No syntactic changes' <<<"${out}"

	# Same commit, but one real change hidden in the reformat.
	sed 's/item.price \* item.quantity,/item.price * item.quantity * (1 - item.discount),/' \
		"${repo}/order.ts" >"${work}/order.new.ts" && mv "${work}/order.new.ts" "${repo}/order.ts"
	changed=$(git -C "${repo}" diff -w | grep -c '^[-+][^-+]' || true)
	out=$(difft --check-only --exit-code "${work}/order.old.ts" "${repo}/order.ts" 2>&1 || true)
	row "hidden" "git diff -w → ${changed} changed lines; difft → $(grep -o 'No syntactic changes\|Has syntactic changes' <<<"${out}")"
	claim "difft flagged the hidden change" grep -q 'Has syntactic changes' <<<"${out}"
	claim "git diff could not tell the two commits apart" test "${plain}" -eq "${changed}"
	row "verdict" "both commits show ${plain} changed lines to git; one exit code separates them"
	finish
}

# ----------------------------------------------------------------- yq
check_yq() {
	have yq || return 0
	start yq "bump the worker image to 1.16.0 in Helm values; the api tag is pinned"
	local f="${work}/values.yaml"
	cat >"${f}" <<'EOF'
# Helm values for the checkout service.
api:
  image:
    repository: ghcr.io/acme/checkout-api
    tag: "1.14.2"   # pinned: 1.15+ leaks DB connections (INC-2291)
  replicas: 3

worker:
  image:
    repository: ghcr.io/acme/checkout-worker
    tag: "1.14.2"
  replicas: 2       # consumes the queue in order; never scale above 2
EOF
	cp "${f}" "${work}/values.sed.yaml"
	cp "${f}" "${work}/values.yq.yaml"
	sed 's/tag: "1.14.2"/tag: "1.16.0"/' "${f}" >"${work}/values.sed.yaml"
	yq -i '.worker.image.tag = "1.16.0"' "${work}/values.yq.yaml"
	row "without" "sed → api tag $(yq '.api.image.tag' "${work}/values.sed.yaml"), worker tag $(yq '.worker.image.tag' "${work}/values.sed.yaml") — the pin is gone"
	if cp "${f}" "${work}/values.py.yaml" && uv run --quiet --with pyyaml python3 - "${work}/values.py.yaml" >/dev/null 2>&1 <<'EOF'; then
import sys, yaml
path = sys.argv[1]
data = yaml.safe_load(open(path))
data["worker"]["image"]["tag"] = "1.16.0"
yaml.safe_dump(data, open(path, "w"), sort_keys=False)
EOF
		row "also" "PyYAML load/dump → $(grep -c '#' "${work}/values.py.yaml" || true) of 3 comments left, tag quoting dropped"
	fi
	row "with" "yq -i '.worker.image.tag = \"1.16.0\"' → api $(yq '.api.image.tag' "${work}/values.yq.yaml"), worker $(yq '.worker.image.tag' "${work}/values.yq.yaml"), $(grep -c '#' "${work}/values.yq.yaml") of 3 comments kept"
	claim "yq changed only the worker tag" test \
		"$(yq -o json '.worker.image.tag = "1.14.2"' "${work}/values.yq.yaml")" = "$(yq -o json "${f}")"
	claim "yq kept every comment" test "$(grep -c '#' "${work}/values.yq.yaml")" -eq 3
	claim "sed also moved the pinned api tag" test "$(yq '.api.image.tag' "${work}/values.sed.yaml")" = "1.16.0"
	row "note" "yq normalises whitespace: blank lines and comment alignment change ($(diff "${f}" "${work}/values.yq.yaml" | grep -c '^[<>]' || true) diff lines, not 2)"
	row "verdict" "a text edit can't tell the two tags apart; a YAML round-trip throws away the reason for the pin"
	finish
}

# ---------------------------------------------------------------- mdq
# shellcheck disable=SC2016 # backticks are Markdown, not command substitution
check_mdq() {
	have mdq || return 0
	start mdq "read the Configuration section of a long README with shell examples"
	local f="${work}/README.md" i awked selected
	{
		printf '# Payments service\n\n## Setup\n\n```bash\n# install dependencies\nmake deps\n```\n\n'
		printf '## Configuration\n\nSet `PAYMENTS_KEY`.\n\n```bash\n# rotate the webhook secret\n./scripts/rotate.sh\n```\n\n'
		printf 'Restart workers after rotation.\n\n### Retries\n\nAt most 5, with jitter.\n\n## Deployment\n\nArgoCD.\n'
		for i in $(seq 1 40); do
			printf '\n## Runbook %d\n\n' "${i}"
			seq 1 30 | sed 's/^/- step /'
		done
	} >"${f}"
	awked=$(awk '/^## Configuration/{f=1; print; next} /^##? /{if (f) exit} f' "${f}")
	selected=$(mdq --link-format keep '# Configuration' "${f}")
	row "without" "cat → $(bytes <"${f}") bytes; awk heading range → stops at '# rotate the webhook secret'"
	row "with" "mdq '# Configuration' → $(printf '%s\n' "${selected}" | bytes) bytes, incl. code block and ### Retries"
	claim "awk cut the section at a shell comment" lacks rotate.sh "${awked}"
	claim "mdq returned the full section" grep -q 'At most 5' <<<"${selected}"
	claim "mdq stopped at the next section" lacks ArgoCD "${selected}"
	row "verdict" "a '#' inside a code fence is a comment, not a heading — only a parser knows"
	finish
}

# ---------------------------------------------------------- hyperfine
check_hyperfine() {
	have hyperfine || return 0
	start hyperfine "'my change made search faster' — A/A test: both sides are the same command"
	local tree="${work}/bench" i times spread
	mkdir -p "${tree}"
	for i in $(seq 1 2000); do
		printf 'package demo\n\nfunc handler%d() error { return nil }\n' "${i}" >"${tree}/file_${i}.go"
	done
	times=$(for i in 1 2 3 4 5 6; do
		{ TIMEFORMAT=%R; time rg -c func "${tree}" >/dev/null 2>&1; } 2>&1
	done | paste -sd' ' -)
	spread=$(tr ' ' '\n' <<<"${times}" | sort -n | awk 'NR==1{min=$1} {max=$1} END{ if (min > 0) printf "%.0f", (max/min - 1) * 100; else print 0 }')
	row "without" "six single runs of one command → ${times}s"
	row "" "picking two of them 'shows' a ${spread}% speedup that does not exist"
	hyperfine -N --warmup 5 --runs 30 --export-json "${work}/aa.json" \
		-n A "rg -c func ${tree}" -n B "rg -c func ${tree}" >/dev/null 2>&1
	# B/A with its propagated uncertainty, the way hyperfine prints "x ± y times faster".
	# Computed from the raw timings: hyperfine 1.x exports .times, 2.x .measurements.
	local verdict
	verdict=$(jq -r '
		def times: if .times then .times else [.measurements[].time_wall_clock.value] end;
		def stats: times as $t | ($t | add / length) as $m
			| {mean: $m, sd: (($t | map((. - $m) * (. - $m)) | add / (length - 1)) | sqrt)};
		[.results[] | stats] as [$a, $b] | ($b.mean / $a.mean) as $r
		| ($r * ((($a.sd / $a.mean) | . * .) + (($b.sd / $b.mean) | . * .) | sqrt)) as $e
		| "\($r * 100 | round / 100) ± \($e * 100 | round / 100) \(if (($r - 1) | fabs) <= 2 * $e then "→ no measurable difference" else "→ different" end)"' "${work}/aa.json")
	row "with" "hyperfine, 30 runs each → B/A = ${verdict}"
	claim "hyperfine did not find a difference between identical commands" grep -q 'no measurable difference' <<<"${verdict}"
	row "verdict" "a difference smaller than the ± is not a result; one run cannot show the ±"
	finish
}

printf 'agent-ready — verifying every claim in README.md\n'
printf 'fixtures in %s (deleted on exit)\n' "${work}"

check_rtk
check_uv
check_sd
check_ripgrep
check_ast_grep
check_gh
check_worktrunk
check_jq
check_gitleaks
check_actionlint
check_shellcheck
check_difftastic
check_yq
check_mdq
check_hyperfine

printf '\n%s\n' "$(printf '%.0s─' $(seq 1 64))"
printf '%d held, %d failed, %d skipped.\n' "${pass}" "${fail}" "${skip}"
[ "${fail}" -eq 0 ]
