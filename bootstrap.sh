#!/usr/bin/env bash

set -euo pipefail

usage() {
	printf 'usage: %s [agent <name>|language <name>|<agent>] [installer options]\n' "$0" >&2
}

work=
cleanup() { [ -z "${work}" ] || rm -rf "${work}"; }
trap cleanup EXIT

source_path="${BASH_SOURCE[0]:-}"
if [ -n "${source_path}" ] && [ -f "${source_path}" ]; then
	root=$(cd -- "$(dirname -- "${source_path}")" && pwd)
else
	command -v curl >/dev/null 2>&1 || { printf 'curl is required\n' >&2; exit 1; }
	work=$(mktemp -d)
	archive="${work}/agent-ready.tar.gz"
	listing="${work}/archive.list"
	ref="${AGENT_READY_REF:-main}"
	archive_url="${AGENT_READY_ARCHIVE_URL:-https://codeload.github.com/Dankosik/agent-ready/tar.gz/${ref}}"
	printf 'Downloading agent-ready %s\n' "${ref}"
	curl -fsSL "${archive_url}" -o "${archive}"
	tar -tzf "${archive}" >"${listing}"
	if grep -Eq '^/|(^|/)\.\.(/|$)' "${listing}"; then
		printf 'archive contains an unsafe path\n' >&2
		exit 1
	fi
	tar -xzf "${archive}" -C "${work}"
	root=$(find "${work}" -mindepth 1 -maxdepth 1 -type d -print -quit)
fi

[ -n "${root}" ] && [ -f "${root}/install.sh" ] || { printf 'agent-ready installer not found\n' >&2; exit 1; }

case "${1:-}" in
"")
	bash "${root}/install.sh"
	;;
agent)
	[ "$#" -ge 2 ] || { usage; exit 2; }
	agent="$2"
	shift 2
	bash "${root}/install.sh" --agent "${agent}" "$@"
	;;
language)
	[ "$#" -ge 2 ] || { usage; exit 2; }
	language="$2"
	shift 2
	case "${language}" in
	"" | *[!a-z0-9_-]*) printf 'unsupported language: %s\n' "${language}" >&2; exit 2 ;;
	esac
	installer="${root}/languages/${language}/install.sh"
	[ -f "${installer}" ] || { printf 'unsupported language: %s\n' "${language}" >&2; exit 2; }
	bash "${installer}" "$@"
	;;
--agent | --configure-only | --upgrade)
	bash "${root}/install.sh" "$@"
	;;
claude | claude-code | codex | cursor | cursor-agent | gemini | gemini-cli | copilot | github-copilot | windsurf | grok | grok-build | opencode | open-code | qwen | qwen-code | cline | kilo | kilocode | kilo-code | crush | goose)
	agent="$1"
	shift
	bash "${root}/install.sh" --agent "${agent}" "$@"
	;;
*)
	usage
	exit 2
	;;
esac
