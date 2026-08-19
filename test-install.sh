#!/usr/bin/env bash

set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)
work=$(mktemp -d)
cleanup() { rm -rf "${work}"; }
trap cleanup EXIT

fake_home="${work}/home"
fake_bin="${work}/bin"
test_path="${fake_bin}:${PATH}"
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
cat >"${fake_bin}/gopls" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "${fake_bin}/gopls"
cat >"${fake_bin}/brew" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${HOME}/brew-calls"
EOF
chmod +x "${fake_bin}/brew"

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
	XDG_CONFIG_HOME="${fake_home}/.config" \
	PATH="${test_path}" \
	CLAUDE_CONFIG_DIR="${fake_home}/.claude" \
	CODEX_HOME="${fake_home}/.codex" \
	COPILOT_HOME="${fake_home}/.copilot" \
		"${root}/install.sh" --configure-only >/dev/null
}

run_tool_install() {
	HOME="${fake_home}" \
	XDG_CONFIG_HOME="${fake_home}/.config" \
	PATH="${test_path}" \
	CODEX_HOME="${fake_home}/.codex" \
		"${root}/bootstrap.sh" --agent codex "$@" >/dev/null
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
	'init -g --agent cursor --hook-only --no-patch --no-trust-filters' \
	'init -g --gemini --hook-only --auto-patch --no-trust-filters' \
	'init -g --copilot --hook-only --auto-patch --no-trust-filters'; do
	rg -qF "${expected}" "${fake_home}/rtk-calls"
done

run_tool_install
run_tool_install --upgrade
rg -qF "bundle --no-upgrade --file ${root}/Brewfile" "${fake_home}/brew-calls"
rg -qF "bundle --file ${root}/Brewfile" "${fake_home}/brew-calls"
if run_tool_install --configure-only --upgrade >/dev/null 2>&1; then
	printf 'conflicting install options unexpectedly succeeded\n' >&2
	exit 1
fi

targeted_home="${work}/targeted-home"
archive_root="${work}/archive/agent-ready-test"
archive="${work}/agent-ready-test.tar.gz"
mkdir -p "${targeted_home}" "${archive_root}"
cp "${root}/Brewfile" "${root}/agent-routing.md" "${root}/install.sh" "${archive_root}/"
tar -czf "${archive}" -C "${work}/archive" agent-ready-test
HOME="${targeted_home}" PATH="${test_path}" \
	XDG_CONFIG_HOME="${targeted_home}/.config" \
	CODEX_HOME="${targeted_home}/.codex" \
	AGENT_READY_ARCHIVE_URL="file://${archive}" \
	bash -s -- codex --configure-only <"${root}/bootstrap.sh" >/dev/null
rg -q '^Tool routing:$' "${targeted_home}/.codex/AGENTS.md"
[ "$(rg -c '^<!-- agent-ready:start -->$' "${targeted_home}/.codex/AGENTS.md")" -eq 1 ]
for untouched in \
	"${targeted_home}/.claude/CLAUDE.md" \
	"${targeted_home}/.cursor/hooks.json" \
	"${targeted_home}/.gemini/GEMINI.md" \
	"${targeted_home}/.copilot/copilot-instructions.md" \
	"${targeted_home}/.codeium/windsurf/memories/global_rules.md"; do
	[ ! -e "${untouched}" ]
done
[ "$(wc -l <"${targeted_home}/rtk-calls" | tr -d ' ')" -eq 1 ]
rg -qF 'init -g --codex --no-trust-filters' "${targeted_home}/rtk-calls"

targeted_cursor_home="${work}/targeted-cursor-home"
mkdir -p "${targeted_cursor_home}"
HOME="${targeted_cursor_home}" PATH="${test_path}" \
XDG_CONFIG_HOME="${targeted_cursor_home}/.config" \
	"${root}/bootstrap.sh" cursor --configure-only >/dev/null
rg -qF 'init -g --agent cursor --hook-only --no-patch --no-trust-filters' \
	"${targeted_cursor_home}/rtk-calls"
[ ! -e "${targeted_cursor_home}/.claude" ]
jq -e '([.hooks.sessionStart[] | select(.command == "cat ./hooks/agent-ready-session-start.json")] | length) == 1' \
	"${targeted_cursor_home}/.cursor/hooks.json" >/dev/null

language_home="${work}/language-home"
mkdir -p "${language_home}/.cursor"
printf '{"keep":true,"mcpServers":{"existing":{"command":"existing"}}}\n' \
	>"${language_home}/.cursor/mcp.json"
HOME="${language_home}" PATH="${test_path}" \
	XDG_CONFIG_HOME="${language_home}/.config" \
	CLAUDE_CONFIG_DIR="${language_home}/.claude" \
	CODEX_HOME="${language_home}/.codex" \
	COPILOT_HOME="${language_home}/.copilot" \
	"${root}/bootstrap.sh" language go --configure-only >/dev/null
[ -f "${language_home}/.config/agent-ready/languages/go" ]
for target in \
	"${language_home}/.claude/CLAUDE.md" \
	"${language_home}/.codex/AGENTS.md" \
	"${language_home}/.gemini/GEMINI.md" \
	"${language_home}/.copilot/copilot-instructions.md" \
	"${language_home}/.codeium/windsurf/memories/global_rules.md"; do
	rg -qF 'use gopls where compiler semantics matter' "${target}"
done
jq -e '.keep and .mcpServers.existing.command == "existing"
	and .mcpServers.gopls.command == "gopls" and .mcpServers.gopls.args == ["mcp"]' \
	"${language_home}/.cursor/mcp.json" >/dev/null

HOME="${language_home}" PATH="${test_path}" \
	XDG_CONFIG_HOME="${language_home}/.config" \
	"${root}/languages/go/install.sh" --agent cursor >/dev/null
HOME="${language_home}" PATH="${test_path}" \
	XDG_CONFIG_HOME="${language_home}/.config" \
	"${root}/languages/go/install.sh" --agent cursor --upgrade >/dev/null
rg -qF "bundle --no-upgrade --file ${root}/languages/go/Brewfile" "${language_home}/brew-calls"
rg -qF "bundle --file ${root}/languages/go/Brewfile" "${language_home}/brew-calls"

invalid_cursor_home="${work}/invalid-cursor-home"
mkdir -p "${invalid_cursor_home}/.cursor"
printf '{broken\n' >"${invalid_cursor_home}/.cursor/mcp.json"
cp "${invalid_cursor_home}/.cursor/mcp.json" "${work}/invalid-cursor-before"
if HOME="${invalid_cursor_home}" PATH="${test_path}" \
	XDG_CONFIG_HOME="${invalid_cursor_home}/.config" \
	"${root}/languages/go/install.sh" --agent cursor --configure-only >/dev/null 2>&1; then
	printf 'invalid Cursor MCP config unexpectedly succeeded\n' >&2
	exit 1
fi
cmp -s "${work}/invalid-cursor-before" "${invalid_cursor_home}/.cursor/mcp.json"

targeted_language_home="${work}/targeted-language-home"
mkdir -p "${targeted_language_home}"
HOME="${targeted_language_home}" PATH="${test_path}" \
	XDG_CONFIG_HOME="${targeted_language_home}/.config" \
	CODEX_HOME="${targeted_language_home}/.codex" \
	"${root}/bootstrap.sh" language go --agent codex --configure-only >/dev/null
rg -qF 'use gopls where compiler semantics matter' "${targeted_language_home}/.codex/AGENTS.md"
[ ! -e "${targeted_language_home}/.claude/CLAUDE.md" ]
[ ! -e "${targeted_language_home}/.cursor/hooks.json" ]

if "${root}/bootstrap.sh" language unknown --configure-only >/dev/null 2>&1; then
	printf 'unknown language unexpectedly succeeded\n' >&2
	exit 1
fi

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
if HOME="${malformed_home}" PATH="${malformed_bin}:${PATH}" \
	XDG_CONFIG_HOME="${malformed_home}/.config" \
	CLAUDE_CONFIG_DIR="${malformed_home}/.claude" \
	"${root}/install.sh" --configure-only >/dev/null 2>&1; then
	printf 'malformed markers unexpectedly succeeded\n' >&2
	exit 1
fi
cmp -s "${work}/before" "${malformed_home}/.claude/CLAUDE.md"

printf 'installer routing checks passed\n'
