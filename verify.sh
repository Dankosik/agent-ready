#!/usr/bin/env bash
# verify.sh — reproduce every claim in README.md on your own machine.
#
# Runs each tool against the alternative an agent would reach for without it,
# and prints both results. Nothing is installed, removed or configured; all
# fixtures live in a temporary directory that is deleted on exit.
#
# The gh check is included even though it does NOT show a correctness win.
# A list you can only confirm is not a list worth trusting.

set -euo pipefail

work="$(mktemp -d)"
cleanup() { [ -n "${work:-}" ] && rm -rf "${work}"; }
trap cleanup EXIT

pass=0 skip=0
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

# A tree of real (non-empty) files, so searches over it do actual work and
# exit 0. Shared by the rtk and hyperfine checks; built at most once.
make_tree() {
	[ -e "${work}/tree/file_1.go" ] && return 0
	mkdir -p "${work}/tree"
	local i
	for i in $(seq 1 300); do
		printf 'package demo\n\nfunc handler%d() error { return nil }\n' "${i}" \
			>"${work}/tree/file_${i}.go"
	done
}

# ---------------------------------------------------------------- rtk
check_rtk() {
	have rtk || return 0
	rule rtk
	make_tree
	local raw filtered
	raw=$(cd "${work}/tree" && rtk proxy find . -name '*.go' 2>/dev/null | wc -c | tr -d ' ')
	filtered=$(cd "${work}/tree" && rtk find . -name '*.go' 2>/dev/null | wc -c | tr -d ' ')
	row "without" "find over 300 files → ${raw} bytes into the model"
	row "with" "same command through rtk → ${filtered} bytes"
	[ "${raw}" -gt 0 ] && row "verdict" "$(awk -v r="${raw}" -v f="${filtered}" \
		'BEGIN{printf "%.0f%% of that output never had to be read", (1-f/r)*100}')"
	pass=$((pass + 1))
}

# ------------------------------------------------------------ ast-grep
check_ast_grep() {
	have ast-grep || return 0
	rule ast-grep
	cat >"${work}/example.js" <<'EOF'
// legacy: foo(1, 2) was removed
const a = foo(1, 2);
const b = foo(
  1,
  2
);
EOF
	row "without" "rg -F 'foo(1, 2)' → lines $(rg -F -n 'foo(1, 2)' "${work}/example.js" | cut -d: -f1 | tr '\n' ' ')"
	row "with" "ast-grep --pattern → lines $(ast-grep --lang js --pattern 'foo(1, 2)' --json=compact "${work}/example.js" | jq -r '[.[] | "\(.range.start.line+1)-\(.range.end.line+1)"] | join(" ")')"
	row "verdict" "rg matched the comment on line 1 and missed the call on 3-6"
	pass=$((pass + 1))
}

# ----------------------------------------------------------------- sd
check_sd() {
	have sd || return 0
	rule sd
	printf 'image: app:v1\n' >"${work}/a.yml"
	printf 'image: app:v1\n' >"${work}/b.yml"
	sed -i 's/app:v1/app:v2/' "${work}/a.yml" >/dev/null 2>&1 || true
	sd 'app:v1' 'app:v2' "${work}/b.yml"
	row "without" "sed -i 's/app:v1/app:v2/' → file reads '$(cat "${work}/a.yml")'"
	row "with" "sd app:v1 app:v2 → file reads '$(cat "${work}/b.yml")'"
	if [ "$(uname)" = "Darwin" ]; then
		row "verdict" "BSD sed took the script as a backup suffix; the edit never happened"
	else
		row "verdict" "GNU sed handles this form — the failure above is macOS-only"
	fi
	pass=$((pass + 1))
}

# --------------------------------------------------------- shellcheck
check_shellcheck() {
	have shellcheck || return 0
	rule shellcheck
	cat >"${work}/buggy.sh" <<'EOF'
#!/bin/bash
f="my file.txt"
if [ -f $f ]; then echo "FOUND"; else echo "MISSING"; fi
EOF
	chmod +x "${work}/buggy.sh"
	: >"${work}/my file.txt"
	local out
	out=$(cd "${work}" && ./buggy.sh 2>/dev/null || true)
	row "without" "the file exists; running the script prints ${out}"
	row "with" "$(shellcheck -f gcc "${work}/buggy.sh" 2>/dev/null | head -1 | sed 's|.*: ||' || true)"
	row "verdict" "no crash, no error — just the wrong answer"
	pass=$((pass + 1))
}

# --------------------------------------------------------- difftastic
check_difftastic() {
	have difft || return 0
	rule difftastic
	local repo="${work}/gitdemo"
	mkdir -p "${repo}"
	git -C "${repo}" init -q
	printf 'function calc(a,b){\n  return a+b;\n}\n' >"${repo}/calc.js"
	git -C "${repo}" add -A
	git -C "${repo}" -c user.email=v@v -c user.name=v commit -qm init
	printf 'function calc(\n  a,\n  b\n) {\n  return a + b;\n}\n' >"${repo}/calc.js"
	row "without" "git diff → $(git -C "${repo}" diff --numstat | awk '{print $1" added, "$2" removed"}')"
	row "with" "difft → $(git -C "${repo}" -c diff.external=difft diff 2>/dev/null | sed -n '2p' | xargs)"
	row "verdict" "the reformat changed nothing; only one of these says so"
	pass=$((pass + 1))
}

# ----------------------------------------------------------------- yq
check_yq() {
	have yq || return 0
	rule yq
	printf '# production values\nreplicas: 2   # tuned after load test\n' >"${work}/y1.yml"
	cp "${work}/y1.yml" "${work}/y2.yml"
	sed 's/replicas: 2.*/replicas: 4/' "${work}/y1.yml" >"${work}/y1.out"
	yq -i '.replicas = 4' "${work}/y2.yml"
	row "without" "line edit → $(sed -n '2p' "${work}/y1.out")"
	row "with" "yq -i '.replicas = 4' → $(sed -n '2p' "${work}/y2.yml")"
	row "verdict" "the line edit silently dropped why the value was 2"
	pass=$((pass + 1))
}

# ----------------------------------------------------------------- jq
check_jq() {
	have jq || return 0
	rule jq
	cat >"${work}/api.json" <<'EOF'
{
  "owner": { "login": "octocat", "name": "The Octocat" },
  "name": "hello-world"
}
EOF
	row "without" "regex for \"name\" → $(rg -o '"name": *"[^"]*"' "${work}/api.json" | head -1)"
	row "with" "jq -r .name → $(jq -r .name "${work}/api.json")"
	row "verdict" "the regex took the nested owner.name; it appears first"
	pass=$((pass + 1))
}

# ----------------------------------------------------------------- gh
check_gh() {
	have gh || return 0
	rule gh
	local html bytes scraped api
	if ! html=$(curl -sfL https://github.com/rtk-ai/rtk 2>/dev/null); then
		row "skipped" "no network"
		skip=$((skip + 1))
		return 0
	fi
	bytes=$(printf '%s' "${html}" | wc -c | tr -d ' ')
	scraped=$(printf '%s' "${html}" | rg -o '[0-9,]+ users starred' | head -1 || echo "no match")
	api=$(gh api repos/rtk-ai/rtk --jq .stargazers_count 2>/dev/null || echo "not authenticated")
	row "without" "${bytes} bytes of HTML, regex → ${scraped}"
	row "with" "gh api --jq .stargazers_count → ${api}"
	row "verdict" "scraping got it right — this one is about cost and staying right"
	pass=$((pass + 1))
}

# ---------------------------------------------------------- hyperfine
check_hyperfine() {
	have hyperfine || return 0
	rule hyperfine
	make_tree
	local a b c
	a=$( { TIMEFORMAT=%R; time rg -c 'func' "${work}/tree" >/dev/null 2>&1; } 2>&1 )
	b=$( { TIMEFORMAT=%R; time rg -c 'func' "${work}/tree" >/dev/null 2>&1; } 2>&1 )
	c=$( { TIMEFORMAT=%R; time rg -c 'func' "${work}/tree" >/dev/null 2>&1; } 2>&1 )
	row "without" "three single runs of the same command → ${a}s ${b}s ${c}s"
	row "with" "$(hyperfine --warmup 2 --runs 10 "rg -c func ${work}/tree" 2>&1 | rg -i 'mean' | xargs)"
	row "verdict" "one run cannot tell a speedup from scheduler noise"
	pass=$((pass + 1))
}

printf 'agent-ready — verifying every claim in README.md\n'
printf 'fixtures in %s (deleted on exit)\n' "${work}"

check_rtk
check_ast_grep
check_sd
check_shellcheck
check_difftastic
check_yq
check_jq
check_gh
check_hyperfine

printf '\n%s\n' "$(printf '%.0s─' $(seq 1 64))"
printf '%d checked, %d skipped. Read the verdicts, not the count.\n' "${pass}" "${skip}"
