#!/usr/bin/env bash

set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)
work=$(mktemp -d)
cleanup() { rm -rf "${work}"; }
trap cleanup EXIT

fake_home="${work}/home"
fake_bin="${work}/bin"
mkdir -p "${fake_home}" "${fake_bin}"

for command in claude codex cursor-agent gemini copilot windsurf; do
	printf '#!/bin/sh\nexit 0\n' >"${fake_bin}/${command}"
	chmod +x "${fake_bin}/${command}"
done
cat >"${fake_bin}/rtk" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${HOME}/rtk-calls"
EOF
chmod +x "${fake_bin}/rtk"

mkdir -p \
	"${fake_home}/.claude" \
	"${fake_home}/.codex" \
	"${fake_home}/.gemini" \
	"${fake_home}/.copilot" \
	"${fake_home}/.cursor" \
	"${fake_home}/dotfiles"
printf 'user claude\n' >"${fake_home}/dotfiles/CLAUDE.md"
ln -s ../dotfiles/CLAUDE.md "${fake_home}/.claude/CLAUDE.md"
printf 'user codex\n' >"${fake_home}/.codex/AGENTS.md"
printf 'user gemini\n' >"${fake_home}/.gemini/GEMINI.md"
printf 'user copilot\n' >"${fake_home}/.copilot/copilot-instructions.md"
cat >"${fake_home}/.cursor/AGENTS.md" <<EOF
user cursor
<!-- agent-ready:start -->
old routing
<!-- agent-ready:end -->
EOF
cat >"${fake_home}/.cursor/hooks.json" <<'EOF'
{
  "version": 1,
  "hooks": {
    "sessionStart": [{"command": "./hooks/existing.sh"}],
    "stop": [{"command": "./hooks/stop.sh"}]
  }
}
EOF

run_install() {
	HOME="${fake_home}" \
	PATH="${fake_bin}:/opt/homebrew/bin:/usr/bin:/bin" \
	CLAUDE_CONFIG_DIR="${fake_home}/.claude" \
	CODEX_HOME="${fake_home}/.codex" \
	COPILOT_HOME="${fake_home}/.copilot" \
		"${root}/install.sh" --configure-only >/dev/null
}

run_install
run_install

for target in \
	"${fake_home}/.claude/CLAUDE.md" \
	"${fake_home}/.codex/AGENTS.md" \
	"${fake_home}/.gemini/GEMINI.md" \
	"${fake_home}/.copilot/copilot-instructions.md" \
	"${fake_home}/.codeium/windsurf/memories/global_rules.md"; do
	[ "$(rg -c '^<!-- agent-ready:start -->$' "${target}")" -eq 1 ]
	[ "$(rg -c '^<!-- agent-ready:end -->$' "${target}")" -eq 1 ]
	rg -q '^Tool routing:$' "${target}"
	if rg -q '^- Go:' "${target}"; then
		printf 'generic install unexpectedly included Go routing in %s\n' "${target}" >&2
		exit 1
	fi
done

rg -q '^user claude$' "${fake_home}/.claude/CLAUDE.md"
[ -L "${fake_home}/.claude/CLAUDE.md" ]
rg -q '^user codex$' "${fake_home}/.codex/AGENTS.md"
rg -q '^user gemini$' "${fake_home}/.gemini/GEMINI.md"
rg -q '^user copilot$' "${fake_home}/.copilot/copilot-instructions.md"
rg -q '^user cursor$' "${fake_home}/.cursor/AGENTS.md"
if rg -q 'agent-ready:' "${fake_home}/.cursor/AGENTS.md"; then
	printf 'legacy Cursor routing block was not removed\n' >&2
	exit 1
fi

jq -e '
	.hooks.stop[0].command == "./hooks/stop.sh" and
	([.hooks.sessionStart[] | select(.command == "./hooks/existing.sh")] | length) == 1 and
	([.hooks.sessionStart[] | select(.command == "cat ./hooks/agent-ready-session-start.json")] | length) == 1
' "${fake_home}/.cursor/hooks.json" >/dev/null
jq -e '.additional_context | contains("Tool routing:")' \
	"${fake_home}/.cursor/hooks/agent-ready-session-start.json" >/dev/null

mkdir -p "${fake_home}/.config/agent-ready/languages"
printf 'enabled\n' >"${fake_home}/.config/agent-ready/languages/go"
run_install
for target in \
	"${fake_home}/.claude/CLAUDE.md" \
	"${fake_home}/.codex/AGENTS.md" \
	"${fake_home}/.gemini/GEMINI.md" \
	"${fake_home}/.copilot/copilot-instructions.md" \
	"${fake_home}/.codeium/windsurf/memories/global_rules.md"; do
	[ "$(rg -c '^- Go:' "${target}")" -eq 1 ]
	rg -qF 'use gopls where compiler semantics matter' "${target}"
done
jq -e '.additional_context | contains("use gopls where compiler semantics matter")' \
	"${fake_home}/.cursor/hooks/agent-ready-session-start.json" >/dev/null

for expected in \
	'init -g --hook-only --auto-patch --no-trust-filters' \
	'init -g --codex --no-trust-filters' \
	'init -g --agent cursor --hook-only --auto-patch --no-trust-filters' \
	'init -g --gemini --hook-only --auto-patch --no-trust-filters' \
	'init -g --copilot --hook-only --auto-patch --no-trust-filters'; do
	rg -qF "${expected}" "${fake_home}/rtk-calls"
done

malformed_home="${work}/malformed-home"
malformed_bin="${work}/malformed-bin"
mkdir -p "${malformed_home}/.claude" "${malformed_bin}"
cp "${fake_bin}/claude" "${fake_bin}/rtk" "${malformed_bin}/"
cat >"${malformed_home}/.claude/CLAUDE.md" <<'EOF'
keep this
<!-- agent-ready:start -->
broken block
EOF
cp "${malformed_home}/.claude/CLAUDE.md" "${work}/before"
if HOME="${malformed_home}" PATH="${malformed_bin}:/opt/homebrew/bin:/usr/bin:/bin" \
	CLAUDE_CONFIG_DIR="${malformed_home}/.claude" \
	"${root}/install.sh" --configure-only >/dev/null 2>&1; then
	printf 'malformed markers unexpectedly succeeded\n' >&2
	exit 1
fi
cmp -s "${work}/before" "${malformed_home}/.claude/CLAUDE.md"

printf 'installer routing checks passed\n'
