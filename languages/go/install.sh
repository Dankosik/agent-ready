#!/usr/bin/env bash

set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)

agent=auto
install_tools=1
usage() {
	printf 'usage: %s [--agent auto|claude|codex|cursor] [--configure-only]\n' "$0" >&2
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
	*) usage; exit 2 ;;
	esac
done

case "${agent}" in
claude-code) agent=claude ;;
cursor-agent) agent=cursor ;;
esac
case "${agent}" in
auto | claude | codex | cursor) ;;
*) usage; exit 2 ;;
esac

if [ "${install_tools}" -eq 1 ]; then
	command -v brew >/dev/null 2>&1 || {
		printf 'Homebrew is required: https://brew.sh\n' >&2
		exit 1
	}
	brew bundle --file "${root}/Brewfile"
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

if [ "${agent}" = cursor ] || { [ "${agent}" = auto ] && { command -v cursor >/dev/null 2>&1 || command -v cursor-agent >/dev/null 2>&1; }; }; then
	cursor_config="${HOME}/.cursor/mcp.json"
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
if [ "${agent}" = codex ] || { [ "${agent}" = auto ] && command -v codex >/dev/null 2>&1; }; then
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
if [ "${agent}" = claude ] || { [ "${agent}" = auto ] && command -v claude >/dev/null 2>&1; }; then
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
		chmod 600 "${cursor_tmp}"
		mv "${cursor_tmp}" "${cursor_config}"
		printf 'Cursor: configured gopls MCP\n'
	fi
fi

agent_ready_config="${XDG_CONFIG_HOME:-${HOME}/.config}/agent-ready"
mkdir -p "${agent_ready_config}/languages"
printf 'enabled\n' >"${agent_ready_config}/languages/go"
if command -v rtk >/dev/null 2>&1; then
	if [ "${agent}" = auto ]; then
		"${root}/../../install.sh" --configure-only
	else
		"${root}/../../install.sh" --agent "${agent}" --configure-only
	fi
else
	printf 'Go routing will be applied after the base agent-ready installer runs\n'
fi

if [ "${found}" -eq 0 ]; then
	printf 'No supported harness found; rerun %s --configure-only after installing one\n' "$0"
fi
