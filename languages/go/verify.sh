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

# Usefulness, not just presence: find the callers of (*users.Store).Get in a
# module where a cache, an HTTP client and url.Values all have a Get too.
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${work}/cache" "${work}/users" "${work}/orders"
printf 'module example.com/svc\n\ngo 1.21\n' >"${work}/go.mod"
cat >"${work}/cache/cache.go" <<'EOF'
package cache

type Cache struct{ m map[string]string }

func (c *Cache) Get(key string) (string, bool) { v, ok := c.m[key]; return v, ok }
EOF
cat >"${work}/users/users.go" <<'EOF'
package users

import (
	"net/http"

	"example.com/svc/cache"
)

type Store struct{ c *cache.Cache }

func (s *Store) Get(id string) (string, bool) { return s.c.Get("user:" + id) }

func Handler(s *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		name, _ := s.Get(r.URL.Query().Get("id"))
		if resp, err := http.Get("https://audit.internal/log?u=" + name); err == nil {
			resp.Body.Close()
		}
	}
}
EOF
cat >"${work}/orders/orders.go" <<'EOF'
package orders

import "example.com/svc/users"

type Repo struct{ users *users.Store }

func (r *Repo) Owner(orderID string) string {
	name, _ := r.users.Get(orderID)
	return name
}
EOF
textual=$(grep -rho '\.Get(' "${work}" --include='*.go' | wc -l | tr -d ' ')
line=$(grep -n 'func (s \*Store) Get' "${work}/users/users.go" | cut -d: -f1)
col=$(awk -v l="${line}" 'NR == l { print index($0, "Get(") }' "${work}/users/users.go")
semantic=$(cd "${work}" && gopls references "users/users.go:${line}:${col}" 2>/dev/null | grep -c '\.go:' || true)
[ "${semantic}" -eq 2 ] || {
	printf 'gopls found %s references to (*Store).Get, expected 2\n' "${semantic}" >&2
	exit 1
}
printf 'renaming (*Store).Get: grep sees %s .Get( calls, gopls finds the %s real callers\n' "${textual}" "${semantic}"

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
