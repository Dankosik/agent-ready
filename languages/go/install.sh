#!/usr/bin/env bash

set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)

case "${1:-}" in
	"")
		command -v brew >/dev/null 2>&1 || {
			printf 'Homebrew is required: https://brew.sh\n' >&2
			exit 1
		}
		brew bundle --file "${root}/Brewfile"
		;;
	--configure-only) ;;
	*)
		printf 'usage: %s [--configure-only]\n' "$0" >&2
		exit 2
		;;
esac

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

if command -v cursor >/dev/null 2>&1 || command -v cursor-agent >/dev/null 2>&1; then
	cursor_config="${HOME}/.cursor/mcp.json"
	if [ -f "${cursor_config}" ] && ! plutil -extract mcpServers.gopls json -o - "${cursor_config}" >/dev/null 2>&1 && ! plutil -convert json -o /dev/null "${cursor_config}" >/dev/null 2>&1; then
		printf 'Cursor MCP config is not valid JSON: %s\n' "${cursor_config}" >&2
		exit 1
	fi
fi

if command -v codex >/dev/null 2>&1; then
	found=1
	if codex mcp get gopls --json >/dev/null 2>&1; then
		printf 'Codex: kept existing gopls MCP\n'
	else
		codex mcp add gopls -- gopls mcp
		printf 'Codex: configured gopls MCP\n'
	fi
fi

if command -v claude >/dev/null 2>&1; then
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
	if [ -f "${cursor_config}" ] && plutil -extract mcpServers.gopls json -o - "${cursor_config}" >/dev/null 2>&1; then
		printf 'Cursor: kept existing gopls MCP\n'
	else
		mkdir -p "$(dirname -- "${cursor_config}")"
		cursor_tmp=$(mktemp "${cursor_config}.XXXXXX")
		if [ -f "${cursor_config}" ]; then
			cp "${cursor_config}" "${cursor_tmp}"
			if ! plutil -extract mcpServers json -o - "${cursor_tmp}" >/dev/null 2>&1; then
				if ! plutil -insert mcpServers -json '{}' "${cursor_tmp}"; then
					rm -f "${cursor_tmp}"
					exit 1
				fi
			fi
		else
			printf '{"mcpServers":{}}\n' >"${cursor_tmp}"
		fi
		if ! plutil -insert mcpServers.gopls -json '{"command":"gopls","args":["mcp"]}' "${cursor_tmp}"; then
			rm -f "${cursor_tmp}"
			exit 1
		fi
		chmod 600 "${cursor_tmp}"
		mv "${cursor_tmp}" "${cursor_config}"
		printf 'Cursor: configured gopls MCP\n'
	fi
fi

if [ "${found}" -eq 0 ]; then
	printf 'No supported harness found; rerun %s --configure-only after installing one\n' "$0"
fi
