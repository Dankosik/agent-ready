#!/usr/bin/env bash

set -euo pipefail

command -v gopls >/dev/null 2>&1 || {
	printf 'gopls is not installed\n' >&2
	exit 1
}

instructions=$(gopls mcp -instructions)
tools=$(printf '%s\n' "${instructions}" | grep -Eo 'go_[a-z_]+' | sort -u | wc -l | tr -d ' ')
version=$(gopls version | awk '/golang.org\/x\/tools\/gopls/{print $2; exit}')

printf 'gopls %s MCP ready; instructions describe %s semantic Go tools\n' "${version}" "${tools}"
