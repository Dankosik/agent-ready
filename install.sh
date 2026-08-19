#!/usr/bin/env bash

set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)

agent=auto
install_tools=1
upgrade_tools=0
usage() {
	printf 'usage: %s [--agent auto|claude|codex|cursor|gemini|copilot|windsurf] [--configure-only|--upgrade]\n' "$0" >&2
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
	*)
		usage
		exit 2
		;;
	esac
done

[ "${install_tools}" -eq 1 ] || [ "${upgrade_tools}" -eq 0 ] || { usage; exit 2; }

case "${agent}" in
claude-code) agent=claude ;;
cursor-agent) agent=cursor ;;
gemini-cli) agent=gemini ;;
github-copilot) agent=copilot ;;
esac
case "${agent}" in
auto | claude | codex | cursor | gemini | copilot | windsurf) ;;
*) usage; exit 2 ;;
esac

if [ "${install_tools}" -eq 1 ]; then
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
cleanup_routing() { [ -z "${routing_tmp}" ] || rm -f "${routing_tmp}"; }
trap cleanup_routing EXIT

command -v rtk >/dev/null 2>&1 || {
	printf 'rtk is not installed; run %s first\n' "$0" >&2
	exit 1
}

start='<!-- agent-ready:start -->'
end='<!-- agent-ready:end -->'

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

install_block() {
	local requested="$1" label="$2" target tmp state
	mkdir -p "$(dirname -- "${requested}")"
	target=$(resolve_target "${requested}")
	mkdir -p "$(dirname -- "${target}")"
	[ -f "${target}" ] || : >"${target}"
	state=$(block_state "${target}")
	[ "${state}" != invalid ] || {
		printf '%s: malformed agent-ready markers in %s\n' "${label}" "${requested}" >&2
		return 1
	}

	tmp=$(mktemp "${target}.XXXXXX") || return 1
	cp -p "${target}" "${tmp}"
	if [ "${state}" = present ]; then
		awk -v s="${start}" -v e="${end}" -v f="${routing}" '
			$0 == s { print; while ((getline line < f) > 0) print line; skip = 1; next }
			$0 == e { skip = 0 }
			!skip { print }
		' "${target}" >"${tmp}"
	else
		{
			cat "${target}"
			[ -s "${target}" ] && printf '\n'
			printf '%s\n' "${start}"
			cat "${routing}"
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

found=0
if [ "${agent}" = claude ] || { [ "${agent}" = auto ] && command -v claude >/dev/null 2>&1; }; then
	found=1
	configure_rtk "Claude Code" -g --hook-only --auto-patch --no-trust-filters
	install_block "${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/CLAUDE.md" "Claude Code"
fi
if [ "${agent}" = codex ] || { [ "${agent}" = auto ] && command -v codex >/dev/null 2>&1; }; then
	found=1
	configure_rtk "Codex" -g --codex --no-trust-filters
	install_block "${CODEX_HOME:-${HOME}/.codex}/AGENTS.md" "Codex"
fi
if [ "${agent}" = cursor ] || { [ "${agent}" = auto ] && { command -v cursor >/dev/null 2>&1 || command -v cursor-agent >/dev/null 2>&1 || [ -d /Applications/Cursor.app ] || [ -d "${HOME}/Applications/Cursor.app" ]; }; }; then
	found=1
	configure_rtk "Cursor" -g --agent cursor --hook-only --no-patch --no-trust-filters >/dev/null
	printf 'Cursor: configured RTK integration\n'
	install_cursor_hook
fi
if [ "${agent}" = gemini ] || { [ "${agent}" = auto ] && command -v gemini >/dev/null 2>&1; }; then
	found=1
	configure_rtk "Gemini CLI" -g --gemini --hook-only --auto-patch --no-trust-filters
	install_block "${HOME}/.gemini/GEMINI.md" "Gemini CLI"
fi
if [ "${agent}" = copilot ] || { [ "${agent}" = auto ] && command -v copilot >/dev/null 2>&1; }; then
	found=1
	configure_rtk "GitHub Copilot CLI" -g --copilot --hook-only --auto-patch --no-trust-filters
	install_block "${COPILOT_HOME:-${HOME}/.copilot}/copilot-instructions.md" "GitHub Copilot CLI"
fi
if [ "${agent}" = windsurf ] || { [ "${agent}" = auto ] && { command -v windsurf >/dev/null 2>&1 || [ -d /Applications/Windsurf.app ] || [ -d "${HOME}/Applications/Windsurf.app" ]; }; }; then
	found=1
	install_block "${HOME}/.codeium/windsurf/memories/global_rules.md" "Windsurf"
fi

[ "${found}" -eq 1 ] || printf 'No supported harness found; rerun %s --configure-only after installing one\n' "$0"
