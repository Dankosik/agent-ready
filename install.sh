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

# Installing a tool is not the same as the agent using it. Measured on real
# session transcripts, an agent reaches for the command it already knows —
# `grep` over `rg`, `git worktree` over a wrapper — unless something tells it
# otherwise. This writes that "something" into each harness's instruction file,
# between markers, leaving everything else in the file untouched.

routing="${root}/agent-routing.md"
[ -f "${routing}" ] || {
	printf 'missing %s\n' "${routing}" >&2
	exit 1
}

start='<!-- agent-ready:start -->'
end='<!-- agent-ready:end -->'

install_block() {
	local target="$1" label="$2" tmp
	mkdir -p "$(dirname -- "${target}")"
	[ -f "${target}" ] || : >"${target}"

	tmp=$(mktemp "${target}.XXXXXX") || return 1
	if grep -qF "${start}" "${target}"; then
		# Replace the managed block in place; keep everything around it.
		awk -v s="${start}" -v e="${end}" -v f="${routing}" '
			index($0, s) { print; while ((getline line < f) > 0) print line; skip = 1; next }
			index($0, e) { skip = 0 }
			!skip { print }
		' "${target}" >"${tmp}"
		printf '%s: refreshed routing block in %s\n' "${label}" "${target}"
	else
		cat "${target}" >"${tmp}"
		[ -s "${tmp}" ] && printf '\n' >>"${tmp}"
		{
			printf '%s\n' "${start}"
			cat "${routing}"
			printf '%s\n' "${end}"
		} >>"${tmp}"
		printf '%s: added routing block to %s\n' "${label}" "${target}"
	fi
	mv "${tmp}" "${target}"
}

found=0
command -v claude >/dev/null 2>&1 && {
	found=1
	install_block "${HOME}/.claude/CLAUDE.md" "Claude Code"
}
command -v codex >/dev/null 2>&1 && {
	found=1
	install_block "${HOME}/.codex/AGENTS.md" "Codex"
}
command -v cursor >/dev/null 2>&1 || command -v cursor-agent >/dev/null 2>&1 && {
	found=1
	install_block "${HOME}/.cursor/AGENTS.md" "Cursor"
}

[ "${found}" -eq 1 ] || printf 'No supported harness found; rerun %s --configure-only after installing one\n' "$0"
