#!/usr/bin/env bash

set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)

# Assigned by lib/receipt.sh when a receipt is read.
receipt_agents=
# shellcheck source=lib/receipt.sh
# shellcheck disable=SC1091
. "${root}/../../lib/receipt.sh"

agent=auto
install_tools=1
upgrade_tools=0
binaries=0
usage() {
	printf 'usage: %s [--agent auto|claude|codex|cursor] [--configure-only|--upgrade] [--binaries]\n' "$0" >&2
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
	*) usage; exit 2 ;;
	esac
done

[ "${install_tools}" -eq 1 ] || { [ "${upgrade_tools}" -eq 0 ] && [ "${binaries}" -eq 0 ]; } || { usage; exit 2; }

case "${agent}" in
claude-code) agent=claude ;;
cursor-agent) agent=cursor ;;
esac
case "${agent}" in
auto | claude | codex | cursor) ;;
*) usage; exit 2 ;;
esac

# Without --agent, an install that named its agents stays with those agents; only
# an automatic install keeps detecting. A stale receipt stops the run first.
receipt_file=$(receipt_path)
if [ -f "${receipt_file}" ]; then
	receipt_read "${receipt_file}" || exit 1
fi
[ "${receipt_agents}" != auto ] || receipt_agents=
auto_selected() {
	[ "${agent}" = auto ] || return 1
	case ",${receipt_agents:-$1}," in
	*",$1,"*) return 0 ;;
	esac
	return 1
}

# Follows a dotfiles symlink, so the atomic move replaces the file it points at.
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

# gopls publishes no release binaries; without Homebrew on Linux it is built
# with the Go toolchain the user already has, into the same directory as the
# generic tools.
os="${AGENT_READY_OS:-$(uname -s)}"
if [ "${install_tools}" -eq 1 ] && [ "${os}" = Linux ] &&
	{ [ "${binaries}" -eq 1 ] || ! command -v brew >/dev/null 2>&1; }; then
	command -v go >/dev/null 2>&1 || {
		printf 'Go is required to install gopls: https://go.dev/dl/\n' >&2
		exit 1
	}
	bin_dir="${AGENT_READY_BIN_DIR:-${HOME}/.local/bin}"
	mkdir -p "${bin_dir}"
	if [ "${upgrade_tools}" -eq 1 ] || [ ! -x "${bin_dir}/gopls" ]; then
		GOBIN="${bin_dir}" go install golang.org/x/tools/gopls@latest
	fi
	PATH="${bin_dir}:${PATH}"
elif [ "${install_tools}" -eq 1 ]; then
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

command -v gopls >/dev/null 2>&1 || {
	printf 'gopls is not installed; run %s first\n' "$0" >&2
	exit 1
}
gopls mcp -instructions >/dev/null 2>&1 || {
	printf 'gopls v0.20 or newer is required for MCP\n' >&2
	exit 1
}

found=0
cursor_config=

if [ "${agent}" = cursor ] || { auto_selected cursor && { command -v cursor >/dev/null 2>&1 || command -v cursor-agent >/dev/null 2>&1; }; }; then
	cursor_config=$(resolve_target "${HOME}/.cursor/mcp.json")
	command -v jq >/dev/null 2>&1 || {
		printf 'Cursor: jq is required to merge mcp.json\n' >&2
		exit 1
	}
	if [ -f "${cursor_config}" ] && ! jq -e -s 'length == 1 and (.[0] | type == "object")' "${cursor_config}" >/dev/null 2>&1; then
		printf 'Cursor MCP config is not valid JSON: %s\n' "${cursor_config}" >&2
		exit 1
	fi
fi

if [ "${agent}" = codex ] && ! command -v codex >/dev/null 2>&1; then
	printf 'codex is required for --agent codex\n' >&2
	exit 1
fi
if [ "${agent}" = codex ] || { auto_selected codex && command -v codex >/dev/null 2>&1; }; then
	found=1
	if codex mcp get gopls --json >/dev/null 2>&1; then
		printf 'Codex: kept existing gopls MCP\n'
	else
		codex mcp add gopls -- gopls mcp
		printf 'Codex: configured gopls MCP\n'
	fi
fi

if [ "${agent}" = claude ] && ! command -v claude >/dev/null 2>&1; then
	printf 'claude is required for --agent claude\n' >&2
	exit 1
fi
if [ "${agent}" = claude ] || { auto_selected claude && command -v claude >/dev/null 2>&1; }; then
	found=1
	if claude mcp get gopls >/dev/null 2>&1; then
		printf 'Claude Code: kept existing gopls MCP\n'
	else
		claude mcp add --scope user gopls -- gopls mcp
		printf 'Claude Code: configured gopls MCP\n'
	fi
fi

if [ -n "${cursor_config}" ]; then
	found=1
	if [ -f "${cursor_config}" ] && jq -e '.mcpServers.gopls != null' "${cursor_config}" >/dev/null 2>&1; then
		printf 'Cursor: kept existing gopls MCP\n'
	else
		mkdir -p "$(dirname -- "${cursor_config}")"
		cursor_tmp=$(mktemp "${cursor_config}.XXXXXX")
		if [ -f "${cursor_config}" ]; then
			cp -p "${cursor_config}" "${cursor_tmp}"
			jq '
				.mcpServers = (.mcpServers // {})
				| if (.mcpServers | type) != "object" then error("mcpServers must be an object") else . end
				| .mcpServers.gopls = {"command":"gopls","args":["mcp"]}
			' "${cursor_config}" >"${cursor_tmp}" || {
				rm -f "${cursor_tmp}"
				exit 1
			}
		else
			jq -n '{mcpServers:{gopls:{command:"gopls",args:["mcp"]}}}' >"${cursor_tmp}"
		fi
		mv "${cursor_tmp}" "${cursor_config}"
		printf 'Cursor: configured gopls MCP\n'
	fi
fi

agent_ready_config="${XDG_CONFIG_HOME:-${HOME}/.config}/agent-ready"
mkdir -p "${agent_ready_config}/languages"
printf 'enabled\n' >"${agent_ready_config}/languages/go"
if command -v rtk >/dev/null 2>&1; then
	if [ "${agent}" = auto ] && [ -n "${receipt_agents}" ]; then
		"${root}/../../install.sh" --agent "${receipt_agents}" --configure-only
	elif [ "${agent}" = auto ]; then
		"${root}/../../install.sh" --configure-only
	else
		"${root}/../../install.sh" --agent "${agent}" --configure-only
	fi
else
	printf 'Go routing will be applied after the base agent-ready installer runs\n'
fi

if [ "${found}" -eq 0 ] && [ -n "${receipt_agents}" ]; then
	printf 'Go: gopls MCP setup is available for Claude Code, Codex, and Cursor only; the Go routing still applies\n'
elif [ "${found}" -eq 0 ]; then
	printf 'No supported harness found; rerun %s --configure-only after installing one\n' "$0"
fi
