#!/usr/bin/env bash

set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)
work=$(mktemp -d)
cleanup() { rm -rf "${work}"; }
trap cleanup EXIT

digest_stdin() {
	if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi
}
digest_of() { digest_stdin <"$1"; }
line_count() {
	if [ -f "$1" ]; then wc -l <"$1" | tr -d ' '; else printf '0'; fi
}

fake_home="${work}/home"
fake_bin="${work}/bin"
test_path="${fake_bin}:${PATH}"
mkdir -p "${fake_home}" "${fake_bin}"

for command in claude codex cursor-agent gemini copilot windsurf grok opencode qwen cline kilo crush goose; do
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
cat >"${fake_bin}/codegraph" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${HOME}/codegraph-calls"
EOF
chmod +x "${fake_bin}/codegraph"
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
	"${fake_home}/grok-home/rules" \
	"${fake_home}/qwen-home" \
	"${fake_home}/cline-data/settings/rules" \
	"${fake_home}/.config/opencode" \
	"${fake_home}/.config/kilo" \
	"${fake_home}/.config/crush" \
	"${fake_home}/.config/goose" \
	"${fake_home}/dotfiles"
printf 'user claude\n' >"${fake_home}/dotfiles/CLAUDE.md"
ln -s ../dotfiles/CLAUDE.md "${fake_home}/.claude/CLAUDE.md"
printf 'user codex\n' >"${fake_home}/.codex/AGENTS.md"
printf 'user gemini\n' >"${fake_home}/.gemini/GEMINI.md"
printf 'user copilot\n' >"${fake_home}/.copilot/copilot-instructions.md"
printf 'user grok\n' >"${fake_home}/grok-home/rules/agent-ready.md"
printf 'user opencode\n' >"${fake_home}/.config/opencode/AGENTS.md"
printf 'user qwen\n' >"${fake_home}/qwen-home/QWEN.md"
printf 'user cline\n' >"${fake_home}/cline-data/settings/rules/agent-ready.md"
printf 'user kilo\n' >"${fake_home}/.config/kilo/AGENTS.md"
printf 'user crush\n' >"${fake_home}/.config/crush/CRUSH.md"
printf 'user goose\n' >"${fake_home}/.config/goose/AGENTS.md"
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

version=$(cat "${root}/VERSION")

# Files an install run writes; every one must be byte-identical on a rerun.
install_targets=(
	"${fake_home}/.claude/CLAUDE.md"
	"${fake_home}/.codex/AGENTS.md"
	"${fake_home}/.gemini/GEMINI.md"
	"${fake_home}/.copilot/copilot-instructions.md"
	"${fake_home}/.codeium/windsurf/memories/global_rules.md"
	"${fake_home}/grok-home/rules/agent-ready.md"
	"${fake_home}/.config/opencode/AGENTS.md"
	"${fake_home}/qwen-home/QWEN.md"
	"${fake_home}/cline-data/settings/rules/agent-ready.md"
	"${fake_home}/.config/kilo/AGENTS.md"
	"${fake_home}/.config/crush/CRUSH.md"
	"${fake_home}/.config/goose/AGENTS.md"
	"${fake_home}/.cursor/AGENTS.md"
	"${fake_home}/.cursor/hooks.json"
	"${fake_home}/.cursor/hooks/agent-ready-session-start.json"
)
block_targets=("${install_targets[@]:0:12}")

block_header() {
	awk -v s='<!-- agent-ready:start -->' -v e='<!-- agent-ready:end -->' '
		$0 == s { inside = 1; next }
		$0 == e { exit }
		inside { print; exit }
	' "$1"
}
block_body() {
	awk -v s='<!-- agent-ready:start -->' -v e='<!-- agent-ready:end -->' '
		$0 == s { inside = 1; first = 1; next }
		$0 == e { exit }
		inside { if (first) first = 0; else print }
	' "$1"
}
check_headers() {
	local target
	for target in "${block_targets[@]}"; do
		[ "$(block_header "${target}")" = "<!-- agent-ready ${version} sha256:$(block_body "${target}" | digest_stdin) -->" ] || {
			printf 'block header is missing or has the wrong hash in %s\n' "${target}" >&2
			exit 1
		}
	done
}
snapshot_targets() {
	local dir="$1" target
	rm -rf "${dir}"
	mkdir -p "${dir}"
	for target in "${install_targets[@]}"; do
		cp -p "${target}" "${dir}/$(printf '%s' "${target}" | tr '/' '_')"
	done
}
compare_targets() {
	local dir="$1" target
	for target in "${install_targets[@]}"; do
		if ! cmp -s "${target}" "${dir}/$(printf '%s' "${target}" | tr '/' '_')"; then
			printf 'target changed: %s\n' "${target}" >&2
			diff -u "${dir}/$(printf '%s' "${target}" | tr '/' '_')" "${target}" >&2 || true
			exit 1
		fi
	done
}

run_install() {
	HOME="${fake_home}" \
	XDG_CONFIG_HOME="${fake_home}/.config" \
	PATH="${test_path}" \
	CLAUDE_CONFIG_DIR="${fake_home}/.claude" \
	CODEX_HOME="${fake_home}/.codex" \
	COPILOT_HOME="${fake_home}/.copilot" \
	GROK_HOME="${fake_home}/grok-home" \
	QWEN_HOME="${fake_home}/qwen-home" \
	CLINE_DATA_DIR="${fake_home}/cline-data" \
		"${root}/install.sh" --configure-only "$@" >/dev/null
}

run_tool_install() {
	HOME="${fake_home}" \
	XDG_CONFIG_HOME="${fake_home}/.config" \
	PATH="${test_path}" \
	CODEX_HOME="${fake_home}/.codex" \
		"${root}/bootstrap.sh" --agent codex "$@" >/dev/null
}

run_install
snapshot_targets "${work}/after-first-run"
run_install
compare_targets "${work}/after-first-run"

for target in \
	"${fake_home}/.claude/CLAUDE.md" \
	"${fake_home}/.codex/AGENTS.md" \
	"${fake_home}/.gemini/GEMINI.md" \
	"${fake_home}/.copilot/copilot-instructions.md" \
	"${fake_home}/.codeium/windsurf/memories/global_rules.md" \
	"${fake_home}/grok-home/rules/agent-ready.md" \
	"${fake_home}/.config/opencode/AGENTS.md" \
	"${fake_home}/qwen-home/QWEN.md" \
	"${fake_home}/cline-data/settings/rules/agent-ready.md" \
	"${fake_home}/.config/kilo/AGENTS.md" \
	"${fake_home}/.config/crush/CRUSH.md" \
	"${fake_home}/.config/goose/AGENTS.md"; do
	[ "$(rg -c '^<!-- agent-ready:start -->$' "${target}")" -eq 1 ]
	[ "$(rg -c '^<!-- agent-ready:end -->$' "${target}")" -eq 1 ]
	rg -q '^Tool routing \(use instead of defaults\):$' "${target}"
	case "${target}" in
	*/.claude/* | */.codex/* | */.gemini/* | */opencode/*)
		# `codegraph install` writes its own section into these files.
		if rg -q '^- Code graph:' "${target}"; then
			printf 'CodeGraph routing duplicated in %s\n' "${target}" >&2
			exit 1
		fi
		;;
	*)
		rg -qF 'Code graph: index of symbols, calls, imports' "${target}"
		rg -qF 'its source is current, so do not re-read it' "${target}"
		rg -qF 'never `codegraph init` unasked' "${target}"
		;;
	esac
	if rg -q '^- Go:' "${target}"; then
		printf 'generic install unexpectedly included Go routing in %s\n' "${target}" >&2
		exit 1
	fi
done
check_headers

# The shared block is sent with every prompt; keep the CodeGraph line terse.
graph_line=$(rg '^- Code graph:' "${fake_home}/.copilot/copilot-instructions.md")
[ "${#graph_line}" -le 400 ] || {
	printf 'CodeGraph routing line is %s characters; keep it under 400\n' "${#graph_line}" >&2
	exit 1
}
# rtk renamed `proxy` to `bypass`, and sd treats its pattern as a regex unless -F.
rg -qF '`rtk bypass <cmd>`' "${fake_home}/.codex/AGENTS.md"
rg -qF '`sd -F ' "${fake_home}/.codex/AGENTS.md"
if rg -qF 'rtk proxy' "${fake_home}/.codex/AGENTS.md"; then
	printf 'routing still names the deprecated rtk proxy\n' >&2
	exit 1
fi

rg -q '^user claude$' "${fake_home}/.claude/CLAUDE.md"
[ -L "${fake_home}/.claude/CLAUDE.md" ]
rg -q '^user codex$' "${fake_home}/.codex/AGENTS.md"
rg -q '^user gemini$' "${fake_home}/.gemini/GEMINI.md"
rg -q '^user copilot$' "${fake_home}/.copilot/copilot-instructions.md"
rg -q '^user grok$' "${fake_home}/grok-home/rules/agent-ready.md"
rg -q '^user opencode$' "${fake_home}/.config/opencode/AGENTS.md"
rg -q '^user qwen$' "${fake_home}/qwen-home/QWEN.md"
rg -q '^user cline$' "${fake_home}/cline-data/settings/rules/agent-ready.md"
rg -q '^user kilo$' "${fake_home}/.config/kilo/AGENTS.md"
rg -q '^user crush$' "${fake_home}/.config/crush/CRUSH.md"
rg -q '^user goose$' "${fake_home}/.config/goose/AGENTS.md"
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
jq -e '.additional_context | contains("Tool routing (use instead of defaults):") and contains("Code graph:")' \
	"${fake_home}/.cursor/hooks/agent-ready-session-start.json" >/dev/null
rg -qF 'install --yes --target=auto --location=global --no-permissions' "${fake_home}/codegraph-calls"
rg -qx 'telemetry off' "${fake_home}/codegraph-calls"

mkdir -p "${fake_home}/.config/agent-ready/languages"
printf 'enabled\n' >"${fake_home}/.config/agent-ready/languages/go"
run_install
for target in \
	"${fake_home}/.claude/CLAUDE.md" \
	"${fake_home}/.codex/AGENTS.md" \
	"${fake_home}/.gemini/GEMINI.md" \
	"${fake_home}/.copilot/copilot-instructions.md" \
	"${fake_home}/.codeium/windsurf/memories/global_rules.md" \
	"${fake_home}/grok-home/rules/agent-ready.md" \
	"${fake_home}/.config/opencode/AGENTS.md" \
	"${fake_home}/qwen-home/QWEN.md" \
	"${fake_home}/cline-data/settings/rules/agent-ready.md" \
	"${fake_home}/.config/kilo/AGENTS.md" \
	"${fake_home}/.config/crush/CRUSH.md" \
	"${fake_home}/.config/goose/AGENTS.md"; do
	[ "$(rg -c '^- Go:' "${target}")" -eq 1 ]
	rg -qF 'use gopls where compiler semantics matter' "${target}"
done
jq -e '.additional_context | contains("use gopls where compiler semantics matter")' \
	"${fake_home}/.cursor/hooks/agent-ready-session-start.json" >/dev/null
check_headers

# A dry run of an already configured machine reports that nothing would change.
dry_repeat=$(HOME="${fake_home}" XDG_CONFIG_HOME="${fake_home}/.config" PATH="${test_path}" \
	CLAUDE_CONFIG_DIR="${fake_home}/.claude" CODEX_HOME="${fake_home}/.codex" \
	COPILOT_HOME="${fake_home}/.copilot" GROK_HOME="${fake_home}/grok-home" \
	QWEN_HOME="${fake_home}/qwen-home" CLINE_DATA_DIR="${fake_home}/cline-data" \
	"${root}/install.sh" --configure-only --dry-run)
rg -q '^Codex: unchanged ' <<<"${dry_repeat}"
rg -q '^Cursor: unchanged ' <<<"${dry_repeat}"
if rg -q 'would add|would refresh|blocked' <<<"${dry_repeat}"; then
	printf 'dry run of a configured machine reported pending changes\n' >&2
	exit 1
fi

for expected in \
	'init -g --hook-only --auto-patch --no-trust-filters' \
	'init -g --codex --no-trust-filters' \
	'init -g --agent cursor --hook-only --no-patch --no-trust-filters' \
	'init -g --gemini --hook-only --auto-patch --no-trust-filters' \
	'init -g --copilot --hook-only --auto-patch --no-trust-filters' \
	'init -g --opencode --hook-only --no-patch --no-trust-filters'; do
	rg -qF "${expected}" "${fake_home}/rtk-calls"
done

# A local edit inside the block stops the run before any file or tool is touched.
snapshot_targets "${work}/before-edit"
sed 's/^- Shell:.*/- Shell: local edit that a normal run must not overwrite./' \
	"${fake_home}/.codex/AGENTS.md" >"${work}/codex-edited"
cp "${work}/codex-edited" "${fake_home}/.codex/AGENTS.md"
snapshot_targets "${work}/after-edit"
rtk_before=$(line_count "${fake_home}/rtk-calls")
codegraph_before=$(line_count "${fake_home}/codegraph-calls")
brew_before=$(line_count "${fake_home}/brew-calls")
if edit_error=$(run_install 2>&1 >/dev/null); then
	printf 'local edits inside the block unexpectedly succeeded\n' >&2
	exit 1
fi
rg -qF 'has local edits inside the agent-ready block' <<<"${edit_error}"
rg -qF "${fake_home}/.codex/AGENTS.md" <<<"${edit_error}"
compare_targets "${work}/after-edit"
[ "$(line_count "${fake_home}/rtk-calls")" -eq "${rtk_before}" ]
[ "$(line_count "${fake_home}/codegraph-calls")" -eq "${codegraph_before}" ]
[ "$(line_count "${fake_home}/brew-calls")" -eq "${brew_before}" ]

# --force is the explicit way to replace those edits.
run_install --force
rg -qF -- '- Shell: prefix commands with `rtk`' "${fake_home}/.codex/AGENTS.md"
compare_targets "${work}/before-edit"
check_headers

run_tool_install
run_tool_install --upgrade
rg -qF "bundle --no-upgrade --file ${root}/Brewfile" "${fake_home}/brew-calls"
rg -qF "bundle --file ${root}/Brewfile" "${fake_home}/brew-calls"
if run_tool_install --configure-only --upgrade >/dev/null 2>&1; then
	printf 'conflicting install options unexpectedly succeeded\n' >&2
	exit 1
fi

# A checkout bootstrap only runs the installer; the local command comes from a
# verified release.
[ ! -e "${fake_home}/.local/share/agent-ready/versions" ]
[ ! -e "${fake_home}/.local/bin/agent-ready" ]

# The receipt records what this run configured so a later update can repeat it.
receipt="${fake_home}/.config/agent-ready/receipt"
rg -qx 'schema=1' "${receipt}"
rg -qx "version=${version}" "${receipt}"
rg -qx 'agents=auto' "${receipt}"
rg -qx 'configured=claude,cline,codex,copilot,crush,cursor,gemini,goose,grok,kilo,opencode,qwen,windsurf' "${receipt}"
rg -qx 'languages=go' "${receipt}"
rg -qx 'tools=brew' "${receipt}"
rg -qx 'updated_at=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "${receipt}"

targeted_home="${work}/targeted-home"
archive_root="${work}/archive/agent-ready-test"
archive="${work}/agent-ready-test.tar.gz"
mkdir -p "${targeted_home}" "${archive_root}/lib"
cp "${root}/Brewfile" "${root}/agent-routing.md" "${root}/install.sh" "${root}/VERSION" \
	"${root}/agent-ready" "${archive_root}/"
cp "${root}/lib/receipt.sh" "${archive_root}/lib/"
tar -czf "${archive}" -C "${work}/archive" agent-ready-test
HOME="${targeted_home}" PATH="${test_path}" \
	XDG_CONFIG_HOME="${targeted_home}/.config" \
	CODEX_HOME="${targeted_home}/.codex" \
	AGENT_READY_ARCHIVE_URL="file://${archive}" \
	bash -s -- codex --configure-only <"${root}/bootstrap.sh" >/dev/null
rg -q '^Tool routing \(use instead of defaults\):$' "${targeted_home}/.codex/AGENTS.md"
[ "$(rg -c '^<!-- agent-ready:start -->$' "${targeted_home}/.codex/AGENTS.md")" -eq 1 ]
for untouched in \
	"${targeted_home}/.claude/CLAUDE.md" \
	"${targeted_home}/.cursor/hooks.json" \
	"${targeted_home}/.gemini/GEMINI.md" \
	"${targeted_home}/.copilot/copilot-instructions.md" \
	"${targeted_home}/.codeium/windsurf/memories/global_rules.md" \
	"${targeted_home}/.grok/rules/agent-ready.md" \
	"${targeted_home}/.config/opencode/AGENTS.md" \
	"${targeted_home}/.qwen/QWEN.md" \
	"${targeted_home}/.cline/data/settings/rules/agent-ready.md" \
	"${targeted_home}/.config/kilo/AGENTS.md" \
	"${targeted_home}/.config/crush/CRUSH.md" \
	"${targeted_home}/.config/goose/AGENTS.md"; do
	[ ! -e "${untouched}" ]
done
[ "$(wc -l <"${targeted_home}/rtk-calls" | tr -d ' ')" -eq 1 ]
rg -qF 'init -g --codex --no-trust-filters' "${targeted_home}/rtk-calls"
rg -qF 'install --yes --target=codex --location=global --no-permissions' "${targeted_home}/codegraph-calls"

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
rg -qF 'install --yes --target=cursor --location=global --no-permissions' "${targeted_cursor_home}/codegraph-calls"

targeted_opencode_home="${work}/targeted-opencode-home"
mkdir -p "${targeted_opencode_home}"
HOME="${targeted_opencode_home}" PATH="${test_path}" \
XDG_CONFIG_HOME="${targeted_opencode_home}/.config" \
	"${root}/bootstrap.sh" open-code --configure-only >/dev/null
# Without --hook-only, `rtk init --opencode` also writes Claude Code's RTK.md.
rg -qF 'init -g --opencode --hook-only --no-patch --no-trust-filters' "${targeted_opencode_home}/rtk-calls"
rg -q '^Tool routing \(use instead of defaults\):$' "${targeted_opencode_home}/.config/opencode/AGENTS.md"
rg -qF 'install --yes --target=opencode --location=global --no-permissions' "${targeted_opencode_home}/codegraph-calls"
[ ! -e "${targeted_opencode_home}/.codex" ]

targeted_windsurf_home="${work}/targeted-windsurf-home"
mkdir -p "${targeted_windsurf_home}"
HOME="${targeted_windsurf_home}" PATH="${test_path}" \
	XDG_CONFIG_HOME="${targeted_windsurf_home}/.config" \
	"${root}/bootstrap.sh" windsurf --configure-only >"${work}/windsurf.out" 2>&1
rg -qF 'MCP setup is not available for windsurf' "${work}/windsurf.out"
if rg -q '^install ' "${targeted_windsurf_home}/codegraph-calls"; then
	printf 'unsupported CodeGraph target was wired anyway\n' >&2
	exit 1
fi
rg -qx 'telemetry off' "${targeted_windsurf_home}/codegraph-calls"
rg -qF 'Code graph: index of symbols, calls, imports' "${targeted_windsurf_home}/.codeium/windsurf/memories/global_rules.md"

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
	"${language_home}/.codeium/windsurf/memories/global_rules.md" \
	"${language_home}/.grok/rules/agent-ready.md" \
	"${language_home}/.config/opencode/AGENTS.md" \
	"${language_home}/.qwen/QWEN.md" \
	"${language_home}/.cline/data/settings/rules/agent-ready.md" \
	"${language_home}/.config/kilo/AGENTS.md" \
	"${language_home}/.config/crush/CRUSH.md" \
	"${language_home}/.config/goose/AGENTS.md"; do
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

# Without CodeGraph on PATH nothing else describes it, so the line stays.
no_graph_home="${work}/no-graph-home"
no_graph_bin="${work}/no-graph-bin"
mkdir -p "${no_graph_home}" "${no_graph_bin}"
cp "${fake_bin}/claude" "${fake_bin}/rtk" "${no_graph_bin}/"
no_graph_path="${no_graph_bin}"
while IFS= read -r dir; do
	[ -x "${dir}/codegraph" ] || no_graph_path="${no_graph_path}:${dir}"
done <<EOF
$(printf '%s\n' "${PATH}" | tr ':' '\n')
EOF
HOME="${no_graph_home}" PATH="${no_graph_path}" \
	XDG_CONFIG_HOME="${no_graph_home}/.config" \
	"${root}/install.sh" --agent claude --configure-only >/dev/null
rg -qF 'Code graph: index of symbols, calls, imports' "${no_graph_home}/.claude/CLAUDE.md"

malformed_home="${work}/malformed-home"
malformed_bin="${work}/malformed-bin"
mkdir -p "${malformed_home}/.claude" "${malformed_bin}"
cp "${fake_bin}/claude" "${fake_bin}/rtk" "${fake_bin}/codegraph" "${malformed_bin}/"
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

# Cursor is preflighted through hooks.json and its legacy AGENTS.md block.
bad_hooks_home="${work}/bad-hooks-home"
mkdir -p "${bad_hooks_home}/.cursor"
printf '{broken\n' >"${bad_hooks_home}/.cursor/hooks.json"
cp "${bad_hooks_home}/.cursor/hooks.json" "${work}/bad-hooks-before"
if HOME="${bad_hooks_home}" XDG_CONFIG_HOME="${bad_hooks_home}/.config" PATH="${test_path}" \
	"${root}/install.sh" --agent cursor --configure-only >"${work}/bad-hooks.out" 2>&1; then
	printf 'an invalid hooks.json unexpectedly succeeded\n' >&2
	exit 1
fi
rg -qF 'hooks.json must be a JSON object' "${work}/bad-hooks.out"
cmp -s "${work}/bad-hooks-before" "${bad_hooks_home}/.cursor/hooks.json"
[ ! -e "${bad_hooks_home}/.cursor/hooks/agent-ready-session-start.json" ]
[ ! -e "${bad_hooks_home}/rtk-calls" ]
[ ! -e "${bad_hooks_home}/.config/agent-ready/receipt" ]

bad_legacy_home="${work}/bad-legacy-home"
mkdir -p "${bad_legacy_home}/.cursor"
printf 'user cursor\n<!-- agent-ready:start -->\nbroken\n' >"${bad_legacy_home}/.cursor/AGENTS.md"
cp "${bad_legacy_home}/.cursor/AGENTS.md" "${work}/bad-legacy-before"
if HOME="${bad_legacy_home}" XDG_CONFIG_HOME="${bad_legacy_home}/.config" PATH="${test_path}" \
	"${root}/install.sh" --agent cursor --configure-only >"${work}/bad-legacy.out" 2>&1; then
	printf 'malformed legacy Cursor markers unexpectedly succeeded\n' >&2
	exit 1
fi
rg -qF 'malformed agent-ready markers in ' "${work}/bad-legacy.out"
rg -qF "${bad_legacy_home}/.cursor/AGENTS.md" "${work}/bad-legacy.out"
cmp -s "${work}/bad-legacy-before" "${bad_legacy_home}/.cursor/AGENTS.md"
[ ! -e "${bad_legacy_home}/.cursor/hooks.json" ]
[ ! -e "${bad_legacy_home}/rtk-calls" ]

# A block written before version headers is managed: it is refreshed and gains
# the header instead of being mistaken for a user edit.
legacy_home="${work}/legacy-home"
mkdir -p "${legacy_home}/.codex"
cat >"${legacy_home}/.codex/AGENTS.md" <<'EOF'
user codex
<!-- agent-ready:start -->
old routing written by v1.2.0
<!-- agent-ready:end -->
EOF
HOME="${legacy_home}" XDG_CONFIG_HOME="${legacy_home}/.config" \
	CODEX_HOME="${legacy_home}/.codex" PATH="${test_path}" \
	"${root}/install.sh" --agent codex --configure-only >/dev/null
rg -q '^user codex$' "${legacy_home}/.codex/AGENTS.md"
if rg -qF 'old routing written by v1.2.0' "${legacy_home}/.codex/AGENTS.md"; then
	printf 'legacy block was not refreshed\n' >&2
	exit 1
fi
[ "$(block_header "${legacy_home}/.codex/AGENTS.md")" = \
	"<!-- agent-ready ${version} sha256:$(block_body "${legacy_home}/.codex/AGENTS.md" | digest_stdin) -->" ]

# A routing file without a trailing newline must still hash and write the same
# normalized body, or the next run would report false local edits.
truncated_tree="${work}/truncated-tree"
truncated_home="${work}/truncated-home"
mkdir -p "${truncated_tree}" "${truncated_home}"
cp -R "${root}/." "${truncated_tree}/"
routing_size=$(wc -c <"${truncated_tree}/agent-routing.md" | tr -d ' ')
head -c "$((routing_size - 1))" "${truncated_tree}/agent-routing.md" >"${truncated_tree}/agent-routing.tmp"
mv "${truncated_tree}/agent-routing.tmp" "${truncated_tree}/agent-routing.md"
HOME="${truncated_home}" XDG_CONFIG_HOME="${truncated_home}/.config" PATH="${test_path}" \
	"${truncated_tree}/install.sh" --agent goose --configure-only >/dev/null 2>"${work}/truncated.err"
cp "${truncated_home}/.config/goose/AGENTS.md" "${work}/truncated-first"
HOME="${truncated_home}" XDG_CONFIG_HOME="${truncated_home}/.config" PATH="${test_path}" \
	"${truncated_tree}/install.sh" --agent goose --configure-only >/dev/null 2>"${work}/truncated.err"
cmp -s "${work}/truncated-first" "${truncated_home}/.config/goose/AGENTS.md"
rg -q '^<!-- agent-ready:end -->$' "${truncated_home}/.config/goose/AGENTS.md"

# A malformed file for a late agent stops the run before earlier agents, tools,
# or the receipt are written.
late_home="${work}/late-home"
mkdir -p "${late_home}/.codex" "${late_home}/.config/goose"
printf 'user codex\n' >"${late_home}/.codex/AGENTS.md"
cat >"${late_home}/.config/goose/AGENTS.md" <<'EOF'
user goose
<!-- agent-ready:start -->
broken goose block
EOF
codex_before=$(digest_of "${late_home}/.codex/AGENTS.md")
if HOME="${late_home}" XDG_CONFIG_HOME="${late_home}/.config" PATH="${test_path}" \
	CODEX_HOME="${late_home}/.codex" \
	"${root}/install.sh" --configure-only >"${work}/late.out" 2>&1; then
	printf 'malformed markers for a late agent unexpectedly succeeded\n' >&2
	exit 1
fi
rg -qF 'malformed agent-ready markers' "${work}/late.out"
[ "$(digest_of "${late_home}/.codex/AGENTS.md")" = "${codex_before}" ]
[ ! -e "${late_home}/.claude/CLAUDE.md" ]
[ ! -e "${late_home}/.gemini/GEMINI.md" ]
[ ! -e "${late_home}/.cursor/hooks.json" ]
[ ! -e "${late_home}/rtk-calls" ]
[ ! -e "${late_home}/codegraph-calls" ]
[ ! -e "${late_home}/brew-calls" ]
[ ! -e "${late_home}/.config/agent-ready/receipt" ]

# --dry-run reports the plan and writes nothing at all.
dry_home="${work}/dry-home"
mkdir -p "${dry_home}"
dry_out=$(HOME="${dry_home}" XDG_CONFIG_HOME="${dry_home}/.config" PATH="${test_path}" \
	CODEX_HOME="${dry_home}/.codex" CLAUDE_CONFIG_DIR="${dry_home}/.claude" \
	"${root}/install.sh" --dry-run)
rg -q '^Claude Code: would add ' <<<"${dry_out}"
rg -q '^Codex: would add ' <<<"${dry_out}"
rg -q '^Cursor: would add ' <<<"${dry_out}"
[ -z "$(ls -A "${dry_home}")" ]
if HOME="${dry_home}" PATH="${test_path}" XDG_CONFIG_HOME="${dry_home}/.config" \
	"${root}/install.sh" --dry-run --upgrade >/dev/null 2>&1; then
	printf -- '--dry-run --upgrade unexpectedly succeeded\n' >&2
	exit 1
fi
if HOME="${dry_home}" PATH="${test_path}" XDG_CONFIG_HOME="${dry_home}/.config" \
	"${root}/install.sh" --dry-run --binaries >/dev/null 2>&1; then
	printf -- '--dry-run --binaries unexpectedly succeeded\n' >&2
	exit 1
fi

# Explicit agents accumulate in the receipt instead of replacing each other.
explicit_home="${work}/explicit-home"
mkdir -p "${explicit_home}"
for explicit_agent in codex claude; do
	HOME="${explicit_home}" XDG_CONFIG_HOME="${explicit_home}/.config" PATH="${test_path}" \
		CODEX_HOME="${explicit_home}/.codex" CLAUDE_CONFIG_DIR="${explicit_home}/.claude" \
		"${root}/install.sh" --agent "${explicit_agent}" --configure-only >/dev/null
done
explicit_receipt="${explicit_home}/.config/agent-ready/receipt"
rg -qx 'agents=claude,codex' "${explicit_receipt}"
rg -qx 'configured=claude,codex' "${explicit_receipt}"
rg -qx 'tools=none' "${explicit_receipt}"
rg -qx 'languages=' "${explicit_receipt}"

# --configure-only keeps the tool path the machine was installed with.
tools_home="${work}/tools-home"
mkdir -p "${tools_home}"
HOME="${tools_home}" XDG_CONFIG_HOME="${tools_home}/.config" PATH="${test_path}" \
	CODEX_HOME="${tools_home}/.codex" \
	"${root}/install.sh" --agent codex >/dev/null
rg -qx 'tools=brew' "${tools_home}/.config/agent-ready/receipt"
HOME="${tools_home}" XDG_CONFIG_HOME="${tools_home}/.config" PATH="${test_path}" \
	CODEX_HOME="${tools_home}/.codex" \
	"${root}/install.sh" --agent codex --configure-only >/dev/null
rg -qx 'tools=brew' "${tools_home}/.config/agent-ready/receipt"
rg -qx 'agents=codex' "${tools_home}/.config/agent-ready/receipt"

# An empty configured list is valid and is merged with this run.
empty_configured_home="${work}/empty-configured-home"
mkdir -p "${empty_configured_home}/.config/agent-ready"
printf 'schema=1\nversion=%s\nagents=codex\nconfigured=\nlanguages=\ntools=brew\nupdated_at=2024-01-01T00:00:00Z\n' \
	"${version}" >"${empty_configured_home}/.config/agent-ready/receipt"
HOME="${empty_configured_home}" XDG_CONFIG_HOME="${empty_configured_home}/.config" PATH="${test_path}" \
	CODEX_HOME="${empty_configured_home}/.codex" \
	"${root}/install.sh" --agent codex --configure-only >/dev/null
rg -qx 'configured=codex' "${empty_configured_home}/.config/agent-ready/receipt"
rg -qx 'tools=brew' "${empty_configured_home}/.config/agent-ready/receipt"

# A receipt with an unknown key fails closed before anything is written.
bad_receipt_home="${work}/bad-receipt-home"
mkdir -p "${bad_receipt_home}/.codex" "${bad_receipt_home}/.config/agent-ready"
printf 'user codex\n' >"${bad_receipt_home}/.codex/AGENTS.md"
cat >"${bad_receipt_home}/.config/agent-ready/receipt" <<'EOF'
schema=1
version=v1.2.1
agents=auto
configured=codex
languages=
tools=none
unexpected=1
updated_at=2024-01-01T00:00:00Z
EOF
cp "${bad_receipt_home}/.codex/AGENTS.md" "${work}/bad-receipt-codex"
cp "${bad_receipt_home}/.config/agent-ready/receipt" "${work}/bad-receipt-before"
if HOME="${bad_receipt_home}" XDG_CONFIG_HOME="${bad_receipt_home}/.config" PATH="${test_path}" \
	CODEX_HOME="${bad_receipt_home}/.codex" \
	"${root}/install.sh" --agent codex --configure-only >"${work}/bad-receipt.out" 2>&1; then
	printf 'a malformed receipt unexpectedly succeeded\n' >&2
	exit 1
fi
rg -qF 'malformed agent-ready receipt' "${work}/bad-receipt.out"
cmp -s "${work}/bad-receipt-before" "${bad_receipt_home}/.config/agent-ready/receipt"
cmp -s "${work}/bad-receipt-codex" "${bad_receipt_home}/.codex/AGENTS.md"
[ ! -e "${bad_receipt_home}/rtk-calls" ]

# Linux without Homebrew: release binaries from a file:// stand-in for the
# GitHub API, with every archive format the real releases use.
gh_api="${work}/github"
gh_assets="${work}/github-assets"
mkdir -p "${gh_api}" "${gh_assets}"
real_jq=$(command -v jq)
fake_binary() {
	if [ "$2" = jq ]; then
		printf '#!/bin/sh\nexec %s "$@"\n' "${real_jq}" >"$1"
	else
		# shellcheck disable=SC2016 # $* and $HOME belong to the generated script
		printf '#!/bin/sh\nprintf "%%s %%s\\n" %s "$*" >>"${HOME}/binary-calls"\n' "$2" >"$1"
	fi
	chmod +x "$1"
}
# publish <repo> <tag> <binaries> <asset>... — one release with the given assets.
publish() {
	local repo="$1" tag="$2" bins="$3" asset dir stage bin
	shift 3
	dir="${gh_assets}/${repo}/${tag}"
	mkdir -p "${dir}" "${gh_api}/repos/${repo}/releases"
	for asset in "$@"; do
		stage="${work}/stage/${asset}"
		rm -rf "${stage}"
		mkdir -p "${stage}/pkg"
		for bin in ${bins//,/ }; do fake_binary "${stage}/pkg/${bin}" "${bin}"; done
		case "${asset}" in
		*.tar.gz) tar -czf "${dir}/${asset}" -C "${stage}" pkg ;;
		*.tar.xz) tar -cJf "${dir}/${asset}" -C "${stage}" pkg ;;
		*.zip) (cd "${stage}/pkg" && python3 -m zipfile -c "${dir}/${asset}" ./*) ;;
		*) cp "${stage}/pkg/${bins}" "${dir}/${asset}" ;;
		esac
	done
	if [ "${repo}" = jqlang/jq ]; then
		(cd "${dir}" && for asset in "$@"; do printf '%s  %s\n' "$(digest_of "${asset}")" "${asset}"; done) >"${dir}/sha256sum.txt"
		set -- "$@" sha256sum.txt
	fi
	for asset in "$@"; do
		jq -n --arg name "${asset}" --arg digest "sha256:$(digest_of "${dir}/${asset}")" \
			--arg url "file://${dir}/${asset}" '{name: $name, digest: $digest, browser_download_url: $url}'
	done | jq -s --arg tag "${tag}" '{tag_name: $tag, assets: .}' >"${gh_api}/repos/${repo}/releases/latest"
}
publish_all() {
	local v="$1"
	publish jqlang/jq "jq-${v}" jq jq-linux-amd64 jq-linux-arm64 jq-linux-armhf
	publish rtk-ai/rtk "v${v}" rtk rtk-x86_64-unknown-linux-musl.tar.gz rtk-aarch64-unknown-linux-gnu.tar.gz \
		rtk-oss-x86_64-unknown-linux-musl.tar.gz
	publish astral-sh/uv "${v}" uv,uvx uv-x86_64-unknown-linux-musl.tar.gz uv-aarch64-unknown-linux-musl.tar.gz \
		uv-x86_64-unknown-linux-gnu.tar.gz
	publish chmln/sd "v${v}" sd "sd-v${v}-x86_64-unknown-linux-musl.tar.gz" "sd-v${v}-aarch64-unknown-linux-musl.tar.gz"
	publish BurntSushi/ripgrep "${v}" rg "ripgrep-${v}-x86_64-unknown-linux-musl.tar.gz" \
		"ripgrep-${v}-aarch64-unknown-linux-musl.tar.gz" "ripgrep-${v}-aarch64-unknown-linux-gnu.tar.gz"
	publish ast-grep/ast-grep "${v}" ast-grep,sg app-x86_64-unknown-linux-gnu.zip app-aarch64-unknown-linux-gnu.zip
	publish cli/cli "v${v}" gh "gh_${v}_linux_amd64.tar.gz" "gh_${v}_linux_arm64.tar.gz"
	publish max-sixty/worktrunk "v${v}" wt,git-wt worktrunk-x86_64-unknown-linux-musl.tar.xz \
		worktrunk-aarch64-unknown-linux-musl.tar.xz
	publish gitleaks/gitleaks "v${v}" gitleaks "gitleaks_${v}_linux_x64.tar.gz" "gitleaks_${v}_linux_arm64.tar.gz"
	publish rhysd/actionlint "v${v}" actionlint "actionlint_${v}_linux_amd64.tar.gz" "actionlint_${v}_linux_arm64.tar.gz"
	publish koalaman/shellcheck "v${v}" shellcheck "shellcheck-v${v}.linux.x86_64.tar.gz" "shellcheck-v${v}.linux.aarch64.tar.gz"
	publish Wilfred/difftastic "${v}" difft "difft-${v}-x86_64-unknown-linux-musl.tar.gz" \
		"difft-${v}-aarch64-unknown-linux-gnu.tar.gz"
	publish mikefarah/yq "v${v}" yq yq_linux_amd64 yq_linux_arm64
	publish yshavit/mdq "v${v}" mdq mdq-linux-x64-musl.tar.gz mdq-linux-x64.tar.gz
	publish sharkdp/hyperfine "v${v}" hyperfine "hyperfine-v${v}-x86_64-unknown-linux-musl.tar.gz" \
		"hyperfine-v${v}-aarch64-unknown-linux-musl.tar.gz"
}
# publish_codegraph <tag> — one release with the four platform bundles, each a
# codegraph-<os>-<arch>/bin/codegraph exactly like the upstream archive.
publish_codegraph() {
	local tag="$1" targets target name stage dir
	targets="darwin-x64 darwin-arm64 linux-x64 linux-arm64"
	stage="${work}/codegraph-stage/${tag}"
	dir="${gh_assets}/colbymchenry/codegraph/${tag}"
	rm -rf "${stage}"
	mkdir -p "${stage}" "${dir}" "${gh_api}/repos/colbymchenry/codegraph/releases"
	for target in ${targets}; do
		name="codegraph-${target}"
		mkdir -p "${stage}/${name}/bin"
		cat >"${stage}/${name}/bin/codegraph" <<EOF
#!/bin/sh
printf '%s %s\n' "${tag}" "\$*" >>"\${HOME}/codegraph-calls"
EOF
		chmod +x "${stage}/${name}/bin/codegraph"
		tar -czf "${dir}/${name}.tar.gz" -C "${stage}" "${name}"
	done
	for target in ${targets}; do
		name="codegraph-${target}.tar.gz"
		jq -n --arg name "${name}" --arg digest "sha256:$(digest_of "${dir}/${name}")" \
			--arg url "file://${dir}/${name}" '{name: $name, digest: $digest, browser_download_url: $url}'
	done | jq -s --arg tag "${tag}" '{tag_name: $tag, assets: .}' >"${gh_api}/repos/colbymchenry/codegraph/releases/latest"
}
# publish_agent_ready <tag> [version] — the release archive the release-asset
# workflow attaches, built from this working tree with the tag's VERSION. The
# archive therefore holds the real installer and the real agent-ready command.
publish_agent_ready() {
	local tag="$1" version="${2:-$1}" name dir stage
	name="agent-ready-${tag}"
	dir="${gh_assets}/Dankosik/agent-ready/${tag}"
	stage="${work}/agent-ready-stage/${tag}"
	rm -rf "${stage}"
	mkdir -p "${stage}/${name}" "${dir}" "${gh_api}/repos/Dankosik/agent-ready/releases/tags"
	cp -R "${root}/." "${stage}/${name}/"
	rm -rf "${stage}/${name}/.git" "${stage}/${name}/.codegraph"
	printf '%s\n' "${version}" >"${stage}/${name}/VERSION"
	tar -czf "${dir}/${name}.tar.gz" -C "${stage}" "${name}"
	jq -n --arg name "${name}.tar.gz" --arg digest "sha256:$(digest_of "${dir}/${name}.tar.gz")" \
		--arg url "file://${dir}/${name}.tar.gz" '{name: $name, digest: $digest, browser_download_url: $url}' |
		jq -s --arg tag "${tag}" '{tag_name: $tag, assets: .}' \
			>"${gh_api}/repos/Dankosik/agent-ready/releases/tags/${tag}"
}
publish_all 1.0.0
publish_codegraph v9.9.9

# A PATH with the base system tools but no jq, so the jq bootstrap runs too.
base_bin="${work}/base-bin"
mkdir -p "${base_bin}"
for command in bash sh env curl tar gzip xz unzip python3 sha256sum shasum awk sed grep find \
	mktemp cp chmod mv rm mkdir ln cut head uname cat dirname basename tr sort readlink cmp wc date; do
	path=$(command -v "${command}" || true)
	[ -z "${path}" ] || ln -s "${path}" "${base_bin}/${command}"
done
# curl drops the query string of a file:// URL, and the stand-in already has a
# releases/ directory, so the release list is served from releases.json.
rm "${base_bin}/curl"
cat >"${base_bin}/curl" <<EOF
#!/usr/bin/env bash
args=()
for arg in "\$@"; do
	case "\${arg}" in */releases\?per_page=30) arg="\${arg%\?per_page=30}.json" ;; esac
	args+=("\${arg}")
done
exec $(command -v curl) "\${args[@]}"
EOF
chmod +x "${base_bin}/curl"
for command in claude codex rtk; do cp "${fake_bin}/${command}" "${base_bin}/"; done

binary_home="${work}/binary-home"
mkdir -p "${binary_home}"
run_binaries() {
	HOME="${binary_home}" PATH="${base_bin}" \
		XDG_CONFIG_HOME="${binary_home}/.config" \
		CODEX_HOME="${binary_home}/.codex" \
		AGENT_READY_OS=Linux AGENT_READY_ARCH="${arch:-x86_64}" \
		AGENT_READY_GITHUB_API="file://${gh_api}" \
		"${root}/install.sh" --agent codex "$@"
}
bins="${binary_home}/.local/bin"
state="${binary_home}/.config/agent-ready/binaries"
expected_bins="jq rtk uv uvx sd rg ast-grep gh wt git-wt gitleaks actionlint shellcheck difft yq mdq hyperfine codegraph"

run_binaries >"${work}/binaries.out"
for bin in ${expected_bins}; do
	[ -x "${bins}/${bin}" ] || { printf 'binary install did not provide %s\n' "${bin}" >&2; exit 1; }
done
[ ! -e "${bins}/sg" ] || { printf 'ast-grep installed sg, which shadows shadow-utils sg\n' >&2; exit 1; }
[ "$(wc -l <"${state}" | tr -d ' ')" -eq 15 ]
rg -qx 'ripgrep 1.0.0' "${state}"
rg -qF 'jq jq-1.0.0 installed' "${work}/binaries.out"
rg -qF 'codegraph v9.9.9 installed' "${work}/binaries.out"
[ -L "${bins}/codegraph" ]
rg -qx 'v9.9.9' "${binary_home}/.config/agent-ready/codegraph"
rg -qF 'v9.9.9 install --yes --target=codex --location=global --no-permissions' \
	"${binary_home}/codegraph-calls"
rg -qF 'init -g --codex --no-trust-filters' "${binary_home}/binary-calls"
rg -q '^Tool routing \(use instead of defaults\):$' "${binary_home}/.codex/AGENTS.md"
rg -qF 'is not on PATH' "${work}/binaries.out"

# A rerun needs no network at all.
mv "${gh_api}" "${gh_api}.offline"
run_binaries >"${work}/binaries.out"
mv "${gh_api}.offline" "${gh_api}"
[ "$(rg -c 'already installed$' "${work}/binaries.out")" -eq 16 ]

# --upgrade downloads only what changed upstream.
publish BurntSushi/ripgrep 2.0.0 rg ripgrep-2.0.0-x86_64-unknown-linux-musl.tar.gz
run_binaries --upgrade >"${work}/binaries.out"
rg -qF 'ripgrep 2.0.0 installed' "${work}/binaries.out"
rg -qF 'codegraph v9.9.9 is up to date' "${work}/binaries.out"
[ "$(rg -c 'is up to date$' "${work}/binaries.out")" -eq 15 ]
rg -qx 'ripgrep 2.0.0' "${state}"

# A latest release missing this platform's asset falls back to the newest
# stable release that has it; prereleases are skipped.
ag="${gh_api}/repos/ast-grep/ast-grep/releases"
cp "${ag}/latest" "${work}/ast-grep.json"
jq -s '[(.[0] | .tag_name = "3.0.0-rc" | .prerelease = true),
	{tag_name: "2.0.0", assets: []},
	.[0]]' "${work}/ast-grep.json" >"${ag}.json"
jq -n '{tag_name: "2.0.0", assets: []}' >"${ag}/latest"
rm "${bins}/ast-grep"
run_binaries >"${work}/binaries.out" 2>&1
rg -qF 'ast-grep: latest release 2.0.0 has no Linux x86_64 asset; using 1.0.0' "${work}/binaries.out"
rg -qF 'ast-grep 1.0.0 installed' "${work}/binaries.out"
[ -x "${bins}/ast-grep" ]
jq -n '[{tag_name: "2.0.0", assets: []}]' >"${ag}.json"
rm "${bins}/ast-grep"
if run_binaries >"${work}/binaries.out" 2>&1; then
	printf 'install without any matching release unexpectedly succeeded\n' >&2
	exit 1
fi
rg -qF 'ast-grep: no recent ast-grep/ast-grep release publishes a Linux x86_64 asset' "${work}/binaries.out"
cp "${work}/ast-grep.json" "${ag}/latest"
rm "${ag}.json"
run_binaries >/dev/null

# A digest mismatch installs nothing and fails.
jq '.assets[0].digest = "sha256:0000000000000000000000000000000000000000000000000000000000000000"' \
	"${gh_api}/repos/chmln/sd/releases/latest" >"${work}/sd.json"
cp "${work}/sd.json" "${gh_api}/repos/chmln/sd/releases/latest"
rm "${bins}/sd"
if run_binaries >"${work}/binaries.out" 2>&1; then
	printf 'checksum mismatch unexpectedly succeeded\n' >&2
	exit 1
fi
rg -qF 'sd: checksum mismatch' "${work}/binaries.out"
[ ! -e "${bins}/sd" ]
publish_all 1.0.0

# aarch64: mdq publishes no build; it is reported and skipped, nothing else is.
rm -rf "${binary_home}"
mkdir -p "${binary_home}"
arch=aarch64 run_binaries >"${work}/binaries.out" 2>&1
rg -qF 'mdq: no Linux aarch64 build is published upstream; skipped' "${work}/binaries.out"
[ ! -e "${bins}/mdq" ]
[ -x "${bins}/hyperfine" ]

# Homebrew stays the default where it exists; --binaries overrides it on Linux only.
brew_home="${work}/brew-linux-home"
mkdir -p "${brew_home}"
HOME="${brew_home}" PATH="${fake_bin}:${base_bin}" XDG_CONFIG_HOME="${brew_home}/.config" \
	CODEX_HOME="${brew_home}/.codex" AGENT_READY_OS=Linux \
	AGENT_READY_GITHUB_API="file://${gh_api}" \
	"${root}/install.sh" --agent codex >/dev/null
rg -qF "bundle --no-upgrade --file ${root}/Brewfile" "${brew_home}/brew-calls"
[ ! -e "${brew_home}/.local/bin" ]
HOME="${brew_home}" PATH="${fake_bin}:${base_bin}" XDG_CONFIG_HOME="${brew_home}/.config" \
	CODEX_HOME="${brew_home}/.codex" AGENT_READY_OS=Linux AGENT_READY_ARCH=x86_64 \
	AGENT_READY_GITHUB_API="file://${gh_api}" \
	"${root}/install.sh" --agent codex --binaries >/dev/null
[ -x "${brew_home}/.local/bin/rg" ]
[ "$(wc -l <"${brew_home}/brew-calls" | tr -d ' ')" -eq 1 ]
if HOME="${brew_home}" PATH="${test_path}" AGENT_READY_OS=Darwin \
	"${root}/install.sh" --agent codex --binaries >/dev/null 2>&1; then
	printf -- '--binaries unexpectedly succeeded on macOS\n' >&2
	exit 1
fi
if HOME="${brew_home}" PATH="${test_path}" "${root}/install.sh" --configure-only --binaries >/dev/null 2>&1; then
	printf -- '--configure-only --binaries unexpectedly succeeded\n' >&2
	exit 1
fi

# Go on Linux without Homebrew builds gopls with the user's toolchain.
go_home="${work}/go-linux-home"
go_bin="${work}/go-bin"
mkdir -p "${go_home}" "${go_bin}"
cat >"${go_bin}/go" <<'EOF'
#!/bin/sh
printf 'GOBIN=%s %s\n' "${GOBIN}" "$*" >>"${HOME}/go-calls"
mkdir -p "${GOBIN}" && cp "$(command -v gopls-fixture)" "${GOBIN}/gopls"
EOF
cp "${fake_bin}/gopls" "${go_bin}/gopls-fixture"
cp "${fake_bin}/codex" "${go_bin}/"
chmod +x "${go_bin}/go"
HOME="${go_home}" PATH="${go_bin}:${base_bin}" XDG_CONFIG_HOME="${go_home}/.config" \
	CODEX_HOME="${go_home}/.codex" AGENT_READY_OS=Linux \
	"${root}/languages/go/install.sh" --agent codex >/dev/null
rg -qxF "GOBIN=${go_home}/.local/bin install golang.org/x/tools/gopls@latest" "${go_home}/go-calls"
[ -x "${go_home}/.local/bin/gopls" ]

# CodeGraph is a self-contained bundle: versioned directory, launcher symlink,
# digest check, and no upgrade of an installation this script does not own.
cg_home="${work}/codegraph-home"
mkdir -p "${cg_home}"
cg_bins="${cg_home}/.local/bin"
cg_state="${cg_home}/.config/agent-ready/codegraph"
cg_versions="${cg_home}/.local/share/agent-ready/codegraph/versions"
run_codegraph() {
	HOME="${cg_home}" PATH="${test_path}" \
		XDG_CONFIG_HOME="${cg_home}/.config" \
		AGENT_READY_OS=Linux AGENT_READY_ARCH=x86_64 \
		AGENT_READY_GITHUB_API="file://${gh_api}" \
		"${root}/install-codegraph.sh" "$@"
}

run_codegraph >"${work}/codegraph.out"
rg -qF 'codegraph v9.9.9 installed' "${work}/codegraph.out"
[ -L "${cg_bins}/codegraph" ]
[ "$(readlink "${cg_bins}/codegraph")" = "${cg_versions}/v9.9.9/bin/codegraph" ]
rg -qx 'v9.9.9' "${cg_state}"

# A rerun needs no network at all.
mv "${gh_api}" "${gh_api}.offline"
run_codegraph >"${work}/codegraph.out"
mv "${gh_api}.offline" "${gh_api}"
rg -qF 'codegraph v9.9.9 already installed' "${work}/codegraph.out"

# --upgrade replaces the bundle and prunes the version it replaced.
publish_codegraph v9.10.0
run_codegraph --upgrade >"${work}/codegraph.out"
rg -qF 'codegraph v9.10.0 installed' "${work}/codegraph.out"
rg -qx 'v9.10.0' "${cg_state}"
[ "$(readlink "${cg_bins}/codegraph")" = "${cg_versions}/v9.10.0/bin/codegraph" ]
[ ! -e "${cg_versions}/v9.9.9" ]

# A digest mismatch installs nothing.
jq --arg name "codegraph-linux-x64.tar.gz" \
	'(.assets[] | select(.name == $name).digest) = "sha256:0000000000000000000000000000000000000000000000000000000000000000"' \
	"${gh_api}/repos/colbymchenry/codegraph/releases/latest" >"${work}/codegraph.json"
cp "${work}/codegraph.json" "${gh_api}/repos/colbymchenry/codegraph/releases/latest"
rm -f "${cg_bins}/codegraph" "${cg_state}"
if run_codegraph >"${work}/codegraph.out" 2>&1; then
	printf 'codegraph checksum mismatch unexpectedly succeeded\n' >&2
	exit 1
fi
rg -qF 'codegraph: checksum mismatch' "${work}/codegraph.out"
[ ! -e "${cg_bins}/codegraph" ]
publish_codegraph v9.10.0

# A codegraph installed by npm or upstream is left in place, not shadowed.
kept_home="${work}/codegraph-kept-home"
mkdir -p "${kept_home}/.local/bin"
printf '#!/bin/sh\nexit 0\n' >"${kept_home}/.local/bin/codegraph"
chmod +x "${kept_home}/.local/bin/codegraph"
cp "${kept_home}/.local/bin/codegraph" "${work}/codegraph-kept-before"
HOME="${kept_home}" PATH="${test_path}" XDG_CONFIG_HOME="${kept_home}/.config" \
	AGENT_READY_OS=Linux AGENT_READY_ARCH=x86_64 AGENT_READY_GITHUB_API="file://${gh_api}" \
	"${root}/install-codegraph.sh" >"${work}/codegraph.out"
rg -qF 'keeping the existing installation' "${work}/codegraph.out"
cmp -s "${work}/codegraph-kept-before" "${kept_home}/.local/bin/codegraph"

if HOME="${cg_home}" PATH="${test_path}" XDG_CONFIG_HOME="${cg_home}/.config" \
	AGENT_READY_OS=Linux AGENT_READY_ARCH=riscv64 AGENT_READY_GITHUB_API="file://${gh_api}" \
	"${root}/install-codegraph.sh" >"${work}/codegraph.out" 2>&1; then
	printf 'unsupported architecture unexpectedly succeeded\n' >&2
	exit 1
fi
rg -qF 'unsupported architecture: riscv64' "${work}/codegraph.out"

# bootstrap.sh verifies a release archive against the digest GitHub records
# before running the installer inside it. The copy sits alone in its own
# directory, so it has no checkout beside it and takes the download path.
bootstrap_copy="${work}/bootstrap-download"
mkdir -p "${bootstrap_copy}"
cp "${root}/bootstrap.sh" "${bootstrap_copy}/bootstrap.sh"
publish_agent_ready v9.9.9
run_bootstrap() {
	HOME="$1" PATH="$2" XDG_CONFIG_HOME="$1/.config" \
		XDG_DATA_HOME="$1/.local/share" \
		AGENT_READY_REF=v9.9.9 AGENT_READY_GITHUB_API="file://${gh_api}" \
		bash "${bootstrap_copy}/bootstrap.sh" codex --configure-only </dev/null
}

verified_home="${work}/verified-home"
verified_bins="${verified_home}/.local/bin"
verified_versions="${verified_home}/.local/share/agent-ready/versions"
mkdir -p "${verified_home}"
run_bootstrap "${verified_home}" "${test_path}" >"${work}/bootstrap.out"
rg -qF 'Downloading agent-ready v9.9.9' "${work}/bootstrap.out"
[ -L "${verified_bins}/agent-ready" ]
[ "$(readlink "${verified_bins}/agent-ready")" = "${verified_versions}/v9.9.9/agent-ready" ]
rg -qF "agent-ready v9.9.9 installed in ${verified_versions}/v9.9.9" "${work}/bootstrap.out"
rg -qx 'version=v9.9.9' "${verified_home}/.config/agent-ready/receipt"
rg -q '^Tool routing \(use instead of defaults\):$' "${verified_home}/.codex/AGENTS.md"

# The same release without jq, as on a fresh Linux.
no_jq_home="${work}/no-jq-bootstrap-home"
mkdir -p "${no_jq_home}"
run_bootstrap "${no_jq_home}" "${base_bin}" >"${work}/bootstrap.out"
[ -L "${no_jq_home}/.local/bin/agent-ready" ]
rg -qx 'version=v9.9.9' "${no_jq_home}/.config/agent-ready/receipt"
rg -q '^Tool routing \(use instead of defaults\):$' "${no_jq_home}/.codex/AGENTS.md"

# A digest mismatch installs nothing and creates no launcher.
wrong_digest_home="${work}/wrong-digest-home"
mkdir -p "${wrong_digest_home}"
jq '.assets[0].digest = "sha256:0000000000000000000000000000000000000000000000000000000000000000"' \
	"${gh_api}/repos/Dankosik/agent-ready/releases/tags/v9.9.9" >"${work}/agent-ready.json"
cp "${work}/agent-ready.json" "${gh_api}/repos/Dankosik/agent-ready/releases/tags/v9.9.9"
if run_bootstrap "${wrong_digest_home}" "${test_path}" >"${work}/bootstrap.out" 2>&1; then
	printf 'bootstrap checksum mismatch unexpectedly succeeded\n' >&2
	exit 1
fi
rg -qF 'checksum mismatch for agent-ready-v9.9.9.tar.gz; nothing installed' "${work}/bootstrap.out"
[ ! -e "${wrong_digest_home}/.local" ]
[ ! -e "${wrong_digest_home}/.config/agent-ready/receipt" ]

# A release without the archive is refused.
no_asset_home="${work}/no-asset-home"
mkdir -p "${no_asset_home}"
jq -n '{tag_name: "v9.9.9", assets: []}' >"${gh_api}/repos/Dankosik/agent-ready/releases/tags/v9.9.9"
if run_bootstrap "${no_asset_home}" "${test_path}" >"${work}/bootstrap.out" 2>&1; then
	printf 'bootstrap without a release archive unexpectedly succeeded\n' >&2
	exit 1
fi
rg -qF 'agent-ready v9.9.9 has no verified release archive; use a newer release' "${work}/bootstrap.out"
[ ! -e "${no_asset_home}/.local" ]

# An archive whose VERSION disagrees with the tag is refused after verification.
version_home="${work}/version-home"
mkdir -p "${version_home}"
publish_agent_ready v9.9.9 v9.9.8
if run_bootstrap "${version_home}" "${test_path}" >"${work}/bootstrap.out" 2>&1; then
	printf 'bootstrap with a mismatched VERSION unexpectedly succeeded\n' >&2
	exit 1
fi
rg -qF 'agent-ready v9.9.9: archive VERSION does not match the tag' "${work}/bootstrap.out"
[ ! -e "${version_home}/.local" ]
publish_agent_ready v9.9.9

# The local command: a verified release keeps its trees side by side and links
# only the launcher, like the CodeGraph bundle. The fake HOME has the build
# tools but none of the tools agent-ready installs, so doctor can report what is
# missing without reaching the network.
publish_agent_ready v9.9.0
publish_agent_ready v9.9.1
publish_agent_ready v9.9.2

cli_home="${work}/cli-home"
cli_bins="${work}/cli-bin"
cli_versions="${cli_home}/.local/share/agent-ready/versions"
cli_path="${cli_bins}:${base_bin}"
mkdir -p "${cli_home}" "${cli_bins}"

run_release() {
	local home="$1" bins="$2" tag="$3" path="$4"
	shift 4
	HOME="${home}" PATH="${path}" \
		XDG_CONFIG_HOME="${home}/.config" \
		XDG_DATA_HOME="${home}/.local/share" \
		AGENT_READY_BIN_DIR="${bins}" \
		CODEX_HOME="${home}/.codex" \
		AGENT_READY_REF="${tag}" AGENT_READY_GITHUB_API="file://${gh_api}" \
		bash "${bootstrap_copy}/bootstrap.sh" "$@" </dev/null
}
run_cli() {
	local home="$1" bins="$2" path="$3"
	shift 3
	HOME="${home}" PATH="${path}" \
		XDG_CONFIG_HOME="${home}/.config" \
		XDG_DATA_HOME="${home}/.local/share" \
		AGENT_READY_BIN_DIR="${bins}" \
		CODEX_HOME="${home}/.codex" \
		"${bins}/agent-ready" "$@"
}

run_release "${cli_home}" "${cli_bins}" v9.9.0 "${base_bin}" codex --configure-only \
	>"${work}/cli.out"
[ -L "${cli_bins}/agent-ready" ]
[ "$(readlink "${cli_bins}/agent-ready")" = "${cli_versions}/v9.9.0/agent-ready" ]
rg -qF "agent-ready v9.9.0 installed in ${cli_versions}/v9.9.0" "${work}/cli.out"
rg -qx 'version=v9.9.0' "${cli_home}/.config/agent-ready/receipt"
rg -q '^Tool routing \(use instead of defaults\):$' "${cli_home}/.codex/AGENTS.md"

# Rerunning the same release changes neither the tree nor the launcher.
cli_agent_before=$(digest_of "${cli_versions}/v9.9.0/agent-ready")
run_release "${cli_home}" "${cli_bins}" v9.9.0 "${base_bin}" codex --configure-only \
	>"${work}/cli.out"
rg -qF "agent-ready v9.9.0 is already in ${cli_versions}/v9.9.0" "${work}/cli.out"
[ "$(digest_of "${cli_versions}/v9.9.0/agent-ready")" = "${cli_agent_before}" ]
[ "$(readlink "${cli_bins}/agent-ready")" = "${cli_versions}/v9.9.0/agent-ready" ]
[ ! -e "${cli_versions}/v9.9.1" ]

# A newer release moves the launcher and keeps both trees.
run_release "${cli_home}" "${cli_bins}" v9.9.1 "${base_bin}" codex --configure-only \
	>"${work}/cli.out"
[ "$(readlink "${cli_bins}/agent-ready")" = "${cli_versions}/v9.9.1/agent-ready" ]
[ -d "${cli_versions}/v9.9.0" ]
[ -d "${cli_versions}/v9.9.1" ]
rg -qx 'version=v9.9.1' "${cli_home}/.config/agent-ready/receipt"

# A third release keeps the two newest and prunes the rest.
run_release "${cli_home}" "${cli_bins}" v9.9.2 "${base_bin}" codex --configure-only \
	>"${work}/cli.out"
[ "$(readlink "${cli_bins}/agent-ready")" = "${cli_versions}/v9.9.2/agent-ready" ]
[ -d "${cli_versions}/v9.9.1" ]
[ -d "${cli_versions}/v9.9.2" ]
[ ! -e "${cli_versions}/v9.9.0" ]

# status is read-only and reports the receipt, the launcher, and the drift.
run_cli "${cli_home}" "${cli_bins}" "${cli_path}" status >"${work}/status.out"
rg -qF 'agent-ready v9.9.2: ' "${work}/status.out"
rg -qF "${cli_versions}/v9.9.2/agent-ready" "${work}/status.out"
rg -qF 'receipt: ' "${work}/status.out"
rg -qF 'version=v9.9.2' "${work}/status.out"
rg -qF 'versions: v9.9.1 v9.9.2' "${work}/status.out"
rg -qF 'drift:' "${work}/status.out"
rg -q '^Codex: unchanged ' "${work}/status.out"

# doctor fails here because the tools are missing, and writes nothing.
receipt_before=$(digest_of "${cli_home}/.config/agent-ready/receipt")
agent_before=$(digest_of "${cli_home}/.codex/AGENTS.md")
rtk_before=$(line_count "${cli_home}/rtk-calls")
if run_cli "${cli_home}" "${cli_bins}" "${cli_path}" doctor >"${work}/doctor.out" 2>&1; then
	printf 'doctor passed in a HOME without the tools\n' >&2
	exit 1
fi
rg -qF 'ok: launcher ' "${work}/doctor.out"
rg -qF 'ok: receipt ' "${work}/doctor.out"
rg -qF "ok: ${cli_bins} is on PATH" "${work}/doctor.out"
rg -qF 'problem: rg is not on PATH' "${work}/doctor.out"
rg -qF 'problem: codegraph is not on PATH' "${work}/doctor.out"
rg -qF 'warn: mdq is not on PATH' "${work}/doctor.out"
rg -qF 'ok: install.sh --dry-run reports nothing blocked' "${work}/doctor.out"
[ "$(digest_of "${cli_home}/.config/agent-ready/receipt")" = "${receipt_before}" ]
[ "$(digest_of "${cli_home}/.codex/AGENTS.md")" = "${agent_before}" ]
[ "$(line_count "${cli_home}/rtk-calls")" -eq "${rtk_before}" ]

# An unknown command prints the usage and exits 2.
unknown_status=0
run_cli "${cli_home}" "${cli_bins}" "${cli_path}" frobnicate >"${work}/usage.out" 2>&1 ||
	unknown_status=$?
[ "${unknown_status}" -eq 2 ]
rg -qF 'usage: ' "${work}/usage.out"

# --agent takes a comma list, configures every named agent and no other one, and
# records the whole list as one entry.
multi_home="${work}/multi-home"
mkdir -p "${multi_home}"
HOME="${multi_home}" PATH="${test_path}" XDG_CONFIG_HOME="${multi_home}/.config" \
	"${root}/install.sh" --agent claude,codex --configure-only >/dev/null
rg -q '^Tool routing \(use instead of defaults\):$' "${multi_home}/.claude/CLAUDE.md"
rg -q '^Tool routing \(use instead of defaults\):$' "${multi_home}/.codex/AGENTS.md"
rg -qx 'agents=claude,codex' "${multi_home}/.config/agent-ready/receipt"
rg -qx 'configured=claude,codex' "${multi_home}/.config/agent-ready/receipt"
rg -qxF 'install --yes --target=claude,codex --location=global --no-permissions' \
	"${multi_home}/codegraph-calls"
[ "$(line_count "${multi_home}/rtk-calls")" -eq 2 ]
for untouched in \
	"${multi_home}/.gemini/GEMINI.md" \
	"${multi_home}/.copilot/copilot-instructions.md" \
	"${multi_home}/.codeium/windsurf/memories/global_rules.md" \
	"${multi_home}/.grok/rules/agent-ready.md" \
	"${multi_home}/.config/opencode/AGENTS.md" \
	"${multi_home}/.qwen/QWEN.md" \
	"${multi_home}/.cline/data/settings/rules/agent-ready.md" \
	"${multi_home}/.config/kilo/AGENTS.md" \
	"${multi_home}/.config/crush/CRUSH.md" \
	"${multi_home}/.config/goose/AGENTS.md" \
	"${multi_home}/.cursor/hooks.json"; do
	[ ! -e "${untouched}" ]
done

# Aliases in a list resolve per item, CodeGraph gets the mapped targets, and an
# unsupported agent is reported without blocking the others.
alias_home="${work}/alias-home"
mkdir -p "${alias_home}"
HOME="${alias_home}" PATH="${test_path}" XDG_CONFIG_HOME="${alias_home}/.config" \
	"${root}/install.sh" --agent claude-code,github-copilot,windsurf --configure-only \
	>"${work}/alias.out" 2>&1
rg -qx 'agents=claude,copilot,windsurf' "${alias_home}/.config/agent-ready/receipt"
rg -qxF 'install --yes --target=claude,copilot-cli --location=global --no-permissions' \
	"${alias_home}/codegraph-calls"
rg -qF 'MCP setup is not available for windsurf' "${work}/alias.out"
rg -q '^Tool routing \(use instead of defaults\):$' "${alias_home}/.claude/CLAUDE.md"
rg -q '^Tool routing \(use instead of defaults\):$' "${alias_home}/.copilot/copilot-instructions.md"
rg -q '^Tool routing \(use instead of defaults\):$' "${alias_home}/.codeium/windsurf/memories/global_rules.md"

# auto cannot join a list, and an empty item is not an agent.
for bad_agents in claude,auto claude,,codex; do
	bad_status=0
	HOME="${multi_home}" PATH="${test_path}" XDG_CONFIG_HOME="${multi_home}/.config" \
		"${root}/install.sh" --agent "${bad_agents}" --configure-only >/dev/null 2>&1 ||
		bad_status=$?
	[ "${bad_status}" -eq 2 ]
done

# A later list joins the recorded explicit list instead of replacing it.
HOME="${multi_home}" PATH="${test_path}" XDG_CONFIG_HOME="${multi_home}/.config" \
	"${root}/install.sh" --agent codex,gemini --configure-only >/dev/null
rg -qx 'agents=claude,codex,gemini' "${multi_home}/.config/agent-ready/receipt"
rg -qx 'configured=claude,codex,gemini' "${multi_home}/.config/agent-ready/receipt"

# rollback reinstalls the newest kept version below the receipt's and moves the
# launcher back to it; the tree's own installer rewrites the receipt.
rollback_home="${work}/rollback-home"
rollback_bins="${work}/rollback-bin"
rollback_versions="${rollback_home}/.local/share/agent-ready/versions"
mkdir -p "${rollback_home}" "${rollback_bins}"
run_release "${rollback_home}" "${rollback_bins}" v9.9.0 "${base_bin}" --agent claude,codex --configure-only >/dev/null
run_release "${rollback_home}" "${rollback_bins}" v9.9.1 "${base_bin}" --agent claude,codex --configure-only >/dev/null
rg -qx 'agents=claude,codex' "${rollback_home}/.config/agent-ready/receipt"
rg -qx 'version=v9.9.1' "${rollback_home}/.config/agent-ready/receipt"
run_cli "${rollback_home}" "${rollback_bins}" "${rollback_bins}:${base_bin}" rollback \
	>"${work}/rollback.out"
rg -qF 'Rolling back to agent-ready v9.9.0' "${work}/rollback.out"
[ "$(readlink "${rollback_bins}/agent-ready")" = "${rollback_versions}/v9.9.0/agent-ready" ]
rg -qx 'version=v9.9.0' "${rollback_home}/.config/agent-ready/receipt"
rg -q '^<!-- agent-ready v9\.9\.0 sha256:[0-9a-f]{64} -->$' "${rollback_home}/.codex/AGENTS.md"
rg -q '^<!-- agent-ready v9\.9\.0 sha256:[0-9a-f]{64} -->$' "${rollback_home}/.claude/CLAUDE.md"

# Both repeated agents are compared with the installed tree, so the drift is
# empty rather than half-checked.
run_cli "${rollback_home}" "${rollback_bins}" "${rollback_bins}:${base_bin}" status \
	>"${work}/rollback-status.out"
rg -qF 'version=v9.9.0' "${work}/rollback-status.out"
rg -q '^Claude Code: unchanged ' "${work}/rollback-status.out"
rg -q '^Codex: unchanged ' "${work}/rollback-status.out"

# Without an older tree kept there is nothing to roll back to.
no_earlier_status=0
run_cli "${rollback_home}" "${rollback_bins}" "${rollback_bins}:${base_bin}" rollback \
	>"${work}/rollback.out" 2>&1 || no_earlier_status=$?
[ "${no_earlier_status}" -eq 1 ]
rg -qF 'no earlier version is kept; run agent-ready update v9.9.0' "${work}/rollback.out"

# A launcher this installer did not create is kept, not shadowed.
foreign_home="${work}/foreign-home"
foreign_bins="${work}/foreign-bin"
mkdir -p "${foreign_home}" "${foreign_bins}"
printf '#!/bin/sh\nexit 0\n' >"${foreign_bins}/agent-ready"
chmod +x "${foreign_bins}/agent-ready"
cp "${foreign_bins}/agent-ready" "${work}/foreign-before"
run_release "${foreign_home}" "${foreign_bins}" v9.9.0 "${base_bin}" codex --configure-only \
	>"${work}/foreign.out"
rg -qF "agent-ready: keeping the existing ${foreign_bins}/agent-ready; it was not installed by agent-ready" \
	"${work}/foreign.out"
cmp -s "${work}/foreign-before" "${foreign_bins}/agent-ready"
[ -d "${foreign_home}/.local/share/agent-ready/versions/v9.9.0" ]

# A failed install never self-installs and never touches the launcher.
fail_home="${work}/cli-fail-home"
fail_bins="${work}/cli-fail-bin"
mkdir -p "${fail_home}/.codex" "${fail_bins}"
cat >"${fail_home}/.codex/AGENTS.md" <<'EOF'
user codex
<!-- agent-ready:start -->
broken block
EOF
cp "${fail_home}/.codex/AGENTS.md" "${work}/cli-fail-before"
if run_release "${fail_home}" "${fail_bins}" v9.9.0 "${base_bin}" codex --configure-only \
	>"${work}/cli-fail.out" 2>&1; then
	printf 'a failing install self-installed\n' >&2
	exit 1
fi
rg -qF 'malformed agent-ready markers' "${work}/cli-fail.out"
cmp -s "${work}/cli-fail-before" "${fail_home}/.codex/AGENTS.md"
[ ! -e "${fail_home}/.local" ]
[ ! -e "${fail_bins}/agent-ready" ]

printf 'installer routing checks passed\n'
