#!/usr/bin/env bash

set -euo pipefail

# These point the installer at agent configuration; a developer's own values must
# not route a test at real files.
unset DSH_HOME PI_CODING_AGENT_DIR CLINE_DIR CLINE_DATA_DIR

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

for command in claude codex cursor-agent gemini agy copilot windsurf grok opencode qwen cline kilo crush goose dsh pi; do
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
	"${fake_home}/cline-home/rules" \
	"${fake_home}/.config/opencode" \
	"${fake_home}/.config/kilo" \
	"${fake_home}/.config/crush" \
	"${fake_home}/.config/goose" \
	"${fake_home}/.dsh" \
	"${fake_home}/.pi/agent" \
	"${fake_home}/dotfiles"
printf 'user claude\n' >"${fake_home}/dotfiles/CLAUDE.md"
ln -s ../dotfiles/CLAUDE.md "${fake_home}/.claude/CLAUDE.md"
printf 'user codex\n' >"${fake_home}/.codex/AGENTS.md"
printf 'user gemini\n' >"${fake_home}/.gemini/GEMINI.md"
printf 'user copilot\n' >"${fake_home}/.copilot/copilot-instructions.md"
printf 'user grok\n' >"${fake_home}/grok-home/rules/agent-ready.md"
printf 'user opencode\n' >"${fake_home}/.config/opencode/AGENTS.md"
printf 'user qwen\n' >"${fake_home}/qwen-home/QWEN.md"
printf 'user cline\n' >"${fake_home}/cline-home/rules/agent-ready.md"
printf 'user kilo\n' >"${fake_home}/.config/kilo/AGENTS.md"
printf 'user crush\n' >"${fake_home}/.config/crush/CRUSH.md"
printf 'user goose\n' >"${fake_home}/.config/goose/AGENTS.md"
printf 'user dsh\n' >"${fake_home}/.dsh/AGENTS.md"
printf 'user pi\n' >"${fake_home}/.pi/agent/AGENTS.md"
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
	"${fake_home}/.devin/global_rules.md"
	"${fake_home}/grok-home/rules/agent-ready.md"
	"${fake_home}/.config/opencode/AGENTS.md"
	"${fake_home}/qwen-home/QWEN.md"
	"${fake_home}/cline-home/rules/agent-ready.md"
	"${fake_home}/.config/kilo/AGENTS.md"
	"${fake_home}/.config/crush/CRUSH.md"
	"${fake_home}/.config/goose/AGENTS.md"
	"${fake_home}/.dsh/AGENTS.md"
	"${fake_home}/.pi/agent/AGENTS.md"
	"${fake_home}/.cursor/AGENTS.md"
	"${fake_home}/.cursor/hooks.json"
	"${fake_home}/.cursor/hooks/agent-ready-session-start.json"
)
block_targets=("${install_targets[@]:0:14}")

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
	CLINE_DIR="${fake_home}/cline-home" \
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
	"${fake_home}/.devin/global_rules.md" \
	"${fake_home}/grok-home/rules/agent-ready.md" \
	"${fake_home}/.config/opencode/AGENTS.md" \
	"${fake_home}/qwen-home/QWEN.md" \
	"${fake_home}/cline-home/rules/agent-ready.md" \
	"${fake_home}/.config/kilo/AGENTS.md" \
	"${fake_home}/.config/crush/CRUSH.md" \
	"${fake_home}/.config/goose/AGENTS.md" \
	"${fake_home}/.dsh/AGENTS.md" \
	"${fake_home}/.pi/agent/AGENTS.md"; do
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
# `build | tail` exits 0 on failure, and a missing edit target changes nothing silently.
rg -qF "don't pipe them into \`tail\`/\`head\`; the pipe exits 0" "${fake_home}/.codex/AGENTS.md"
rg -qF '`set -o pipefail` first' "${fake_home}/.codex/AGENTS.md"
rg -qF 'use your file-edit tool, which fails when the text is missing' "${fake_home}/.codex/AGENTS.md"
rg -qF '`str.replace` and `sd` silently change nothing' "${fake_home}/.codex/AGENTS.md"
# rtk renamed `proxy` to `bypass`, and sd treats its pattern as a regex unless -F.
rg -qF '`rtk bypass <cmd>`' "${fake_home}/.codex/AGENTS.md"
rg -qF '`sd -F ' "${fake_home}/.codex/AGENTS.md"
# Without the rewrite flags agents fall back to line-based edits of code.
rg -qF "\`-r '<new>' -U\` to rewrite" "${fake_home}/.codex/AGENTS.md"
# Narrow tools name their trigger; a category alone reads as "replace the default".
rg -qF 'one section of a long Markdown file' "${fake_home}/.codex/AGENTS.md"
rg -qF 'when formatting noise may hide a logic change' "${fake_home}/.codex/AGENTS.md"
rg -qF 'to compare commands, `hyperfine' "${fake_home}/.codex/AGENTS.md"
# jq cannot edit in place, so agents rewrote JSON through Python; yq -i can.
rg -qF '`yq -i` edits these and JSON in place' "${fake_home}/.codex/AGENTS.md"
rg -qF '`osv-scanner scan source -r .` vulnerable dependencies' "${fake_home}/.codex/AGENTS.md"
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
rg -q '^user cline$' "${fake_home}/cline-home/rules/agent-ready.md"
rg -q '^user kilo$' "${fake_home}/.config/kilo/AGENTS.md"
rg -q '^user crush$' "${fake_home}/.config/crush/CRUSH.md"
rg -q '^user goose$' "${fake_home}/.config/goose/AGENTS.md"
rg -q '^user dsh$' "${fake_home}/.dsh/AGENTS.md"
rg -q '^user pi$' "${fake_home}/.pi/agent/AGENTS.md"
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
	"${fake_home}/.devin/global_rules.md" \
	"${fake_home}/grok-home/rules/agent-ready.md" \
	"${fake_home}/.config/opencode/AGENTS.md" \
	"${fake_home}/qwen-home/QWEN.md" \
	"${fake_home}/cline-home/rules/agent-ready.md" \
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
	QWEN_HOME="${fake_home}/qwen-home" CLINE_DIR="${fake_home}/cline-home" \
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
	'init -g --opencode --hook-only --no-patch --no-trust-filters' \
	'init -g --agent antigravity --hook-only --no-patch --no-trust-filters' \
	'init -g --agent pi --hook-only --no-patch --no-trust-filters'; do
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
rg -qx 'configured=antigravity,claude,cline,codex,copilot,crush,cursor,dsh,gemini,goose,grok,kilo,opencode,pi,qwen,windsurf' "${receipt}"
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
	"${targeted_home}/.devin/global_rules.md" \
	"${targeted_home}/.grok/rules/agent-ready.md" \
	"${targeted_home}/.config/opencode/AGENTS.md" \
	"${targeted_home}/.qwen/QWEN.md" \
	"${targeted_home}/.cline/rules/agent-ready.md" \
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
rg -qF 'Code graph: index of symbols, calls, imports' "${targeted_windsurf_home}/.devin/global_rules.md"

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
	"${language_home}/.devin/global_rules.md" \
	"${language_home}/.grok/rules/agent-ready.md" \
	"${language_home}/.config/opencode/AGENTS.md" \
	"${language_home}/.qwen/QWEN.md" \
	"${language_home}/.cline/rules/agent-ready.md" \
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
	publish google/osv-scanner "v${v}" osv-scanner osv-scanner_linux_amd64 osv-scanner_linux_arm64 \
		osv-scanner_darwin_arm64
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
# publish_agent_ready <tag> [version] [published_at] [overlay] — the release
# archive the release-asset workflow attaches, built from this working tree with
# the tag's VERSION. The archive therefore holds the real installer and the real
# agent-ready command. It also joins the newest-first releases list the updater
# reads, and an overlay directory can add files (such as a migration) to that
# release only.
publish_agent_ready() {
	local tag="$1" version="${2:-$1}" published="${3:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
	local overlay="${4:-}" name dir stage releases entry
	name="agent-ready-${tag}"
	dir="${gh_assets}/Dankosik/agent-ready/${tag}"
	stage="${work}/agent-ready-stage/${tag}"
	rm -rf "${stage}"
	mkdir -p "${stage}/${name}" "${dir}" "${gh_api}/repos/Dankosik/agent-ready/releases/tags"
	cp -R "${root}/." "${stage}/${name}/"
	rm -rf "${stage}/${name}/.git" "${stage}/${name}/.codegraph"
	printf '%s\n' "${version}" >"${stage}/${name}/VERSION"
	if [ -n "${overlay}" ]; then
		cp -R "${overlay}/." "${stage}/${name}/"
	fi
	tar -czf "${dir}/${name}.tar.gz" -C "${stage}" "${name}"
	entry=$(jq -n --arg name "${name}.tar.gz" --arg digest "sha256:$(digest_of "${dir}/${name}.tar.gz")" \
		--arg url "file://${dir}/${name}.tar.gz" --arg tag "${tag}" --arg published "${published}" \
		'{tag_name: $tag, draft: false, prerelease: false, published_at: $published,
			body: ("Notes for " + $tag + "."),
			assets: [{name: $name, digest: $digest, browser_download_url: $url}]}')
	printf '%s\n' "${entry}" >"${gh_api}/repos/Dankosik/agent-ready/releases/tags/${tag}"
	releases="${gh_api}/repos/Dankosik/agent-ready/releases.json"
	if [ -f "${releases}" ]; then
		jq -c --argjson entry "${entry}" '[.[] | select(.tag_name != $entry.tag_name)] | [$entry] + .' \
			"${releases}" >"${releases}.tmp"
		mv "${releases}.tmp" "${releases}"
	else
		printf '[%s]\n' "${entry}" >"${releases}"
	fi
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
expected_bins="jq rtk uv uvx sd rg ast-grep gh wt git-wt gitleaks actionlint shellcheck difft yq mdq hyperfine osv-scanner codegraph"

run_binaries >"${work}/binaries.out"
for bin in ${expected_bins}; do
	[ -x "${bins}/${bin}" ] || { printf 'binary install did not provide %s\n' "${bin}" >&2; exit 1; }
done
[ ! -e "${bins}/sg" ] || { printf 'ast-grep installed sg, which shadows shadow-utils sg\n' >&2; exit 1; }
[ "$(wc -l <"${state}" | tr -d ' ')" -eq 16 ]
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
[ "$(rg -c 'already installed$' "${work}/binaries.out")" -eq 17 ]

# --upgrade downloads only what changed upstream.
publish BurntSushi/ripgrep 2.0.0 rg ripgrep-2.0.0-x86_64-unknown-linux-musl.tar.gz
run_binaries --upgrade >"${work}/binaries.out"
rg -qF 'ripgrep 2.0.0 installed' "${work}/binaries.out"
rg -qF 'codegraph v9.9.9 is up to date' "${work}/binaries.out"
[ "$(rg -c 'is up to date$' "${work}/binaries.out")" -eq 16 ]
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

# macOS: coreutils installs `gtimeout`; `timeout` is linked only where none exists.
mac_home="${work}/brew-mac-home"
mac_bin="${work}/mac-bin"
mkdir -p "${mac_home}" "${mac_bin}"
printf '#!/bin/sh\nexit 0\n' >"${mac_bin}/gtimeout"
chmod +x "${mac_bin}/gtimeout"
run_mac() {
	HOME="${mac_home}" PATH="${mac_bin}:${fake_bin}:${base_bin}" XDG_CONFIG_HOME="${mac_home}/.config" \
		CODEX_HOME="${mac_home}/.codex" AGENT_READY_OS=Darwin \
		"${root}/install.sh" --agent codex
}
run_mac >"${work}/mac.out"
rg -qF 'timeout: linked' "${work}/mac.out"
[ "$(readlink "${mac_home}/.local/bin/timeout")" = "${mac_bin}/gtimeout" ]
run_mac >"${work}/mac.out"
rg -qx 'timeout already linked' "${work}/mac.out"
# A file the user put there is kept, and a `timeout` already on PATH needs no link.
rm "${mac_home}/.local/bin/timeout"
printf 'mine\n' >"${mac_home}/.local/bin/timeout"
run_mac >"${work}/mac.out"
rg -qF 'timeout: keeping the existing' "${work}/mac.out"
rg -qx 'mine' "${mac_home}/.local/bin/timeout"
rm "${mac_home}/.local/bin/timeout"
cp "${mac_bin}/gtimeout" "${mac_bin}/timeout"
run_mac >"${work}/mac.out"
[ ! -e "${mac_home}/.local/bin/timeout" ]

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
	"${multi_home}/.devin/global_rules.md" \
	"${multi_home}/.grok/rules/agent-ready.md" \
	"${multi_home}/.config/opencode/AGENTS.md" \
	"${multi_home}/.qwen/QWEN.md" \
	"${multi_home}/.cline/rules/agent-ready.md" \
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
rg -q '^Tool routing \(use instead of defaults\):$' "${alias_home}/.devin/global_rules.md"

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

# update: resolve the newest eligible release from a file:// stand-in for the
# releases list, then download, verify, and install it through bootstrap. The
# releases are the real tree with only VERSION changed, so the updater, the
# installer, and the migration all run the code they ship with.
stamp_ago() {
	local secs=$(( $(date -u +%s) - $1 * 3600 ))
	date -u -d "@${secs}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null ||
		date -u -r "${secs}" +%Y-%m-%dT%H:%M:%SZ
}
migration_overlay="${work}/migration-overlay"
mkdir -p "${migration_overlay}/migrations"
cat >"${migration_overlay}/migrations/v9.9.2-test.sh" <<'EOF'
#!/usr/bin/env bash
printf 'migrated\n' >"${HOME}/migration-marker"
EOF
chmod +x "${migration_overlay}/migrations/v9.9.2-test.sh"
publish_agent_ready v9.9.0 v9.9.0 "$(stamp_ago 96)"
publish_agent_ready v9.9.1 v9.9.1 "$(stamp_ago 48)"
publish_agent_ready v9.9.2 v9.9.2 "$(stamp_ago 0)" "${migration_overlay}"
# The list holds only the three updatable releases, newest first, so the
# bootstrap-only v9.9.9 never becomes the target.
jq -s -c '[.[] | select(.tag_name | test("^v9\\.9\\.[0-2]$"))] | sort_by(.tag_name) | reverse' \
	"${gh_api}/repos/Dankosik/agent-ready/releases/tags/"v9.9.? \
	>"${gh_api}/repos/Dankosik/agent-ready/releases.json"

update_home="${work}/update-home"
update_bins="${work}/update-launcher-bin"
update_versions="${update_home}/.local/share/agent-ready/versions"
# base_bin serves the releases list through its curl wrapper but has no jq.
update_bin="${work}/update-bin"
mkdir -p "${update_home}" "${update_bins}" "${update_bin}"
for entry in "${base_bin}"/*; do ln -s "${entry}" "${update_bin}/${entry##*/}"; done
ln -s "$(command -v jq)" "${update_bin}/jq"
update_path="${update_bin}:${test_path}"
run_update() {
	local home="$1" bins="$2" age="$3"
	shift 3
	HOME="${home}" PATH="${update_path}" \
		XDG_CONFIG_HOME="${home}/.config" \
		XDG_DATA_HOME="${home}/.local/share" \
		AGENT_READY_BIN_DIR="${bins}" \
		CODEX_HOME="${home}/.codex" \
		AGENT_READY_GITHUB_API="file://${gh_api}" \
		AGENT_READY_MIN_RELEASE_AGE="${age}" \
		"${bins}/agent-ready" update "$@"
}

run_release "${update_home}" "${update_bins}" v9.9.0 "${base_bin}" --agent codex --configure-only \
	>"${work}/update.out"
[ "$(readlink "${update_bins}/agent-ready")" = "${update_versions}/v9.9.0/agent-ready" ]

# --check only reports: exit 10 and no change.
check_status=0
run_update "${update_home}" "${update_bins}" 0 --check >"${work}/update.out" || check_status=$?
[ "${check_status}" -eq 10 ]
rg -qF 'agent-ready v9.9.0 → v9.9.2 available' "${work}/update.out"
[ "$(readlink "${update_bins}/agent-ready")" = "${update_versions}/v9.9.0/agent-ready" ]
rg -qx 'version=v9.9.0' "${update_home}/.config/agent-ready/receipt"

run_update "${update_home}" "${update_bins}" 0 >"${work}/update.out"
rg -qF 'Updating agent-ready v9.9.0 → v9.9.2' "${work}/update.out"
rg -qF 'Running migration v9.9.2-test.sh' "${work}/update.out"
rg -qF 'Release notes: https://github.com/Dankosik/agent-ready/releases/tag/v9.9.2' "${work}/update.out"
rg -qF 'Notes for v9.9.2.' "${work}/update.out"
rg -qF 'Start a new agent session to load the updated instructions.' "${work}/update.out"
[ "$(readlink "${update_bins}/agent-ready")" = "${update_versions}/v9.9.2/agent-ready" ]
rg -qx 'version=v9.9.2' "${update_home}/.config/agent-ready/receipt"
rg -qx 'agents=codex' "${update_home}/.config/agent-ready/receipt"
rg -qx 'configured=codex' "${update_home}/.config/agent-ready/receipt"
rg -q '^<!-- agent-ready v9\.9\.2 sha256:[0-9a-f]{64} -->$' "${update_home}/.codex/AGENTS.md"
[ -f "${update_home}/migration-marker" ]
# The receipt's one agent is repeated; every other fake agent on PATH stays out.
for untouched in \
	"${update_home}/.claude/CLAUDE.md" \
	"${update_home}/.gemini/GEMINI.md" \
	"${update_home}/.copilot/copilot-instructions.md" \
	"${update_home}/.devin/global_rules.md" \
	"${update_home}/.grok/rules/agent-ready.md" \
	"${update_home}/.config/opencode/AGENTS.md" \
	"${update_home}/.qwen/QWEN.md" \
	"${update_home}/.cline/rules/agent-ready.md" \
	"${update_home}/.config/kilo/AGENTS.md" \
	"${update_home}/.config/crush/CRUSH.md" \
	"${update_home}/.config/goose/AGENTS.md" \
	"${update_home}/.cursor/hooks.json"; do
	[ ! -e "${untouched}" ]
done
# A configure-only receipt stays configure-only, and nothing upgrades a tool.
[ ! -e "${update_home}/brew-calls" ]
if rg -q -- '--upgrade' "${update_home}/rtk-calls"; then
	printf 'update upgraded a tool without --upgrade-tools\n' >&2
	exit 1
fi

# Nothing newer is left, so a second update changes no byte and does not run the
# migration again.
rm -f "${update_home}/migration-marker"
agent_before=$(digest_of "${update_home}/.codex/AGENTS.md")
receipt_before=$(digest_of "${update_home}/.config/agent-ready/receipt")
launcher_before=$(readlink "${update_bins}/agent-ready")
run_update "${update_home}" "${update_bins}" 0 >"${work}/update.out"
rg -qF 'agent-ready v9.9.2 is up to date' "${work}/update.out"
[ "$(digest_of "${update_home}/.codex/AGENTS.md")" = "${agent_before}" ]
[ "$(digest_of "${update_home}/.config/agent-ready/receipt")" = "${receipt_before}" ]
[ "$(readlink "${update_bins}/agent-ready")" = "${launcher_before}" ]
[ ! -e "${update_home}/migration-marker" ]

# A release younger than the default 24 hours is skipped, so the installed
# v9.9.1 is the newest eligible release and the update is already current.
age_home="${work}/update-age-home"
age_bins="${work}/update-age-bin"
mkdir -p "${age_home}" "${age_bins}"
run_release "${age_home}" "${age_bins}" v9.9.1 "${base_bin}" --agent codex --configure-only \
	>"${work}/min-age.out"
run_update "${age_home}" "${age_bins}" 24 >>"${work}/min-age.out"
rg -qF 'agent-ready v9.9.1 is up to date' "${work}/min-age.out"
[ "$(readlink "${age_bins}/agent-ready")" = \
	"${age_home}/.local/share/agent-ready/versions/v9.9.1/agent-ready" ]

# With every release inside the minimum age there is nothing newer to offer:
# up to date, and --check exits 0 rather than failing.
run_update "${age_home}" "${age_bins}" 1000 >"${work}/min-age-none.out"
rg -qF 'agent-ready v9.9.1 is up to date' "${work}/min-age-none.out"
run_update "${age_home}" "${age_bins}" 1000 --check >"${work}/min-age-none.out"
rg -qF 'agent-ready v9.9.1 is up to date' "${work}/min-age-none.out"

# An explicit older release is a downgrade, and it is applied.
run_update "${update_home}" "${update_bins}" 0 v9.9.1 >"${work}/update.out"
rg -qF 'Downgrading agent-ready v9.9.2 → v9.9.1' "${work}/update.out"
[ "$(readlink "${update_bins}/agent-ready")" = "${update_versions}/v9.9.1/agent-ready" ]
rg -qx 'version=v9.9.1' "${update_home}/.config/agent-ready/receipt"
rg -q '^<!-- agent-ready v9\.9\.1 sha256:[0-9a-f]{64} -->$' "${update_home}/.codex/AGENTS.md"

# --dry-run downloads and reports but installs nothing.
agent_before=$(digest_of "${update_home}/.codex/AGENTS.md")
receipt_before=$(digest_of "${update_home}/.config/agent-ready/receipt")
launcher_before=$(readlink "${update_bins}/agent-ready")
versions_before=$(find "${update_versions}" -mindepth 1 -maxdepth 1 -type d | sort | tr '\n' ' ')
run_update "${update_home}" "${update_bins}" 0 --dry-run >"${work}/dry-run.out"
rg -qF 'Updating agent-ready v9.9.1 → v9.9.2' "${work}/dry-run.out"
rg -q '^Codex: would refresh ' "${work}/dry-run.out"
[ "$(digest_of "${update_home}/.codex/AGENTS.md")" = "${agent_before}" ]
[ "$(digest_of "${update_home}/.config/agent-ready/receipt")" = "${receipt_before}" ]
[ "$(readlink "${update_bins}/agent-ready")" = "${launcher_before}" ]
[ "$(find "${update_versions}" -mindepth 1 -maxdepth 1 -type d | sort | tr '\n' ' ')" = "${versions_before}" ]

# A stale lock refuses the run before anything is resolved or changed.
mkdir "${update_home}/.config/agent-ready/update.lock"
lock_status=0
run_update "${update_home}" "${update_bins}" 0 >"${work}/lock.out" 2>&1 || lock_status=$?
[ "${lock_status}" -eq 1 ]
rg -qF "another agent-ready update is running (remove ${update_home}/.config/agent-ready/update.lock if it is stale)" \
	"${work}/lock.out"
[ "$(digest_of "${update_home}/.codex/AGENTS.md")" = "${agent_before}" ]
[ "$(digest_of "${update_home}/.config/agent-ready/receipt")" = "${receipt_before}" ]
[ "$(readlink "${update_bins}/agent-ready")" = "${launcher_before}" ]
rmdir "${update_home}/.config/agent-ready/update.lock"

# A digest mismatch on the target stops the update with nothing replaced.
cp "${gh_api}/repos/Dankosik/agent-ready/releases/tags/v9.9.2" "${work}/v9.9.2-tag.json"
jq --arg name "agent-ready-v9.9.2.tar.gz" \
	'(.assets[] | select(.name == $name) | .digest) = "sha256:0000000000000000000000000000000000000000000000000000000000000000"' \
	"${work}/v9.9.2-tag.json" >"${gh_api}/repos/Dankosik/agent-ready/releases/tags/v9.9.2"
digest_status=0
run_update "${update_home}" "${update_bins}" 0 >"${work}/digest.out" 2>&1 || digest_status=$?
[ "${digest_status}" -eq 1 ]
rg -qF 'checksum mismatch for agent-ready-v9.9.2.tar.gz; nothing installed' "${work}/digest.out"
[ "$(digest_of "${update_home}/.codex/AGENTS.md")" = "${agent_before}" ]
[ "$(digest_of "${update_home}/.config/agent-ready/receipt")" = "${receipt_before}" ]
[ "$(readlink "${update_bins}/agent-ready")" = "${launcher_before}" ]
cp "${work}/v9.9.2-tag.json" "${gh_api}/repos/Dankosik/agent-ready/releases/tags/v9.9.2"

# Without a receipt (v1.3.0 or earlier) the tool mode is read from the machine
# and the agents are auto-detected again, and the update says so.
legacy_home="${work}/update-legacy-home"
legacy_bins="${work}/update-legacy-bin"
mkdir -p "${legacy_home}" "${legacy_bins}"
run_release "${legacy_home}" "${legacy_bins}" v9.9.0 "${base_bin}" --agent codex --configure-only \
	>/dev/null
rm "${legacy_home}/.config/agent-ready/receipt"
run_update "${legacy_home}" "${legacy_bins}" 0 >"${work}/legacy.out"
rg -qF 'No receipt: assuming agents=auto and tools=brew' "${work}/legacy.out"
rg -qF 'Updating agent-ready none → v9.9.2' "${work}/legacy.out"
rg -qx 'version=v9.9.2' "${legacy_home}/.config/agent-ready/receipt"
rg -qx 'agents=auto' "${legacy_home}/.config/agent-ready/receipt"
rg -q '^<!-- agent-ready v9\.9\.2 ' "${legacy_home}/.claude/CLAUDE.md"
[ "$(readlink "${legacy_bins}/agent-ready")" = \
	"${legacy_home}/.local/share/agent-ready/versions/v9.9.2/agent-ready" ]

# The documented `curl … | AGENT_READY_REF=… bash -s -- update` path: a
# standalone bootstrap downloads the pinned tree and runs its update, which then
# installs the newest release and moves the launcher there.
bootstrap_home="${work}/update-bootstrap-home"
bootstrap_bins="${work}/update-bootstrap-bin"
mkdir -p "${bootstrap_home}" "${bootstrap_bins}"
HOME="${bootstrap_home}" PATH="${update_path}" \
	XDG_CONFIG_HOME="${bootstrap_home}/.config" \
	XDG_DATA_HOME="${bootstrap_home}/.local/share" \
	AGENT_READY_BIN_DIR="${bootstrap_bins}" \
	CODEX_HOME="${bootstrap_home}/.codex" \
	AGENT_READY_REF=v9.9.1 AGENT_READY_GITHUB_API="file://${gh_api}" \
	AGENT_READY_MIN_RELEASE_AGE=0 \
	bash "${bootstrap_copy}/bootstrap.sh" update </dev/null >"${work}/bootstrap-update.out"
rg -qF 'Updating agent-ready none → v9.9.2' "${work}/bootstrap-update.out"
rg -qx 'version=v9.9.2' "${bootstrap_home}/.config/agent-ready/receipt"
[ "$(readlink "${bootstrap_bins}/agent-ready")" = \
	"${bootstrap_home}/.local/share/agent-ready/versions/v9.9.2/agent-ready" ]

# The language step repeats the language's own installer, but must not let its
# automatic mode re-detect agents: a Go receipt with one explicit agent stays
# one agent, and that agent's block carries the Go routing.
lang_home="${work}/update-language-home"
lang_bins="${work}/update-language-bin"
mkdir -p "${lang_home}/.config/agent-ready/languages" "${lang_bins}"
printf 'enabled\n' >"${lang_home}/.config/agent-ready/languages/go"
run_release "${lang_home}" "${lang_bins}" v9.9.0 "${base_bin}" --agent codex --configure-only \
	>"${work}/language.out"
rg -qx 'languages=go' "${lang_home}/.config/agent-ready/receipt"
run_update "${lang_home}" "${lang_bins}" 0 >>"${work}/language.out"
rg -qF 'Codex: kept existing gopls MCP' "${work}/language.out"
rg -qx 'version=v9.9.2' "${lang_home}/.config/agent-ready/receipt"
rg -qx 'agents=codex' "${lang_home}/.config/agent-ready/receipt"
rg -qx 'languages=go' "${lang_home}/.config/agent-ready/receipt"
rg -q '^<!-- agent-ready v9\.9\.2 sha256:[0-9a-f]{64} -->$' "${lang_home}/.codex/AGENTS.md"
rg -qF 'Use `go_workspace` only when the module/workspace layout is unclear' \
	"${lang_home}/.codex/AGENTS.md"
[ ! -e "${lang_home}/.claude/CLAUDE.md" ]
[ ! -e "${lang_home}/.gemini/GEMINI.md" ]

# uninstall removes only what agent-ready wrote: the managed blocks, its own
# Cursor hook entry, and agent-ready's state. Tools and third-party files stay.
tree_digest() {
	local dir="$1" path
	{
		find "${dir}" -type f | LC_ALL=C sort | while IFS= read -r path; do
			printf 'f %s %s\n' "${path#"${dir}"}" "$(digest_of "${path}")"
		done
		find "${dir}" -type l | LC_ALL=C sort | while IFS= read -r path; do
			printf 'l %s %s\n' "${path#"${dir}"}" "$(readlink "${path}")"
		done
	} | digest_stdin
}
run_uninstall_checkout() {
	local home="$1"
	shift
	HOME="${home}" XDG_CONFIG_HOME="${home}/.config" \
		XDG_DATA_HOME="${home}/.local/share" \
		CLAUDE_CONFIG_DIR="${home}/.claude" \
		CODEX_HOME="${home}/.codex" \
		COPILOT_HOME="${home}/.copilot" \
		GROK_HOME="${home}/.grok" \
		QWEN_HOME="${home}/.qwen" \
		CLINE_DIR="${home}/.cline" \
		PATH="${test_path}" \
		"${root}/install.sh" --uninstall "$@"
}

uninstall_home="${work}/uninstall-home"
uninstall_bins="${work}/uninstall-bin"
uninstall_versions="${uninstall_home}/.local/share/agent-ready/versions"
uninstall_originals="${work}/uninstall-originals"
mkdir -p "${uninstall_originals}" "${uninstall_home}/.claude" "${uninstall_home}/dotfiles" \
	"${uninstall_home}/.codex" "${uninstall_home}/.gemini" "${uninstall_home}/.copilot" \
	"${uninstall_home}/.grok/rules" "${uninstall_home}/.config/opencode" \
	"${uninstall_home}/.qwen" "${uninstall_home}/.cline/rules" \
	"${uninstall_home}/.config/kilo" "${uninstall_home}/.config/crush" \
	"${uninstall_home}/.config/goose" "${uninstall_home}/.cursor" \
	"${uninstall_home}/.dsh" "${uninstall_home}/.pi/agent" \
	"${uninstall_home}/.config/agent-ready/languages" "${uninstall_bins}"
printf 'user claude\n' >"${uninstall_home}/dotfiles/CLAUDE.md"
ln -s ../dotfiles/CLAUDE.md "${uninstall_home}/.claude/CLAUDE.md"
printf 'user codex\n' >"${uninstall_home}/.codex/AGENTS.md"
printf 'user gemini\n' >"${uninstall_home}/.gemini/GEMINI.md"
printf 'user copilot\n' >"${uninstall_home}/.copilot/copilot-instructions.md"
printf 'user grok\n' >"${uninstall_home}/.grok/rules/agent-ready.md"
printf 'user opencode\n' >"${uninstall_home}/.config/opencode/AGENTS.md"
printf 'user qwen\n' >"${uninstall_home}/.qwen/QWEN.md"
printf 'user cline\n' >"${uninstall_home}/.cline/rules/agent-ready.md"
printf 'user kilo\n' >"${uninstall_home}/.config/kilo/AGENTS.md"
printf 'user crush\n' >"${uninstall_home}/.config/crush/CRUSH.md"
printf 'user goose\n' >"${uninstall_home}/.config/goose/AGENTS.md"
printf 'user dsh\n' >"${uninstall_home}/.dsh/AGENTS.md"
printf 'user pi\n' >"${uninstall_home}/.pi/agent/AGENTS.md"
printf 'enabled\n' >"${uninstall_home}/.config/agent-ready/languages/go"
cat >"${uninstall_home}/.cursor/hooks.json" <<'EOF'
{
  "version": 1,
  "hooks": {
    "sessionStart": [{"command": "./hooks/existing.sh"}],
    "stop": [{"command": "./hooks/stop.sh"}]
  }
}
EOF
uninstall_user_targets=(
	"${uninstall_home}/.claude/CLAUDE.md"
	"${uninstall_home}/.codex/AGENTS.md"
	"${uninstall_home}/.gemini/GEMINI.md"
	"${uninstall_home}/.copilot/copilot-instructions.md"
	"${uninstall_home}/.grok/rules/agent-ready.md"
	"${uninstall_home}/.config/opencode/AGENTS.md"
	"${uninstall_home}/.qwen/QWEN.md"
	"${uninstall_home}/.cline/rules/agent-ready.md"
	"${uninstall_home}/.config/kilo/AGENTS.md"
	"${uninstall_home}/.config/crush/CRUSH.md"
	"${uninstall_home}/.config/goose/AGENTS.md"
	"${uninstall_home}/.dsh/AGENTS.md"
	"${uninstall_home}/.pi/agent/AGENTS.md"
)
for target in "${uninstall_user_targets[@]}"; do
	cp -p "${target}" "${uninstall_originals}/$(printf '%s' "${target}" | tr '/' '_')"
done

publish_agent_ready v9.9.4
run_release "${uninstall_home}" "${uninstall_bins}" v9.9.4 "${test_path}" \
	--agent claude,codex,cursor,gemini,antigravity,copilot,windsurf,grok,opencode,qwen,cline,kilo,crush,goose,dsh,pi \
	--configure-only >"${work}/uninstall-install.out"
[ -L "${uninstall_bins}/agent-ready" ]
[ "$(readlink "${uninstall_bins}/agent-ready")" = "${uninstall_versions}/v9.9.4/agent-ready" ]
[ -f "${uninstall_home}/.config/agent-ready/receipt" ]
[ -f "${uninstall_home}/.devin/global_rules.md" ]
rg -qx 'languages=go' "${uninstall_home}/.config/agent-ready/receipt"

# --dry-run reports every target and changes not one byte.
uninstall_before=$(tree_digest "${uninstall_home}")
run_cli "${uninstall_home}" "${uninstall_bins}" "${test_path}" uninstall --dry-run \
	>"${work}/uninstall-dry.out"
rg -q '^Codex: would remove ' "${work}/uninstall-dry.out"
rg -q '^Cursor: would remove the session hook ' "${work}/uninstall-dry.out"
rg -qF 'would remove receipt ' "${work}/uninstall-dry.out"
rg -qF 'would remove languages state ' "${work}/uninstall-dry.out"
rg -qF 'would remove versions directory ' "${work}/uninstall-dry.out"
[ "$(tree_digest "${uninstall_home}")" = "${uninstall_before}" ]

# A local edit inside a block stops the run before anything is removed, and
# --force is the explicit way past it.
uninstall_edit_home="${work}/uninstall-edit-home"
mkdir -p "${uninstall_edit_home}/.codex"
printf 'user codex\n' >"${uninstall_edit_home}/.codex/AGENTS.md"
cp "${uninstall_edit_home}/.codex/AGENTS.md" "${work}/uninstall-edit-original"
run_uninstall_checkout_install() {
	local home="$1"
	shift
	HOME="${home}" XDG_CONFIG_HOME="${home}/.config" \
		CODEX_HOME="${home}/.codex" PATH="${test_path}" \
		"${root}/install.sh" --configure-only "$@"
}
run_uninstall_checkout_install "${uninstall_edit_home}" --agent codex >/dev/null
sed 's/^- Shell:.*/- Shell: local edit that uninstall must not remove./' \
	"${uninstall_edit_home}/.codex/AGENTS.md" >"${work}/uninstall-edit-file"
cp "${work}/uninstall-edit-file" "${uninstall_edit_home}/.codex/AGENTS.md"
uninstall_edit_before=$(digest_of "${uninstall_edit_home}/.codex/AGENTS.md")
uninstall_edit_status=0
run_uninstall_checkout "${uninstall_edit_home}" >"${work}/uninstall-edit.out" 2>&1 ||
	uninstall_edit_status=$?
[ "${uninstall_edit_status}" -eq 1 ]
rg -qF 'has local edits inside the agent-ready block' "${work}/uninstall-edit.out"
rg -qF "${uninstall_edit_home}/.codex/AGENTS.md" "${work}/uninstall-edit.out"
[ "$(digest_of "${uninstall_edit_home}/.codex/AGENTS.md")" = "${uninstall_edit_before}" ]
[ -f "${uninstall_edit_home}/.config/agent-ready/receipt" ]
run_uninstall_checkout "${uninstall_edit_home}" --force >/dev/null
[ "$(digest_of "${uninstall_edit_home}/.codex/AGENTS.md")" = "$(digest_of "${work}/uninstall-edit-original")" ]
[ ! -e "${uninstall_edit_home}/.config/agent-ready/receipt" ]

# Malformed markers are reported for every target, never half-removed.
uninstall_bad_home="${work}/uninstall-bad-home"
mkdir -p "${uninstall_bad_home}/.codex" "${uninstall_bad_home}/.gemini"
printf 'user codex\n<!-- agent-ready:start -->\nbroken block\n' >"${uninstall_bad_home}/.codex/AGENTS.md"
printf 'user gemini\n<!-- agent-ready:start -->\nbroken block\n' >"${uninstall_bad_home}/.gemini/GEMINI.md"
cp "${uninstall_bad_home}/.codex/AGENTS.md" "${work}/uninstall-bad-codex"
cp "${uninstall_bad_home}/.gemini/GEMINI.md" "${work}/uninstall-bad-gemini"
uninstall_bad_status=0
run_uninstall_checkout "${uninstall_bad_home}" >"${work}/uninstall-bad.out" 2>&1 ||
	uninstall_bad_status=$?
[ "${uninstall_bad_status}" -eq 1 ]
rg -qF "${uninstall_bad_home}/.codex/AGENTS.md" "${work}/uninstall-bad.out"
rg -qF "${uninstall_bad_home}/.gemini/GEMINI.md" "${work}/uninstall-bad.out"
cmp -s "${work}/uninstall-bad-codex" "${uninstall_bad_home}/.codex/AGENTS.md"
cmp -s "${work}/uninstall-bad-gemini" "${uninstall_bad_home}/.gemini/GEMINI.md"

# A block the receipt does not name, such as one left by a v1.3.0 install, is
# still removed.
uninstall_mixed_home="${work}/uninstall-mixed-home"
mkdir -p "${uninstall_mixed_home}/.codex" "${uninstall_mixed_home}/.gemini"
printf 'user codex\n' >"${uninstall_mixed_home}/.codex/AGENTS.md"
printf 'user gemini\n\n<!-- agent-ready:start -->\nlegacy routing\n<!-- agent-ready:end -->\n' \
	>"${uninstall_mixed_home}/.gemini/GEMINI.md"
run_uninstall_checkout_install "${uninstall_mixed_home}" --agent codex >/dev/null
rg -qx 'configured=codex' "${uninstall_mixed_home}/.config/agent-ready/receipt"
run_uninstall_checkout "${uninstall_mixed_home}" >/dev/null
[ "$(cat "${uninstall_mixed_home}/.codex/AGENTS.md")" = 'user codex' ]
[ "$(cat "${uninstall_mixed_home}/.gemini/GEMINI.md")" = 'user gemini' ]

# The real run restores every user file, keeps only the other Cursor hooks, and
# removes the receipt, the launcher, and the versions directory.
run_cli "${uninstall_home}" "${uninstall_bins}" "${test_path}" uninstall \
	>"${work}/uninstall.out"
for target in "${uninstall_user_targets[@]}"; do
	cmp -s "${target}" "${uninstall_originals}/$(printf '%s' "${target}" | tr '/' '_')" || {
		printf 'uninstall did not restore %s\n' "${target}" >&2
		exit 1
	}
done
[ -L "${uninstall_home}/.claude/CLAUDE.md" ]
[ -f "${uninstall_home}/.devin/global_rules.md" ]
[ ! -s "${uninstall_home}/.devin/global_rules.md" ]
jq -e '
	.version == 1 and
	.hooks.stop[0].command == "./hooks/stop.sh" and
	([.hooks.sessionStart[] | select(.command == "./hooks/existing.sh")] | length) == 1 and
	([.hooks.sessionStart[] | select(.command == "cat ./hooks/agent-ready-session-start.json")] | length) == 0
' "${uninstall_home}/.cursor/hooks.json" >/dev/null
[ ! -e "${uninstall_home}/.cursor/hooks/agent-ready-session-start.json" ]
[ ! -e "${uninstall_home}/.config/agent-ready/receipt" ]
[ ! -e "${uninstall_home}/.config/agent-ready/languages" ]
[ ! -e "${uninstall_versions}" ]
[ ! -L "${uninstall_bins}/agent-ready" ]
[ ! -e "${uninstall_bins}/agent-ready" ]
rg -qF 'removed receipt ' "${work}/uninstall.out"
rg -qF 'removed versions directory ' "${work}/uninstall.out"
rg -qF 'rtk init -g --uninstall' "${work}/uninstall.out"
rg -qF 'codegraph uninstall' "${work}/uninstall.out"

# A second uninstall has nothing left to do and still exits 0.
uninstall_second_status=0
run_uninstall_checkout "${uninstall_home}" >"${work}/uninstall-second.out" 2>&1 ||
	uninstall_second_status=$?
[ "${uninstall_second_status}" -eq 0 ]
[ ! -e "${uninstall_home}/.config/agent-ready/receipt" ]
rg -qF 'brew uninstall ' "${work}/uninstall-second.out"

# A launcher agent-ready did not create is kept, while its own tree and receipt
# still go.
foreign_uninstall_tree="${foreign_home}/.local/share/agent-ready/versions/v9.9.0/agent-ready"
HOME="${foreign_home}" XDG_CONFIG_HOME="${foreign_home}/.config" \
	XDG_DATA_HOME="${foreign_home}/.local/share" \
	AGENT_READY_BIN_DIR="${foreign_bins}" PATH="${test_path}" \
	bash "${foreign_uninstall_tree}" uninstall >"${work}/uninstall-foreign.out"
cmp -s "${work}/foreign-before" "${foreign_bins}/agent-ready"
[ ! -e "${foreign_home}/.local/share/agent-ready/versions" ]
[ ! -e "${foreign_home}/.config/agent-ready/receipt" ]
rg -qF "keeping ${foreign_bins}/agent-ready: it was not installed by agent-ready" \
	"${work}/uninstall-foreign.out"

# The tool state files outlive the configuration while their tools are there.
uninstall_state_home="${work}/uninstall-state-home"
uninstall_state_config="${uninstall_state_home}/.config/agent-ready"
mkdir -p "${uninstall_state_home}/.local/bin" "${uninstall_state_config}"
for bin in rg codegraph; do
	printf '#!/bin/sh\nexit 0\n' >"${uninstall_state_home}/.local/bin/${bin}"
	chmod +x "${uninstall_state_home}/.local/bin/${bin}"
done
printf 'ripgrep v1.0.0\n' >"${uninstall_state_config}/binaries"
printf 'v9.9.9\n' >"${uninstall_state_config}/codegraph"
HOME="${uninstall_state_home}" XDG_CONFIG_HOME="${uninstall_state_home}/.config" \
	PATH="${base_bin}" "${root}/install.sh" --uninstall >"${work}/uninstall-state.out"
[ -f "${uninstall_state_config}/binaries" ]
[ -f "${uninstall_state_config}/codegraph" ]
rg -qF 'keeping ' "${work}/uninstall-state.out"
rg -qF 'binaries: its tools are still installed' "${work}/uninstall-state.out"
rg -qF 'codegraph: codegraph is still installed' "${work}/uninstall-state.out"
rg -qF "rm ${uninstall_state_home}/.local/bin/rg" "${work}/uninstall-state.out"
rm -f "${uninstall_state_home}/.local/bin/rg" "${uninstall_state_home}/.local/bin/codegraph"
HOME="${uninstall_state_home}" XDG_CONFIG_HOME="${uninstall_state_home}/.config" \
	PATH="${base_bin}" "${root}/install.sh" --uninstall >"${work}/uninstall-state.out"
[ ! -e "${uninstall_state_config}/binaries" ]
[ ! -e "${uninstall_state_config}/codegraph" ]

# Aliases resolve to canonical ids, and CodeGraph gets only the targets it has.
new_agents_home="${work}/new-agents-home"
mkdir -p "${new_agents_home}"
HOME="${new_agents_home}" XDG_CONFIG_HOME="${new_agents_home}/.config" PATH="${test_path}" \
	"${root}/install.sh" --agent agy,deepseek-harness,pi-coding-agent --configure-only \
	>"${work}/new-agents.out" 2>&1
rg -qx 'agents=antigravity,dsh,pi' "${new_agents_home}/.config/agent-ready/receipt"
rg -qxF 'install --yes --target=antigravity --location=global --no-permissions' \
	"${new_agents_home}/codegraph-calls"
rg -qF 'MCP setup is not available for dsh' "${work}/new-agents.out"
rg -qF 'MCP setup is not available for pi' "${work}/new-agents.out"
rg -q '^Tool routing \(use instead of defaults\):$' "${new_agents_home}/.dsh/AGENTS.md"
rg -q '^Tool routing \(use instead of defaults\):$' "${new_agents_home}/.pi/agent/AGENTS.md"
# Without Gemini nothing writes CodeGraph's section, so the block keeps the line.
rg -qF 'Code graph: index of symbols, calls, imports' "${new_agents_home}/.gemini/GEMINI.md"

# The launcher accepts every selector the installer does.
launcher_home="${work}/launcher-home"
mkdir -p "${launcher_home}"
for selector in antigravity antigravity-cli agy dsh deepseek-harness pi pi-coding-agent; do
	HOME="${launcher_home}" XDG_CONFIG_HOME="${launcher_home}/.config" PATH="${test_path}" \
		"${root}/agent-ready" "${selector}" --configure-only >/dev/null 2>&1
done
rg -qx 'agents=antigravity,dsh,pi' "${launcher_home}/.config/agent-ready/receipt"

# DSH_HOME and PI_CODING_AGENT_DIR move the files those agents read.
moved_home="${work}/moved-home"
mkdir -p "${moved_home}"
HOME="${moved_home}" XDG_CONFIG_HOME="${moved_home}/.config" PATH="${test_path}" \
	DSH_HOME="${moved_home}/dsh-home" PI_CODING_AGENT_DIR="${moved_home}/pi-home" \
	"${root}/install.sh" --agent dsh,pi --configure-only >/dev/null 2>&1
rg -q '^Tool routing' "${moved_home}/dsh-home/AGENTS.md"
rg -q '^Tool routing' "${moved_home}/pi-home/AGENTS.md"
[ ! -e "${moved_home}/.dsh" ]
[ ! -e "${moved_home}/.pi/agent/AGENTS.md" ]

# Gemini and Antigravity share one file: one block in either order, stable across
# reruns, and a dry run agrees. The fake CodeGraph writes no section, so the
# block is what is being compared.
shared_home="${work}/shared-home"
mkdir -p "${shared_home}/.gemini"
printf 'user gemini\n' >"${shared_home}/.gemini/GEMINI.md"
run_shared() {
	HOME="${shared_home}" XDG_CONFIG_HOME="${shared_home}/.config" PATH="${test_path}" \
		"${root}/install.sh" --configure-only "$@"
}
run_shared --agent gemini,antigravity >/dev/null 2>&1
[ "$(rg -c '^<!-- agent-ready:start -->$' "${shared_home}/.gemini/GEMINI.md")" -eq 1 ]
if rg -q '^- Code graph:' "${shared_home}/.gemini/GEMINI.md"; then
	printf 'shared Gemini block repeats the CodeGraph rule\n' >&2
	exit 1
fi
shared_digest=$(digest_of "${shared_home}/.gemini/GEMINI.md")
run_shared --agent antigravity,gemini >/dev/null 2>&1
[ "$(digest_of "${shared_home}/.gemini/GEMINI.md")" = "${shared_digest}" ]
run_shared --agent gemini,antigravity --dry-run >"${work}/shared-dry.out" 2>&1
if rg -q 'would (add|refresh)' "${work}/shared-dry.out"; then
	printf 'dry run of the shared Gemini file reported pending changes\n' >&2
	exit 1
fi
rg -q '^user gemini$' "${shared_home}/.gemini/GEMINI.md"

# Pi loads only the first context file in its directory. A new AGENTS.md would
# hide the user's CLAUDE.md, and an AGENTS.md beside an override would never load.
pi_claude_home="${work}/pi-claude-home"
mkdir -p "${pi_claude_home}/.pi/agent"
printf 'user pi claude\n' >"${pi_claude_home}/.pi/agent/CLAUDE.md"
HOME="${pi_claude_home}" XDG_CONFIG_HOME="${pi_claude_home}/.config" PATH="${test_path}" \
	"${root}/install.sh" --agent pi --configure-only >/dev/null 2>&1
[ ! -e "${pi_claude_home}/.pi/agent/AGENTS.md" ]
rg -q '^user pi claude$' "${pi_claude_home}/.pi/agent/CLAUDE.md"
rg -q '^Tool routing' "${pi_claude_home}/.pi/agent/CLAUDE.md"
pi_override_home="${work}/pi-override-home"
mkdir -p "${pi_override_home}/.pi/agent"
printf 'user pi agents\n' >"${pi_override_home}/.pi/agent/AGENTS.md"
printf 'user pi override\n' >"${pi_override_home}/.pi/agent/AGENTS.override.md"
HOME="${pi_override_home}" XDG_CONFIG_HOME="${pi_override_home}/.config" PATH="${test_path}" \
	"${root}/install.sh" --agent pi --configure-only >/dev/null 2>&1
rg -q '^Tool routing' "${pi_override_home}/.pi/agent/AGENTS.override.md"
[ "$(cat "${pi_override_home}/.pi/agent/AGENTS.md")" = 'user pi agents' ]

# Auto-detection finds an npx-only DeepSeek Harness by its home directory, and an
# Antigravity desktop install by the directory CodeGraph also detects. No agent
# command is on PATH; a machine's own apps may still add agents to the receipt.
detect_bin="${work}/detect-bin"
mkdir -p "${detect_bin}"
cp "${fake_bin}/rtk" "${detect_bin}/rtk"
ln -s "$(command -v jq)" "${detect_bin}/jq"
detect_home="${work}/detect-home"
mkdir -p "${detect_home}/.dsh" "${detect_home}/.gemini/antigravity"
HOME="${detect_home}" XDG_CONFIG_HOME="${detect_home}/.config" \
	PATH="${detect_bin}:${base_bin}" "${root}/install.sh" --configure-only >/dev/null 2>&1
rg -q '^Tool routing' "${detect_home}/.dsh/AGENTS.md"
rg -q '^Tool routing' "${detect_home}/.gemini/GEMINI.md"
rg -q '^configured=antigravity,.*dsh' "${detect_home}/.config/agent-ready/receipt"

# An existing rtk may predate these integrations, and installs do not upgrade it.
# The routing block is still written and the run still succeeds.
old_rtk_bin="${work}/old-rtk-bin"
mkdir -p "${old_rtk_bin}"
cat >"${old_rtk_bin}/rtk" <<'EOF'
#!/bin/sh
printf "error: invalid value for '--agent'\n" >&2
exit 2
EOF
chmod +x "${old_rtk_bin}/rtk"
old_rtk_home="${work}/old-rtk-home"
mkdir -p "${old_rtk_home}"
HOME="${old_rtk_home}" XDG_CONFIG_HOME="${old_rtk_home}/.config" \
	PATH="${old_rtk_bin}:${test_path}" "${root}/install.sh" --agent antigravity,pi --configure-only \
	>"${work}/old-rtk.out" 2>&1
rg -qF 'Pi: RTK integration failed' "${work}/old-rtk.out"
rg -qF 'Google Antigravity: RTK integration failed' "${work}/old-rtk.out"
rg -q '^Tool routing' "${old_rtk_home}/.pi/agent/AGENTS.md"
rg -q '^Tool routing' "${old_rtk_home}/.gemini/GEMINI.md"

# Uninstall names the agent that configured the shared file and gives the RTK
# commands that actually remove these integrations. A Gemini-only install must
# not report Antigravity at all.
agy_home="${work}/agy-home"
mkdir -p "${agy_home}/.gemini"
printf 'user gemini\n' >"${agy_home}/.gemini/GEMINI.md"
run_uninstall_checkout_install "${agy_home}" --agent antigravity,pi >/dev/null 2>&1
run_uninstall_checkout "${agy_home}" >"${work}/agy-uninstall.out" 2>&1
[ "$(cat "${agy_home}/.gemini/GEMINI.md")" = 'user gemini' ]
rg -qF 'rtk init -g --agent antigravity --uninstall' "${work}/agy-uninstall.out"
rg -qF 'rtk init -g --agent pi --uninstall' "${work}/agy-uninstall.out"
if rg -q '^Gemini CLI:' "${work}/agy-uninstall.out"; then
	printf 'uninstall reported Gemini CLI for an Antigravity-only file\n' >&2
	exit 1
fi
gemini_only_home="${work}/gemini-only-home"
mkdir -p "${gemini_only_home}/.gemini"
run_uninstall_checkout_install "${gemini_only_home}" --agent gemini >/dev/null 2>&1
run_uninstall_checkout "${gemini_only_home}" >"${work}/gemini-only-uninstall.out" 2>&1
rg -q '^Gemini CLI:' "${work}/gemini-only-uninstall.out"
if rg -q 'Antigravity|antigravity' "${work}/gemini-only-uninstall.out"; then
	printf 'uninstall reported Antigravity for a Gemini-only file\n' >&2
	exit 1
fi

# --- regressions from the v1.5.0 audit ------------------------------------------
regression_install() {
	local home="$1"
	shift
	HOME="${home}" XDG_CONFIG_HOME="${home}/.config" XDG_DATA_HOME="${home}/.local/share" \
		CODEX_HOME="${home}/.codex" PATH="${test_path}" "${root}/install.sh" "$@"
}
has_no_block() { [ ! -f "$1" ] || ! rg -qF 'agent-ready:start' "$1"; }
stale_block() { printf '<!-- agent-ready:start -->\nold\n<!-- agent-ready:end -->\n' >"$1"; }

# A block written where the agent no longer reads it moves to the file it does.
relocated_home="${work}/relocated-home"
mkdir -p "${relocated_home}/.cline/data/settings/rules" "${relocated_home}/.codeium/windsurf/memories" "${relocated_home}/.devin"
stale_block "${relocated_home}/.cline/data/settings/rules/agent-ready.md"
stale_block "${relocated_home}/.codeium/windsurf/memories/global_rules.md"
regression_install "${relocated_home}" --agent cline,windsurf --configure-only >/dev/null 2>&1
rg -q '^Tool routing' "${relocated_home}/.cline/rules/agent-ready.md"
rg -q '^Tool routing' "${relocated_home}/.devin/global_rules.md"
has_no_block "${relocated_home}/.cline/data/settings/rules/agent-ready.md"
has_no_block "${relocated_home}/.codeium/windsurf/memories/global_rules.md"

# A machine with only the older Windsurf app stays on the file that app reads.
old_windsurf_home="${work}/old-windsurf-home"
mkdir -p "${old_windsurf_home}/.codeium/windsurf"
regression_install "${old_windsurf_home}" --agent windsurf --configure-only >/dev/null 2>&1
rg -q '^Tool routing' "${old_windsurf_home}/.codeium/windsurf/memories/global_rules.md"
[ ! -e "${old_windsurf_home}/.devin" ]

# A Pi override appearing after install: uninstall still finds the first block,
# and a reinstall moves it instead of leaving two.
pi_late_home="${work}/pi-late-home"
regression_install "${pi_late_home}" --agent pi --configure-only >/dev/null 2>&1
printf 'user pi override\n' >"${pi_late_home}/.pi/agent/AGENTS.override.md"
run_uninstall_checkout "${pi_late_home}" >/dev/null 2>&1
has_no_block "${pi_late_home}/.pi/agent/AGENTS.md"
[ "$(cat "${pi_late_home}/.pi/agent/AGENTS.override.md")" = 'user pi override' ]
pi_move_home="${work}/pi-move-home"
regression_install "${pi_move_home}" --agent pi --configure-only >/dev/null 2>&1
printf 'user pi override\n' >"${pi_move_home}/.pi/agent/AGENTS.override.md"
regression_install "${pi_move_home}" --agent pi --configure-only >/dev/null 2>&1
has_no_block "${pi_move_home}/.pi/agent/AGENTS.md"
rg -q '^Tool routing' "${pi_move_home}/.pi/agent/AGENTS.override.md"

# Local edits in a block about to move stop the run before anything is written.
pi_edit_home="${work}/pi-edit-home"
regression_install "${pi_edit_home}" --agent pi --configure-only >/dev/null 2>&1
awk -v e='<!-- agent-ready:end -->' '$0 == e { print "local edit" } { print }' \
	"${pi_edit_home}/.pi/agent/AGENTS.md" >"${work}/pi-edit" && cp "${work}/pi-edit" "${pi_edit_home}/.pi/agent/AGENTS.md"
printf 'user pi override\n' >"${pi_edit_home}/.pi/agent/AGENTS.override.md"
if regression_install "${pi_edit_home}" --agent pi --configure-only >"${work}/pi-edit.out" 2>&1; then
	printf 'install moved a block with local edits\n' >&2
	exit 1
fi
[ "$(cat "${pi_edit_home}/.pi/agent/AGENTS.override.md")" = 'user pi override' ]

# Codex reads a non-empty override instead of AGENTS.md, and CodeGraph's section
# in AGENTS.md is hidden with it, so the block keeps its own Code graph line.
codex_override_home="${work}/codex-override-home"
mkdir -p "${codex_override_home}/.codex"
printf 'user override\n' >"${codex_override_home}/.codex/AGENTS.override.md"
regression_install "${codex_override_home}" --agent codex --configure-only >/dev/null 2>&1
rg -q '^Tool routing' "${codex_override_home}/.codex/AGENTS.override.md"
rg -qF 'Code graph:' "${codex_override_home}/.codex/AGENTS.override.md"
has_no_block "${codex_override_home}/.codex/AGENTS.md"
codex_empty_home="${work}/codex-empty-home"
mkdir -p "${codex_empty_home}/.codex"
: >"${codex_empty_home}/.codex/AGENTS.override.md"
regression_install "${codex_empty_home}" --agent codex --configure-only >/dev/null 2>&1
rg -q '^Tool routing' "${codex_empty_home}/.codex/AGENTS.md"
[ ! -s "${codex_empty_home}/.codex/AGENTS.override.md" ]

# CRLF markers, and a directory where a file belongs, stop before any write; a
# dangling legacy Cursor link is simply not a legacy block.
crlf_home="${work}/crlf-home"
regression_install "${crlf_home}" --agent qwen --configure-only >/dev/null 2>&1
awk '{ printf "%s\r\n", $0 }' "${crlf_home}/.qwen/QWEN.md" >"${work}/crlf" && cp "${work}/crlf" "${crlf_home}/.qwen/QWEN.md"
if regression_install "${crlf_home}" --agent qwen --configure-only >/dev/null 2>&1; then
	printf 'install accepted CRLF agent-ready markers\n' >&2
	exit 1
fi
[ "$(rg -cF 'agent-ready:start' "${crlf_home}/.qwen/QWEN.md")" -eq 1 ]
directory_home="${work}/directory-home"
mkdir -p "${directory_home}/.qwen/QWEN.md"
if regression_install "${directory_home}" --agent qwen --configure-only --dry-run >"${work}/directory.out" 2>&1; then
	printf 'dry run accepted a directory as an instruction file\n' >&2
	exit 1
fi
rg -qF 'not a regular file' "${work}/directory.out"
dangling_home="${work}/dangling-home"
mkdir -p "${dangling_home}/.cursor"
ln -s "${dangling_home}/nowhere" "${dangling_home}/.cursor/AGENTS.md"
regression_install "${dangling_home}" --agent cursor --configure-only --dry-run >/dev/null 2>&1

# Merging a user's config keeps its mode, and a dotfiles symlink stays a symlink.
mode_home="${work}/mode-home"
mkdir -p "${mode_home}/.cursor" "${mode_home}/dotfiles"
printf '{"version":1,"hooks":{}}\n' >"${mode_home}/.cursor/hooks.json"
printf '{"mcpServers":{"mine":{"command":"mine"}}}\n' >"${mode_home}/dotfiles/mcp.json"
ln -s "${mode_home}/dotfiles/mcp.json" "${mode_home}/.cursor/mcp.json"
chmod 644 "${mode_home}/.cursor/hooks.json" "${mode_home}/dotfiles/mcp.json"
regression_install "${mode_home}" --agent cursor --configure-only >/dev/null 2>&1
HOME="${mode_home}" XDG_CONFIG_HOME="${mode_home}/.config" PATH="${test_path}" \
	"${root}/languages/go/install.sh" --agent cursor --configure-only >/dev/null 2>&1
[ -n "$(find "${mode_home}/.cursor/hooks.json" -perm 644)" ]
[ -n "$(find "${mode_home}/dotfiles/mcp.json" -perm 644)" ]
[ -L "${mode_home}/.cursor/mcp.json" ]
jq -e '.mcpServers.gopls and .mcpServers.mine' "${mode_home}/dotfiles/mcp.json" >/dev/null

# Go support without --agent stays with the agents an explicit install named.
go_explicit_home="${work}/go-explicit-home"
mkdir -p "${go_explicit_home}"
regression_install "${go_explicit_home}" --agent claude --configure-only >/dev/null 2>&1
HOME="${go_explicit_home}" XDG_CONFIG_HOME="${go_explicit_home}/.config" PATH="${test_path}" \
	"${root}/languages/go/install.sh" --configure-only >/dev/null 2>&1
rg -qx 'agents=claude' "${go_explicit_home}/.config/agent-ready/receipt"
rg -qx 'languages=go' "${go_explicit_home}/.config/agent-ready/receipt"
[ ! -e "${go_explicit_home}/.codex/AGENTS.md" ]
[ ! -e "${go_explicit_home}/.cursor/mcp.json" ]
rg -qF 'use gopls where compiler semantics matter' "${go_explicit_home}/.claude/CLAUDE.md"

# A release-binaries install keeps that tool mode when Homebrew appears later.
tools_mode_home="${work}/tools-mode-home"
mkdir -p "${tools_mode_home}/.config/agent-ready"
printf 'schema=1\nversion=v9.9.0\nagents=qwen\nconfigured=qwen\nlanguages=\ntools=binaries\nupdated_at=2026-11-01T00:00:00Z\n' \
	>"${tools_mode_home}/.config/agent-ready/receipt"
HOME="${tools_mode_home}" XDG_CONFIG_HOME="${tools_mode_home}/.config" PATH="${update_bin}:${test_path}" \
	AGENT_READY_OS=Linux AGENT_READY_ARCH=x86_64 AGENT_READY_GITHUB_API="file://${gh_api}" \
	bash "${root}/agent-ready" apply-update --from v9.9.0 >/dev/null 2>&1
[ ! -e "${tools_mode_home}/brew-calls" ]
rg -qx 'tools=binaries' "${tools_mode_home}/.config/agent-ready/receipt"

# A failed release-notes request does not turn a finished update into an error.
notes_home="${work}/notes-home"
notes_bins="${work}/notes-launcher-bin"
notes_bin="${work}/notes-bin"
mkdir -p "${notes_home}" "${notes_bins}" "${notes_bin}"
cat >"${notes_bin}/curl" <<EOF
#!/usr/bin/env bash
case "\$*" in
*/releases/tags/v9.9.1*)
	count=\$((\$(cat "\${HOME}/notes-count" 2>/dev/null || printf 0) + 1))
	printf '%s' "\${count}" >"\${HOME}/notes-count"
	if [ "\${count}" -gt 1 ]; then printf 'curl: (7) unreachable\n' >&2; exit 7; fi
	;;
esac
exec "${update_bin}/curl" "\$@"
EOF
chmod +x "${notes_bin}/curl"
run_release "${notes_home}" "${notes_bins}" v9.9.0 "${base_bin}" --agent codex --configure-only >/dev/null
saved_update_path="${update_path}"
update_path="${notes_bin}:${update_path}"
run_update "${notes_home}" "${notes_bins}" 0 v9.9.1 >"${work}/notes.out" 2>&1
update_path="${saved_update_path}"
rg -qF 'Start a new agent session' "${work}/notes.out"
rg -qx 'version=v9.9.1' "${notes_home}/.config/agent-ready/receipt"

# A dry run through the verified bootstrap path writes nothing, and the flag works
# as the first argument too.
self_dry_home="${work}/self-dry-home"
mkdir -p "${self_dry_home}"
HOME="${self_dry_home}" XDG_CONFIG_HOME="${self_dry_home}/.config" XDG_DATA_HOME="${self_dry_home}/.local/share" \
	PATH="${test_path}" bash "${root}/agent-ready" --self-install --agent qwen --configure-only --dry-run >/dev/null 2>&1
[ ! -e "${self_dry_home}/.local" ]
HOME="${self_dry_home}" XDG_CONFIG_HOME="${self_dry_home}/.config" XDG_DATA_HOME="${self_dry_home}/.local/share" \
	PATH="${test_path}" bash "${root}/agent-ready" --dry-run --agent qwen --configure-only >/dev/null 2>&1
[ ! -e "${self_dry_home}/.qwen" ]

# Migrations run in version order across a major version.
order_home="${work}/order-home"
order_tree="${work}/order-tree"
mkdir -p "${order_home}"
cp -R "${root}" "${order_tree}"
printf 'v2.0.0\n' >"${order_tree}/VERSION"
for migration in v1.9.0-a v1.10.0-b v2.0.0-c; do
	# shellcheck disable=SC2016 # ${HOME} belongs to the generated script
	printf '#!/bin/sh\nprintf "%%s\\n" %s >>"${HOME}/migrations"\n' "${migration}" >"${order_tree}/migrations/${migration}.sh"
	chmod +x "${order_tree}/migrations/${migration}.sh"
done
regression_install "${order_home}" --agent qwen --configure-only >/dev/null 2>&1
HOME="${order_home}" XDG_CONFIG_HOME="${order_home}/.config" PATH="${test_path}" \
	bash "${order_tree}/agent-ready" apply-update --from v1.8.0 >/dev/null 2>&1
[ "$(tr '\n' ' ' <"${order_home}/migrations")" = 'v1.9.0-a v1.10.0-b v2.0.0-c ' ]

# Rollback to a release whose strict receipt reader rejects a newer agent: this
# stand-in fails the way v1.4.1 does on a receipt or --agent naming pi.
rollback_new_home="${work}/rollback-new-home"
rollback_old_tree="${rollback_new_home}/.local/share/agent-ready/versions/v1.4.1"
rollback_receipt="${rollback_new_home}/.config/agent-ready/receipt"
mkdir -p "${rollback_old_tree}" "${rollback_new_home}/.config/agent-ready"
cat >"${rollback_old_tree}/install.sh" <<'EOF'
#!/usr/bin/env bash
if grep -q 'pi' "${HOME}/.config/agent-ready/receipt" || [ -e "${HOME}/old-release-fails" ]; then
	exit 1
fi
printf '%s\n' "$*" >"${HOME}/old-release-args"
EOF
write_rollback_receipt() {
	printf 'schema=1\nversion=v1.5.0\nagents=%s\nconfigured=%s\nlanguages=\ntools=none\nupdated_at=2026-11-01T00:00:00Z\n' \
		"$1" "$2" >"${rollback_receipt}"
}
run_rollback_new() {
	HOME="${rollback_new_home}" XDG_CONFIG_HOME="${rollback_new_home}/.config" \
		XDG_DATA_HOME="${rollback_new_home}/.local/share" \
		AGENT_READY_BIN_DIR="${rollback_new_home}/bin" PATH="${test_path}" \
		bash "${root}/agent-ready" rollback
}
write_rollback_receipt pi pi
if run_rollback_new >/dev/null 2>&1; then
	printf 'rollback to a release that supports none of the agents succeeded\n' >&2
	exit 1
fi
rg -qx 'agents=pi' "${rollback_receipt}"
write_rollback_receipt claude,pi claude,pi
touch "${rollback_new_home}/old-release-fails"
if run_rollback_new >/dev/null 2>&1; then
	printf 'rollback ignored a failing older installer\n' >&2
	exit 1
fi
rm "${rollback_new_home}/old-release-fails"
rg -qx 'agents=claude,pi' "${rollback_receipt}"
[ ! -e "${rollback_new_home}/bin/agent-ready" ]
write_rollback_receipt claude,pi claude,pi
run_rollback_new >/dev/null 2>&1
[ "$(cat "${rollback_new_home}/old-release-args")" = '--configure-only --agent claude' ]
rg -qx 'configured=claude' "${rollback_receipt}"
[ "$(readlink "${rollback_new_home}/bin/agent-ready")" = "${rollback_old_tree}/agent-ready" ]

# A named downgrade narrows the receipt the same way, restores it when the release
# cannot be installed, and a dry run changes nothing.
publish_agent_ready v1.4.1 v1.4.1 "$(stamp_ago 48)"
downgrade_home="${work}/downgrade-home"
downgrade_bins="${work}/downgrade-launcher-bin"
downgrade_receipt="${downgrade_home}/.config/agent-ready/receipt"
mkdir -p "${downgrade_home}" "${downgrade_bins}"
run_release "${downgrade_home}" "${downgrade_bins}" v9.9.0 "${base_bin}" --agent claude,pi --configure-only >/dev/null
run_update "${downgrade_home}" "${downgrade_bins}" 0 --dry-run v1.4.1 >"${work}/downgrade.out" 2>&1
rg -qx 'agents=claude,pi' "${downgrade_receipt}"
rg -qF 'nothing changed' "${work}/downgrade.out"
if run_update "${downgrade_home}" "${downgrade_bins}" 0 v1.0.1 >/dev/null 2>&1; then
	printf 'update to an unpublished release succeeded\n' >&2
	exit 1
fi
rg -qx 'agents=claude,pi' "${downgrade_receipt}"
run_update "${downgrade_home}" "${downgrade_bins}" 0 v1.4.1 >/dev/null 2>&1
rg -qx 'agents=claude' "${downgrade_receipt}"
rg -qx 'version=v1.4.1' "${downgrade_receipt}"

# --upgrade keeps a launcher the user replaced, even with the state file left over.
owned_home="${work}/owned-home"
mkdir -p "${owned_home}/.local/bin" "${owned_home}/.config/agent-ready"
printf 'v1\n' >"${owned_home}/.config/agent-ready/codegraph"
printf '#!/bin/sh\necho user-owned\n' >"${owned_home}/.local/bin/codegraph"
HOME="${owned_home}" XDG_CONFIG_HOME="${owned_home}/.config" XDG_DATA_HOME="${owned_home}/.local/share" \
	PATH="${update_bin}:${test_path}" AGENT_READY_OS=Linux AGENT_READY_ARCH=x86_64 \
	AGENT_READY_GITHUB_API="file://${gh_api}" "${root}/install-codegraph.sh" --upgrade >/dev/null 2>&1
rg -qx 'echo user-owned' "${owned_home}/.local/bin/codegraph"

# Uninstall names every RTK integration that needs its own command, keeps the
# binaries state while osv-scanner remains, and claims no codegraph or timeout it
# did not link.
hints_home="${work}/hints-home"
mkdir -p "${hints_home}/.gemini" "${hints_home}/.local/bin"
run_uninstall_checkout_install "${hints_home}" --agent codex,gemini,copilot >/dev/null 2>&1
printf 'osv-scanner v2\n' >"${hints_home}/.config/agent-ready/binaries"
touch "${hints_home}/.local/bin/osv-scanner"
ln -s /usr/local/lib/user-codegraph "${hints_home}/.local/bin/codegraph"
ln -s /opt/homebrew/bin/gtimeout "${hints_home}/.local/bin/timeout"
run_uninstall_checkout "${hints_home}" >"${work}/hints.out" 2>&1
rg -qF 'rtk init -g --codex --uninstall' "${work}/hints.out"
rg -qF 'rtk init -g --gemini --uninstall' "${work}/hints.out"
rg -qF 'rtk init -g --copilot --uninstall' "${work}/hints.out"
rg -qF 'timeout link: rm ' "${work}/hints.out"
[ -f "${hints_home}/.config/agent-ready/binaries" ]
if rg -qF 'codegraph bundle:' "${work}/hints.out"; then
	printf 'uninstall offered to remove a codegraph it does not own\n' >&2
	exit 1
fi

# The GitHub token reaches curl on stdin, never in its arguments, and only for the
# real API.
token_home="${work}/token-home"
token_bin="${work}/token-bin"
mkdir -p "${token_home}" "${token_bin}"
cat >"${token_bin}/curl" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${HOME}/curl-args"
cat >>"${HOME}/curl-stdin"
printf 200
EOF
chmod +x "${token_bin}/curl"
HOME="${token_home}" XDG_CONFIG_HOME="${token_home}/.config" XDG_DATA_HOME="${token_home}/.local/share" \
	PATH="${token_bin}:${test_path}" GITHUB_TOKEN=synthetic-value "${root}/install-codegraph.sh" </dev/null >/dev/null 2>&1 || true
rg -qF 'api.github.com' "${token_home}/curl-args"
rg -qF 'Authorization: Bearer synthetic-value' "${token_home}/curl-stdin"
if rg -qF 'synthetic-value' "${token_home}/curl-args"; then
	printf 'the GitHub token was passed in curl arguments\n' >&2
	exit 1
fi
rm "${token_home}/curl-args" "${token_home}/curl-stdin"
HOME="${token_home}" XDG_CONFIG_HOME="${token_home}/.config" XDG_DATA_HOME="${token_home}/.local/share" \
	PATH="${token_bin}:${test_path}" GITHUB_TOKEN=synthetic-value AGENT_READY_GITHUB_API=https://example.invalid \
	"${root}/install-codegraph.sh" </dev/null >/dev/null 2>&1 || true
if rg -qF 'synthetic-value' "${token_home}/curl-stdin"; then
	printf 'the GitHub token was sent to an API override\n' >&2
	exit 1
fi

printf 'installer routing checks passed\n'
