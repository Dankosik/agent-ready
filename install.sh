#!/usr/bin/env bash

set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)

# Assigned by lib/receipt.sh when a receipt is read.
receipt_agents=
receipt_configured=
receipt_tools=
# shellcheck source=lib/receipt.sh
# shellcheck disable=SC1091
. "${root}/lib/receipt.sh"

agent=auto
install_tools=1
upgrade_tools=0
binaries=0
force=0
dry_run=0
usage() {
	printf 'usage: %s [--agent auto|claude|codex|cursor|gemini|copilot|windsurf|grok|opencode|qwen|cline|kilo|crush|goose|<name>,...] [--configure-only|--upgrade] [--binaries] [--force] [--dry-run]\n' "$0" >&2
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	--agent)
		[ "$#" -ge 2 ] || { usage; exit 2; }
		agent="$2"
		shift 2
		;;
	--configure-only)
		install_tools=0
		shift
		;;
	--upgrade)
		upgrade_tools=1
		shift
		;;
	--binaries)
		binaries=1
		shift
		;;
	--force)
		force=1
		shift
		;;
	--dry-run)
		dry_run=1
		shift
		;;
	*)
		usage
		exit 2
		;;
	esac
done

[ "${install_tools}" -eq 1 ] || { [ "${upgrade_tools}" -eq 0 ] && [ "${binaries}" -eq 0 ]; } || { usage; exit 2; }
[ "${dry_run}" -eq 0 ] || { [ "${upgrade_tools}" -eq 0 ] && [ "${binaries}" -eq 0 ]; } || { usage; exit 2; }

# One name or a comma list, and every alias a selector list accepts resolves to
# the canonical id used in blocks, receipts, and CodeGraph targets.
normalise_agent() {
	case "$1" in
	claude-code) printf 'claude\n' ;;
	cursor-agent) printf 'cursor\n' ;;
	gemini-cli) printf 'gemini\n' ;;
	github-copilot) printf 'copilot\n' ;;
	grok-build) printf 'grok\n' ;;
	open-code) printf 'opencode\n' ;;
	qwen-code) printf 'qwen\n' ;;
	kilocode | kilo-code) printf 'kilo\n' ;;
	claude | codex | cursor | gemini | copilot | windsurf | grok | opencode | qwen | cline | kilo | crush | goose)
		printf '%s\n' "$1"
		;;
	*) return 1 ;;
	esac
}

# The header written into every managed block, and the receipt, name the
# release that wrote them, so an update knows what it is replacing.
version_file="${root}/VERSION"
[ -f "${version_file}" ] || {
	printf 'missing %s\n' "${version_file}" >&2
	exit 1
}
version=$(cat "${version_file}")
[[ "${version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
	printf 'invalid version in %s: %s\n' "${version_file}" "${version}" >&2
	exit 1
}

os="${AGENT_READY_OS:-$(uname -s)}"

start='<!-- agent-ready:start -->'
end='<!-- agent-ready:end -->'

agent_label() {
	case "$1" in
	claude) printf 'Claude Code' ;;
	codex) printf 'Codex' ;;
	cursor) printf 'Cursor' ;;
	gemini) printf 'Gemini CLI' ;;
	copilot) printf 'GitHub Copilot CLI' ;;
	windsurf) printf 'Windsurf' ;;
	grok) printf 'Grok Build' ;;
	opencode) printf 'OpenCode' ;;
	qwen) printf 'Qwen Code' ;;
	cline) printf 'Cline CLI' ;;
	kilo) printf 'Kilo Code' ;;
	crush) printf 'Crush' ;;
	goose) printf 'goose' ;;
	esac
}

agent_instructions() {
	case "$1" in
	claude) printf '%s\n' "${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/CLAUDE.md" ;;
	codex) printf '%s\n' "${CODEX_HOME:-${HOME}/.codex}/AGENTS.md" ;;
	gemini) printf '%s\n' "${HOME}/.gemini/GEMINI.md" ;;
	copilot) printf '%s\n' "${COPILOT_HOME:-${HOME}/.copilot}/copilot-instructions.md" ;;
	windsurf) printf '%s\n' "${HOME}/.codeium/windsurf/memories/global_rules.md" ;;
	grok) printf '%s\n' "${GROK_HOME:-${HOME}/.grok}/rules/agent-ready.md" ;;
	opencode) printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/opencode/AGENTS.md" ;;
	qwen) printf '%s\n' "${QWEN_HOME:-${HOME}/.qwen}/QWEN.md" ;;
	cline) printf '%s\n' "${CLINE_DATA_DIR:-${HOME}/.cline/data}/settings/rules/agent-ready.md" ;;
	kilo) printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/kilo/AGENTS.md" ;;
	crush) printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/crush/CRUSH.md" ;;
	goose) printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/goose/AGENTS.md" ;;
	esac
}

# `codegraph install` writes its own CodeGraph section into these four agents'
# files, so their agent-ready block leaves out the Code graph line.
agent_block() {
	case "$1" in
	claude | codex | gemini | opencode) printf '%s\n' "${graph_routing}" ;;
	*) printf '%s\n' "${routing}" ;;
	esac
}

# On Linux the tools come from upstream release binaries unless Homebrew is
# already there; --binaries chooses them even then. macOS always uses Homebrew.
detect_claude() { command -v claude >/dev/null 2>&1; }
detect_codex() { command -v codex >/dev/null 2>&1; }
detect_cursor() {
	command -v cursor >/dev/null 2>&1 || command -v cursor-agent >/dev/null 2>&1 ||
		[ -d /Applications/Cursor.app ] || [ -d "${HOME}/Applications/Cursor.app" ]
}
detect_gemini() { command -v gemini >/dev/null 2>&1; }
detect_copilot() { command -v copilot >/dev/null 2>&1; }
detect_windsurf() {
	command -v windsurf >/dev/null 2>&1 ||
		[ -d /Applications/Windsurf.app ] || [ -d "${HOME}/Applications/Windsurf.app" ]
}
detect_grok() { command -v grok >/dev/null 2>&1; }
detect_opencode() { command -v opencode >/dev/null 2>&1; }
detect_qwen() { command -v qwen >/dev/null 2>&1; }
detect_cline() { command -v cline >/dev/null 2>&1; }
detect_kilo() { command -v kilo >/dev/null 2>&1; }
detect_crush() { command -v crush >/dev/null 2>&1; }
detect_goose() { command -v goose >/dev/null 2>&1; }

agent_ids="claude codex cursor gemini copilot windsurf grok opencode qwen cline kilo crush goose"
auto_detection=0
selected_agents=
# The canonical comma list of this run's explicit agents, in the order given.
agents_csv=
if [ "${agent}" = auto ]; then
	auto_detection=1
	for id in ${agent_ids}; do
		if "detect_${id}"; then
			selected_agents="${selected_agents} ${id}"
		fi
	done
else
	# --agent may name a comma list. Every item stands on its own: empty items,
	# auto inside a list, and unknown names are usage errors, and repeats count
	# once so the receipt and CodeGraph targets stay stable.
	rest="${agent},"
	while [ -n "${rest}" ]; do
		item="${rest%%,*}"
		rest="${rest#*,}"
		[ -n "${item}" ] || { usage; exit 2; }
		[ "${item}" != auto ] || { usage; exit 2; }
		item=$(normalise_agent "${item}") || { usage; exit 2; }
		case " ${selected_agents} " in
		*" ${item} "*) continue ;;
		esac
		selected_agents="${selected_agents} ${item}"
		[ -z "${agents_csv}" ] || agents_csv="${agents_csv},"
		agents_csv="${agents_csv}${item}"
	done
fi

agent_selected() {
	case " ${selected_agents} " in
	*" $1 "*) return 0 ;;
	esac
	return 1
}

resolve_target() {
	local path="$1" link dir hops=0
	while [ -L "${path}" ]; do
		hops=$((hops + 1))
		[ "${hops}" -le 20 ] || {
			printf 'too many symlinks while resolving %s\n' "$1" >&2
			return 1
		}
		link=$(readlink "${path}")
		case "${link}" in
		/*) path="${link}" ;;
		*)
			dir=$(cd -- "$(dirname -- "${path}")" && pwd -P)
			path="${dir}/${link}"
			;;
		esac
	done
	printf '%s\n' "${path}"
}

block_state() {
	awk -v s="${start}" -v e="${end}" '
		$0 == s { starts++; start_line = NR }
		$0 == e { ends++; end_line = NR }
		END {
			if (starts == 0 && ends == 0) print "absent"
			else if (starts == 1 && ends == 1 && start_line < end_line) print "present"
			else print "invalid"
		}
	' "$1"
}

block_first_line() {
	awk -v s="${start}" -v e="${end}" '
		$0 == s { inside = 1; next }
		$0 == e { exit }
		inside { print; exit }
	' "$1"
}

# The body is emitted one newline per line, so an unterminated last line in a
# routing file still produces the bytes that are written and hashed here.
block_body() {
	awk '{ print }' "$1"
}

# The block body is everything after the header line, each line newline
# terminated, which is exactly what install_block writes.
block_body_hash() {
	awk -v s="${start}" -v e="${end}" '
		$0 == s { inside = 1; first = 1; next }
		$0 == e { exit }
		inside {
			if (first) first = 0
			else print
		}
	' "$1" | sha256_stdin
}

block_has_header() {
	printf '%s\n' "$1" | grep -Eq '^<!-- agent-ready v[^ ]+ sha256:[0-9a-f]{64} -->$'
}

sha256_stdin() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum | cut -d' ' -f1
	else
		shasum -a 256 | cut -d' ' -f1
	fi
}

merge_lists() {
	tr ',' '\n' | awk 'NF' | sort -u | join_lines
}

join_lines() {
	awk 'BEGIN { ORS = "" } NR > 1 { printf "," } { print }'
}

preflight_report() {
	[ "${dry_run}" -eq 0 ] || printf '%s: %s %s\n' "$1" "$2" "$3"
}

# Every problem is reported, not just the first; the run stops before any
# write once the selected agents have all been checked.
preflight_blocked() {
	local label="$1" requested="$2" kind="$3" reason="$4"
	blocked=$((blocked + 1))
	case "${kind}" in
	markers)
		printf '%s: malformed agent-ready markers in %s\n' "${label}" "${requested}" >&2
		reason="malformed agent-ready markers"
		;;
	edits)
		printf '%s: %s has local edits inside the agent-ready block; move them outside the markers or rerun with --force\n' \
			"${label}" "${requested}" >&2
		reason="local edits inside the agent-ready block"
		;;
	*)
		printf '%s: %s: %s\n' "${label}" "${requested}" "${reason}" >&2
		;;
	esac
	[ "${dry_run}" -eq 0 ] || printf '%s: blocked (%s) %s\n' "${label}" "${reason}" "${requested}"
}

preflight_instruction() {
	local label="$1" requested="$2" body="$3" target state header digest expected
	target=$(resolve_target "${requested}") || {
		preflight_blocked "${label}" "${requested}" other "unresolvable symlink"
		return 0
	}
	if [ ! -f "${target}" ]; then
		preflight_report "${label}" "would add" "${requested}"
		return 0
	fi
	state=$(block_state "${target}")
	case "${state}" in
	absent)
		preflight_report "${label}" "would add" "${requested}"
		;;
	invalid)
		preflight_blocked "${label}" "${requested}" markers ""
		;;
	present)
		header=$(block_first_line "${target}")
		expected="<!-- agent-ready ${version} sha256:$(block_body "${body}" | sha256_stdin) -->"
		if block_has_header "${header}"; then
			digest="${header#* sha256:}"
			digest="${digest%% -->*}"
			if [ "${digest}" != "$(block_body_hash "${target}")" ]; then
				if [ "${force}" -eq 1 ]; then
					preflight_report "${label}" "would refresh" "${requested}"
				else
					preflight_blocked "${label}" "${requested}" edits ""
				fi
				return 0
			fi
		fi
		if [ "${header}" = "${expected}" ]; then
			preflight_report "${label}" unchanged "${requested}"
		else
			preflight_report "${label}" "would refresh" "${requested}"
		fi
		;;
	esac
}

preflight_cursor() {
	local label="Cursor" cursor_dir="${HOME}/.cursor" requested legacy state=absent hooks response current=1
	requested="${cursor_dir}/hooks.json"
	legacy="${cursor_dir}/AGENTS.md"
	response="${cursor_dir}/hooks/agent-ready-session-start.json"
	if [ -e "${legacy}" ] || [ -L "${legacy}" ]; then
		state=$(block_state "${legacy}")
		[ "${state}" != invalid ] || preflight_blocked "${label}" "${legacy}" markers ""
	fi
	if [ ! -f "${requested}" ] && [ ! -L "${requested}" ]; then
		preflight_report "${label}" "would add" "${requested}"
		return 0
	fi
	command -v jq >/dev/null 2>&1 || {
		# A full run installs jq before configuring Cursor, so only a
		# configure-only run has to fail closed here.
		if [ "${install_tools}" -eq 1 ]; then
			preflight_report "${label}" "would refresh" "${requested}"
		else
			preflight_blocked "${label}" "${requested}" other "jq is required to merge hooks.json"
		fi
		return 0
	}
	hooks=$(resolve_target "${requested}")
	if ! jq -e -s '
		length == 1
		and (.[0] | type == "object")
		and (((.[0].hooks // {}).sessionStart // []) | type) == "array"
	' "${hooks}" >/dev/null 2>&1; then
		preflight_blocked "${label}" "${requested}" other "hooks.json must be a JSON object whose hooks.sessionStart is an array or absent"
		return 0
	fi
	# The run also retires a legacy AGENTS.md block and rewrites the hook
	# response, so both count as a change.
	if [ "${state}" = present ]; then current=0; fi
	if [ ! -f "${response}" ]; then current=0; fi
	if ! jq -e --arg command 'cat ./hooks/agent-ready-session-start.json' \
		'([.hooks.sessionStart[] | select(.command == $command)] | length) == 1' \
		"${hooks}" >/dev/null 2>&1; then
		current=0
	fi
	if [ "${current}" -eq 1 ] && ! cmp -s "${response}" <(jq -Rs '{additional_context: .}' "${routing}"); then
		current=0
	fi
	if [ "${current}" -eq 1 ]; then
		preflight_report "${label}" unchanged "${requested}"
	else
		preflight_report "${label}" "would refresh" "${requested}"
	fi
}

preflight_all() {
	local id
	for id in ${selected_agents}; do
		if [ "${id}" = cursor ]; then
			preflight_cursor
		else
			preflight_instruction "$(agent_label "${id}")" "$(agent_instructions "${id}")" "$(agent_block "${id}")"
		fi
	done
}

install_block() {
	local requested="$1" label="$2" block="${3:-${routing}}" target tmp state header
	mkdir -p "$(dirname -- "${requested}")"
	target=$(resolve_target "${requested}")
	mkdir -p "$(dirname -- "${target}")"
	[ -f "${target}" ] || : >"${target}"
	state=$(block_state "${target}")
	[ "${state}" != invalid ] || {
		printf '%s: malformed agent-ready markers in %s\n' "${label}" "${requested}" >&2
		return 1
	}
	header="<!-- agent-ready ${version} sha256:$(block_body "${block}" | sha256_stdin) -->"

	tmp=$(mktemp "${target}.XXXXXX") || return 1
	cp -p "${target}" "${tmp}"
	if [ "${state}" = present ]; then
		awk -v s="${start}" -v e="${end}" '
			$0 == s { print; exit }
			{ print }
		' "${target}" >"${tmp}"
		{
			printf '%s\n' "${header}"
			block_body "${block}"
			awk -v e="${end}" '
				found { print }
				$0 == e { found = 1; print }
			' "${target}"
		} >>"${tmp}"
	else
		{
			cat "${target}"
			[ -s "${target}" ] && printf '\n'
			printf '%s\n' "${start}"
			printf '%s\n' "${header}"
			block_body "${block}"
			printf '%s\n' "${end}"
		} >"${tmp}"
	fi
	if cmp -s "${target}" "${tmp}"; then
		rm -f "${tmp}"
		printf '%s: routing already configured in %s\n' "${label}" "${requested}"
		return 0
	fi
	mv "${tmp}" "${target}"
	printf '%s: %s routing block in %s\n' "${label}" "$([ "${state}" = present ] && printf refreshed || printf added)" "${requested}"
}

remove_block() {
	local requested="$1" label="$2" target tmp state
	[ -e "${requested}" ] || [ -L "${requested}" ] || return 0
	target=$(resolve_target "${requested}")
	[ -f "${target}" ] || return 0
	state=$(block_state "${target}")
	[ "${state}" != invalid ] || {
		printf '%s: malformed agent-ready markers in %s\n' "${label}" "${requested}" >&2
		return 1
	}
	[ "${state}" = present ] || return 0
	tmp=$(mktemp "${target}.XXXXXX") || return 1
	cp -p "${target}" "${tmp}"
	awk -v s="${start}" -v e="${end}" '
		$0 == s { skip = 1; next }
		$0 == e { skip = 0; next }
		!skip { print }
	' "${target}" >"${tmp}"
	mv "${tmp}" "${target}"
	printf '%s: removed legacy routing block from %s\n' "${label}" "${requested}"
}

configure_rtk() {
	local label="$1"
	shift
	rtk init "$@"
	printf '%s: configured RTK integration\n' "${label}"
}

install_cursor_hook() {
	local cursor_dir="${HOME}/.cursor" response hooks requested tmp command
	command -v jq >/dev/null 2>&1 || {
		printf 'Cursor: jq is required to merge hooks.json\n' >&2
		return 1
	}
	mkdir -p "${cursor_dir}/hooks"

	response="${cursor_dir}/hooks/agent-ready-session-start.json"
	tmp=$(mktemp "${response}.XXXXXX") || return 1
	jq -Rs '{additional_context: .}' "${routing}" >"${tmp}"
	if [ -f "${response}" ] && cmp -s "${response}" "${tmp}"; then
		rm -f "${tmp}"
	else
		mv "${tmp}" "${response}"
	fi

	requested="${cursor_dir}/hooks.json"
	hooks=$(resolve_target "${requested}")
	mkdir -p "$(dirname -- "${hooks}")"
	tmp=$(mktemp "${hooks}.XXXXXX") || return 1
	command='cat ./hooks/agent-ready-session-start.json'
	if [ -f "${hooks}" ]; then
		cp -p "${hooks}" "${tmp}"
		jq --arg command "${command}" '
			if type != "object" then error("hooks.json root must be an object") else . end
			| .hooks = (.hooks // {})
			| if ((.hooks.sessionStart // []) | type) != "array"
				then error("hooks.sessionStart must be an array") else . end
			| .version = (.version // 1)
			| .hooks.sessionStart = ([.hooks.sessionStart[]?
				| select((type != "object") or (.command != $command))]
				+ [{"command": $command}])
		' "${hooks}" >"${tmp}" || {
			rm -f "${tmp}"
			return 1
		}
	else
		jq -n --arg command "${command}" '{version: 1, hooks: {sessionStart: [{command: $command}]}}' >"${tmp}"
	fi
	if [ -f "${hooks}" ] && cmp -s "${hooks}" "${tmp}"; then
		rm -f "${tmp}"
		printf 'Cursor: routing hook already configured in %s\n' "${requested}"
	else
		chmod 600 "${tmp}"
		mv "${tmp}" "${hooks}"
		printf 'Cursor: configured routing hook in %s\n' "${requested}"
	fi

	remove_block "${cursor_dir}/AGENTS.md" "Cursor"
}

# CodeGraph's installer knows each agent's MCP config shape, including
# OpenCode 2's `mcp.servers` migration, so the wiring is delegated to it rather
# than reimplemented here. --no-permissions keeps it out of the agent's
# auto-allow list, and telemetry is turned off afterwards.
configure_codegraph() {
	local id target targets=
	command -v codegraph >/dev/null 2>&1 || return 0
	if [ "${auto_detection}" -eq 1 ]; then
		targets=auto
	else
		for id in ${selected_agents}; do
			case "${id}" in
			claude | codex | cursor | opencode | gemini) target="${id}" ;;
			copilot) target=copilot-cli ;;
			*)
				printf 'CodeGraph: MCP setup is not available for %s; the CLI routing still applies\n' "${id}" >&2
				target=
				;;
			esac
			[ -z "${target}" ] || targets="${targets}${targets:+,}${target}"
		done
	fi
	if [ -n "${targets}" ]; then
		codegraph install --yes --target="${targets}" --location=global --no-permissions ||
			printf 'CodeGraph: MCP setup failed; run codegraph install manually\n' >&2
	fi
	codegraph telemetry off >/dev/null 2>&1 ||
		printf 'CodeGraph: could not disable telemetry; run codegraph telemetry off\n' >&2
}

# Installing a tool is not the same as the agent using it. Measured on real
# session transcripts, an agent reaches for the command it already knows —
# `grep` over `rg`, `git worktree` over a wrapper — unless something tells it
# otherwise. This writes that "something" into each harness's instruction file,
# between markers, leaving everything else in the file untouched.

base_routing="${root}/agent-routing.md"
[ -f "${base_routing}" ] || {
	printf 'missing %s\n' "${base_routing}" >&2
	exit 1
}
routing="${base_routing}"
routing_tmp=
agent_ready_config="${XDG_CONFIG_HOME:-${HOME}/.config}/agent-ready"
if [ -f "${agent_ready_config}/languages/go" ]; then
	go_routing="${root}/languages/go/agent-routing.md"
	[ -f "${go_routing}" ] || {
		printf 'missing %s\n' "${go_routing}" >&2
		exit 1
	}
	routing_tmp=$(mktemp)
	{
		cat "${base_routing}"
		printf '\n'
		cat "${go_routing}"
	} >"${routing_tmp}"
	routing="${routing_tmp}"
fi
# The block is prepared before preflight, so it has to assume the CodeGraph
# install this run would perform: a real run installs or keeps it, and a
# dry run must describe the same block.
codegraph_available=0
if command -v codegraph >/dev/null 2>&1 || [ "${install_tools}" -eq 1 ]; then
	codegraph_available=1
fi
graph_routing="${routing}"
graph_routing_tmp=
if [ "${codegraph_available}" -eq 1 ]; then
	graph_routing_tmp=$(mktemp)
	grep -v '^- Code graph:' "${routing}" >"${graph_routing_tmp}"
	graph_routing="${graph_routing_tmp}"
fi
cleanup_routing() {
	[ -z "${routing_tmp}" ] || rm -f "${routing_tmp}"
	[ -z "${graph_routing_tmp}" ] || rm -f "${graph_routing_tmp}"
}
trap cleanup_routing EXIT

# A stale receipt must stop the run before any tool or agent is touched, and
# this run's receipt is built from the previous one.
receipt_file=$(receipt_path)
prev_agents=
prev_configured=
prev_tools=
blocked=0
if [ -f "${receipt_file}" ]; then
	receipt_read "${receipt_file}" || exit 1
	prev_agents="${receipt_agents}"
	prev_configured="${receipt_configured}"
	prev_tools="${receipt_tools}"
fi

preflight_all

if [ "${dry_run}" -eq 1 ]; then
	[ "${blocked}" -eq 0 ] || exit 1
	exit 0
fi
[ "${blocked}" -eq 0 ] || exit 1

tools_used=
if [ "${install_tools}" -eq 1 ] && [ "${os}" = Linux ] &&
	{ [ "${binaries}" -eq 1 ] || ! command -v brew >/dev/null 2>&1; }; then
	tools_used=binaries
	if [ "${upgrade_tools}" -eq 1 ]; then
		bash "${root}/install-binaries.sh" --upgrade
	else
		bash "${root}/install-binaries.sh"
	fi
	PATH="${AGENT_READY_BIN_DIR:-${HOME}/.local/bin}:${PATH}"
elif [ "${install_tools}" -eq 1 ]; then
	tools_used=brew
	[ "${binaries}" -eq 0 ] || {
		printf -- '--binaries is supported on Linux only; use Homebrew on %s\n' "${os}" >&2
		exit 2
	}
	command -v brew >/dev/null 2>&1 || {
		printf 'Homebrew is required: https://brew.sh\n' >&2
		exit 1
	}
	if [ "${upgrade_tools}" -eq 1 ]; then
		brew bundle --file "${root}/Brewfile"
	else
		brew bundle --no-upgrade --file "${root}/Brewfile"
	fi
fi

# CodeGraph publishes no Homebrew formula and ships one self-contained bundle per
# platform, so it comes from its release archive whichever way the other tools
# are installed. A copy this installer did not create (npm or upstream's own
# installer) is kept rather than replaced.
codegraph_state="${XDG_CONFIG_HOME:-${HOME}/.config}/agent-ready/codegraph"
if [ "${install_tools}" -eq 1 ]; then
	if command -v codegraph >/dev/null 2>&1 && [ ! -f "${codegraph_state}" ]; then
		printf 'codegraph: keeping the existing installation\n'
	elif command -v codegraph >/dev/null 2>&1 && [ "${upgrade_tools}" -eq 0 ]; then
		printf 'codegraph already installed\n'
	elif [ "${upgrade_tools}" -eq 1 ]; then
		bash "${root}/install-codegraph.sh" --upgrade
		PATH="${AGENT_READY_BIN_DIR:-${HOME}/.local/bin}:${PATH}"
	else
		bash "${root}/install-codegraph.sh"
		PATH="${AGENT_READY_BIN_DIR:-${HOME}/.local/bin}:${PATH}"
	fi
fi

command -v rtk >/dev/null 2>&1 || {
	printf 'rtk is not installed; run %s first\n' "$0" >&2
	exit 1
}

found=0
if agent_selected claude; then
	found=1
	configure_rtk "$(agent_label claude)" -g --hook-only --auto-patch --no-trust-filters
	install_block "$(agent_instructions claude)" "$(agent_label claude)" "$(agent_block claude)"
fi
if agent_selected codex; then
	found=1
	configure_rtk "$(agent_label codex)" -g --codex --no-trust-filters
	install_block "$(agent_instructions codex)" "$(agent_label codex)" "$(agent_block codex)"
fi
if agent_selected cursor; then
	found=1
	mkdir -p "${HOME}/.cursor"
	configure_rtk "$(agent_label cursor)" -g --agent cursor --hook-only --no-patch --no-trust-filters >/dev/null
	printf 'Cursor: configured RTK integration\n'
	install_cursor_hook
fi
if agent_selected gemini; then
	found=1
	configure_rtk "$(agent_label gemini)" -g --gemini --hook-only --auto-patch --no-trust-filters
	install_block "$(agent_instructions gemini)" "$(agent_label gemini)" "$(agent_block gemini)"
fi
if agent_selected copilot; then
	found=1
	configure_rtk "$(agent_label copilot)" -g --copilot --hook-only --auto-patch --no-trust-filters
	install_block "$(agent_instructions copilot)" "$(agent_label copilot)" "$(agent_block copilot)"
fi
if agent_selected windsurf; then
	found=1
	install_block "$(agent_instructions windsurf)" "$(agent_label windsurf)" "$(agent_block windsurf)"
fi
if agent_selected grok; then
	found=1
	install_block "$(agent_instructions grok)" "$(agent_label grok)" "$(agent_block grok)"
fi
if agent_selected opencode; then
	found=1
	configure_rtk "$(agent_label opencode)" -g --opencode --hook-only --no-patch --no-trust-filters >/dev/null
	printf 'OpenCode: configured RTK integration\n'
	install_block "$(agent_instructions opencode)" "$(agent_label opencode)" "$(agent_block opencode)"
fi
if agent_selected qwen; then
	found=1
	install_block "$(agent_instructions qwen)" "$(agent_label qwen)" "$(agent_block qwen)"
fi
if agent_selected cline; then
	found=1
	install_block "$(agent_instructions cline)" "$(agent_label cline)" "$(agent_block cline)"
fi
if agent_selected kilo; then
	found=1
	install_block "$(agent_instructions kilo)" "$(agent_label kilo)" "$(agent_block kilo)"
fi
if agent_selected crush; then
	found=1
	install_block "$(agent_instructions crush)" "$(agent_label crush)" "$(agent_block crush)"
fi
if agent_selected goose; then
	found=1
	install_block "$(agent_instructions goose)" "$(agent_label goose)" "$(agent_block goose)"
fi

# Run last: a malformed instructions file must stop the installer before a
# third-party installer gets a chance to edit it.
configure_codegraph

if [ "${found}" -eq 1 ]; then
	configured_value=$(for id in ${selected_agents}; do printf '%s\n' "${id}"; done | merge_lists)
	if [ "${auto_detection}" -eq 1 ] || [ "${prev_agents}" = auto ]; then
		agents_value=auto
	else
		# Every explicit agent this run configured joins the previous list, so a
		# later update repeats all of them rather than only the newest.
		agents_value=$(printf '%s\n%s\n' "${prev_agents}" "${agents_csv}" | merge_lists)
	fi
	if [ "${auto_detection}" -eq 1 ]; then
		configured_value=$(printf '%s\n' "${configured_value}" | merge_lists)
	else
		configured_value=$(printf '%s\n%s\n' "${prev_configured}" "${configured_value}" | merge_lists)
	fi
	languages_value=
	if [ -d "${agent_ready_config}/languages" ]; then
		languages_value=$(
			find "${agent_ready_config}/languages" -mindepth 1 -maxdepth 1 -type f -exec basename {} \; |
				awk '/^[a-z0-9_-]+$/' | sort -u | join_lines
		)
	fi
	tools_value="${prev_tools:-none}"
	[ "${install_tools}" -eq 0 ] || tools_value="${tools_used}"
	receipt_write "$(receipt_path)" "${version}" "${agents_value}" "${configured_value}" "${languages_value}" "${tools_value}"
fi

[ "${found}" -eq 1 ] || printf 'No supported harness found; rerun %s --configure-only after installing one\n' "$0"
