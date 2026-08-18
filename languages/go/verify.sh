#!/usr/bin/env bash

set -euo pipefail

command -v gopls >/dev/null 2>&1 || {
	printf 'gopls is not installed\n' >&2
	exit 1
}

agent_ready_config="${XDG_CONFIG_HOME:-${HOME}/.config}/agent-ready"
[ -f "${agent_ready_config}/languages/go" ] || {
	printf 'agent-ready Go routing is not enabled; run languages/go/install.sh\n' >&2
	exit 1
}

instructions=$(gopls mcp -instructions)
version=$(gopls version | awk '/golang.org\/x\/tools\/gopls/{print $2; exit}')
for tool in go_workspace go_search go_file_context go_package_api go_symbol_references go_diagnostics go_vulncheck; do
	grep -q "${tool}" <<<"${instructions}" || {
		printf 'gopls MCP instructions are missing %s\n' "${tool}" >&2
		exit 1
	}
done

configured=0
if command -v codex >/dev/null 2>&1; then
	codex mcp get gopls --json >/dev/null
	configured=$((configured + 1))
fi
if command -v claude >/dev/null 2>&1; then
	claude mcp get gopls >/dev/null
	configured=$((configured + 1))
fi
if command -v cursor >/dev/null 2>&1 || command -v cursor-agent >/dev/null 2>&1; then
	jq -e '.mcpServers.gopls != null' "${HOME}/.cursor/mcp.json" >/dev/null
	configured=$((configured + 1))
fi

printf 'gopls %s MCP ready; 7 semantic tools and %d agent connections verified\n' "${version}" "${configured}"
