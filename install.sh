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
uninstall=0
usage() {
	printf 'usage: %s [--agent auto|claude|codex|cursor|gemini|antigravity|copilot|windsurf|grok|opencode|qwen|cline|kilo|crush|goose|dsh|pi|<name>,...] [--configure-only|--upgrade] [--binaries] [--force] [--dry-run]\n' "$0" >&2
	printf '       %s --uninstall [--force] [--dry-run]\n' "$0" >&2
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
	--uninstall)
		uninstall=1
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
[ "${uninstall}" -eq 0 ] || { [ "${agent}" = auto ] && [ "${install_tools}" -eq 1 ] && [ "${upgrade_tools}" -eq 0 ] && [ "${binaries}" -eq 0 ]; } || { usage; exit 2; }

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
	agy | antigravity-cli) printf 'antigravity\n' ;;
	deepseek-harness) printf 'dsh\n' ;;
	pi-coding-agent) printf 'pi\n' ;;
	claude | codex | cursor | gemini | antigravity | copilot | windsurf | grok | opencode | qwen | cline | kilo | crush | goose | dsh | pi)
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
	antigravity) printf 'Google Antigravity' ;;
	copilot) printf 'GitHub Copilot CLI' ;;
	windsurf) printf 'Windsurf' ;;
	grok) printf 'Grok Build' ;;
	opencode) printf 'OpenCode' ;;
	qwen) printf 'Qwen Code' ;;
	cline) printf 'Cline CLI' ;;
	kilo) printf 'Kilo Code' ;;
	crush) printf 'Crush' ;;
	goose) printf 'goose' ;;
	dsh) printf 'DeepSeek Harness' ;;
	pi) printf 'Pi' ;;
	esac
}

# Pi reads only the first of these files that exists in its agent directory, so
# a new AGENTS.md would silently hide a user's CLAUDE.md, and an override would
# hide the block. The block goes in whichever file Pi actually loads.
pi_instructions() {
	local dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}" name
	for name in AGENTS.override.md AGENTS.md AGENTS.MD CLAUDE.md CLAUDE.MD; do
		if [ -f "${dir}/${name}" ]; then
			printf '%s\n' "${dir}/${name}"
			return 0
		fi
	done
	printf '%s\n' "${dir}/AGENTS.md"
}

any_enabled() {
	local value
	for value in "$@"; do
		case "${value}" in
		1 | true | TRUE | True) return 0 ;;
		esac
	done
	return 1
}

# Once Kilo has attempted its Claude migration it stops loading ~/.claude/CLAUDE.md,
# unless one of these variables puts it in a context the migration does not cover.
# Without XDG_STATE_HOME its state stays under the data directory when that exists.
kilo_claude_handed_off() {
	local value
	for value in "${CLAUDE_CONFIG_DIR:-}" "${KILO_CONFIG_DIR:-}" "${KILO_CONFIG:-}" "${KILO_CONFIG_CONTENT:-}"; do
		[ -z "${value//[[:space:]]/}" ] || return 1
	done
	if [ -n "${XDG_STATE_HOME:-}" ]; then
		[ -e "${XDG_STATE_HOME}/kilo/claude-migration.json" ]
	else
		[ -e "${XDG_DATA_HOME:-${HOME}/.local/share}/kilo/state/claude-migration.json" ] ||
			[ -e "${HOME}/.local/state/kilo/claude-migration.json" ]
	fi
}

# Kilo loads the first of these that exists, even an empty one, so a new AGENTS.md
# would silently hide ~/.claude/CLAUDE.md, whichever agent wrote that file. The
# block goes in whichever file Kilo actually loads. KILO_CONFIG_DIR replaces the
# default directory rather than adding to it. A selected Claude Code is about to
# create CLAUDE.md, so it counts as existing.
kilo_claude_disabled() {
	any_enabled "${KILO_DISABLE_CLAUDE_CODE:-}" "${KILO_DISABLE_CLAUDE_CODE_PROMPT:-}" || kilo_claude_handed_off
}

kilo_default_instructions() {
	printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/kilo/AGENTS.md"
}

kilo_instructions() {
	local own claude="${HOME}/.claude/CLAUDE.md"
	if [ -n "${KILO_CONFIG_DIR:-}" ]; then
		own="${KILO_CONFIG_DIR}/AGENTS.md"
	else
		own=$(kilo_default_instructions)
	fi
	if [ ! -f "${own}" ] && ! kilo_claude_disabled &&
		{ [ -f "${claude}" ] || { agent_selected claude && [ -z "${CLAUDE_CONFIG_DIR:-}" ]; }; }; then
		printf '%s\n' "${claude}"
	else
		printf '%s\n' "${own}"
	fi
}

# OpenCode 1.x loads the first of its AGENTS.md and ~/.claude/CLAUDE.md that exists,
# even an empty one; 2.x reads only AGENTS.md, and so does a version this cannot
# read. Asked once, because the path functions run many times per install.
opencode_major=
if command -v opencode >/dev/null 2>&1; then
	opencode_major=$(opencode --version 2>/dev/null </dev/null |
		sed -n 's/^[^0-9]*\([0-9][0-9]*\)\..*/\1/p' | head -1) || opencode_major=
fi

opencode_reads_claude() {
	[ "${opencode_major}" = 1 ] &&
		! any_enabled "${OPENCODE_DISABLE_CLAUDE_CODE:-}" "${OPENCODE_DISABLE_CLAUDE_CODE_PROMPT:-}"
}

opencode_own_instructions() {
	printf '%s\n' "${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-${HOME}/.config}/opencode}/AGENTS.md"
}

# The same rule as Kilo: the block joins a CLAUDE.md a new AGENTS.md would hide.
opencode_instructions() {
	local own claude="${HOME}/.claude/CLAUDE.md"
	own=$(opencode_own_instructions)
	if opencode_reads_claude && [ ! -e "${own}" ] && [ ! -L "${own}" ] &&
		{ [ -f "${claude}" ] || { agent_selected claude && [ -z "${CLAUDE_CONFIG_DIR:-}" ]; }; }; then
		printf '%s\n' "${claude}"
	else
		printf '%s\n' "${own}"
	fi
}

# `codegraph install` creates the default AGENTS.md, which would hide that CLAUDE.md
# again, so OpenCode goes without the MCP entry there. It does not know
# OPENCODE_CONFIG_DIR, and a file it writes elsewhere hides nothing.
opencode_codegraph_hides() {
	agent_selected opencode && [ -z "${OPENCODE_CONFIG_DIR:-}" ] &&
		[ "$(opencode_instructions)" != "$(opencode_own_instructions)" ]
}

# A file with only managed content, or left empty by uninstall, still hides
# CLAUDE.md. Whether to delete it is the user's call, so it is only pointed out.
hiding_notice() {
	local label="$1" name="$2" own="$3" claude="${HOME}/.claude/CLAUDE.md"
	[ -f "${claude}" ] || return 0
	[ "${own}" != "${claude}" ] && [ -f "${own}" ] || return 0
	[ ! "${own}" -ef "${claude}" ] || return 0
	if awk -v s="${start}" -v e="${end}" '
		$0 == s || $0 == "<!-- CODEGRAPH_START -->" { skip = 1; next }
		$0 == e || $0 == "<!-- CODEGRAPH_END -->" { skip = 0; next }
		!skip && NF { found = 1 }
		END { exit !found }
	' "${own}"; then
		return 0
	fi
	printf '%s: %s holds nothing of yours but hides %s from %s; delete it if %s should read that file\n' \
		"${label}" "${own}" "${claude}" "${name}" "${name}"
}

kilo_hiding_notice() {
	! kilo_claude_disabled || return 0
	hiding_notice 'Kilo Code' Kilo "$(kilo_instructions)"
}

opencode_hiding_notice() {
	opencode_reads_claude || return 0
	hiding_notice OpenCode OpenCode "$(opencode_own_instructions)"
}

goose_default_instructions() {
	printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/goose/AGENTS.md"
}

# goose ignores a GOOSE_PATH_ROOT that is not absolute.
goose_instructions() {
	case "${GOOSE_PATH_ROOT:-}" in
	/*) printf '%s\n' "${GOOSE_PATH_ROOT}/config/AGENTS.md" ;;
	*) goose_default_instructions ;;
	esac
}

# Codex reads the first non-empty one of these, so an override hides AGENTS.md.
codex_instructions() {
	local dir="${CODEX_HOME:-${HOME}/.codex}"
	if [ -s "${dir}/AGENTS.override.md" ]; then
		printf '%s\n' "${dir}/AGENTS.override.md"
	else
		printf '%s\n' "${dir}/AGENTS.md"
	fi
}

# Windsurf became Devin Desktop, which documents ~/.devin/global_rules.md. A
# machine with only the older app's data stays on the file that app reads.
windsurf_instructions() {
	if [ ! -d "${HOME}/.devin" ] && [ -d "${HOME}/.codeium/windsurf" ]; then
		printf '%s\n' "${HOME}/.codeium/windsurf/memories/global_rules.md"
	else
		printf '%s\n' "${HOME}/.devin/global_rules.md"
	fi
}

agent_instructions() {
	case "$1" in
	claude) printf '%s\n' "${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/CLAUDE.md" ;;
	codex) codex_instructions ;;
	# Antigravity shares Gemini CLI's global file unless GEMINI_CLI_HOME moves
	# Gemini's; only Gemini CLI is documented to honour that variable.
	gemini) printf '%s\n' "${GEMINI_CLI_HOME:-${HOME}}/.gemini/GEMINI.md" ;;
	antigravity) printf '%s\n' "${HOME}/.gemini/GEMINI.md" ;;
	copilot) printf '%s\n' "${COPILOT_HOME:-${HOME}/.copilot}/copilot-instructions.md" ;;
	windsurf) windsurf_instructions ;;
	grok) printf '%s\n' "${GROK_HOME:-${HOME}/.grok}/rules/agent-ready.md" ;;
	opencode) opencode_instructions ;;
	qwen) printf '%s\n' "${QWEN_HOME:-${HOME}/.qwen}/QWEN.md" ;;
	cline) printf '%s\n' "${CLINE_DIR:-${HOME}/.cline}/rules/agent-ready.md" ;;
	kilo) kilo_instructions ;;
	crush) printf '%s\n' "${CRUSH_GLOBAL_CONFIG:-${XDG_CONFIG_HOME:-${HOME}/.config}/crush}/CRUSH.md" ;;
	goose) goose_instructions ;;
	dsh) printf '%s\n' "${DSH_HOME:-${HOME}/.dsh}/AGENTS.md" ;;
	pi) pi_instructions ;;
	esac
}

# Files an earlier run may have written for this agent. The agent no longer
# reads a block left in one, so install moves it and uninstall still finds it.
agent_stale_candidates() {
	local dir name
	case "$1" in
	codex)
		dir="${CODEX_HOME:-${HOME}/.codex}"
		printf '%s\n' "${dir}/AGENTS.override.md" "${dir}/AGENTS.md"
		;;
	windsurf)
		printf '%s\n' "${HOME}/.devin/global_rules.md" "${HOME}/.codeium/windsurf/memories/global_rules.md"
		;;
	# Where the block sat before one of these variables moved the agent's file.
	opencode)
		printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/opencode/AGENTS.md"
		[ -z "${OPENCODE_CONFIG_DIR:-}" ] || printf '%s\n' "${OPENCODE_CONFIG_DIR}/AGENTS.md"
		printf '%s\n' "${HOME}/.claude/CLAUDE.md"
		;;
	crush) printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/crush/CRUSH.md" ;;
	goose) goose_default_instructions ;;
	kilo)
		kilo_default_instructions
		[ -z "${KILO_CONFIG_DIR:-}" ] || printf '%s\n' "${KILO_CONFIG_DIR}/AGENTS.md"
		printf '%s\n' "${HOME}/.claude/CLAUDE.md"
		;;
	# Before v1.5.1 the block went where Cline CLI never loaded it.
	cline) printf '%s\n' "${CLINE_DATA_DIR:-${HOME}/.cline/data}/settings/rules/agent-ready.md" ;;
	pi)
		dir="${PI_CODING_AGENT_DIR:-${HOME}/.pi/agent}"
		for name in AGENTS.override.md AGENTS.md AGENTS.MD CLAUDE.md CLAUDE.MD; do
			printf '%s\n' "${dir}/${name}"
		done
		;;
	esac
}

# -ef because AGENTS.md and AGENTS.MD are one file on a case-insensitive disk, and
# a candidate may be a symlink to the file another agent reads, whose block is not
# this agent's to remove.
agent_stale_instructions() {
	local active path other
	active=$(agent_instructions "$1")
	while IFS= read -r path; do
		[ "${path}" != "${active}" ] || continue
		if [ -e "${path}" ]; then
			[ ! "${path}" -ef "${active}" ] || continue
			for other in ${agent_ids}; do
				[ "${other}" != "$1" ] || continue
				[ ! "${path}" -ef "$(agent_instructions "${other}")" ] || continue 2
			done
		fi
		printf '%s\n' "${path}"
	done < <(agent_stale_candidates "$1")
}

# `codegraph install` writes its own CodeGraph section into these four agents'
# files, so their agent-ready block leaves out the Code graph line. It knows
# neither GEMINI_CLI_HOME nor OPENCODE_CONFIG_DIR, so a file moved by one of those
# never gets that section and keeps the line.
agent_own_block() {
	case "$1" in
	claude) printf '%s\n' "${graph_routing}" ;;
	gemini)
		if [ -n "${GEMINI_CLI_HOME:-}" ]; then
			printf '%s\n' "${routing}"
		else
			printf '%s\n' "${graph_routing}"
		fi
		;;
	opencode)
		if [ -n "${OPENCODE_CONFIG_DIR:-}" ] || opencode_codegraph_hides; then
			printf '%s\n' "${routing}"
		else
			printf '%s\n' "${graph_routing}"
		fi
		;;
	# CodeGraph writes its section to AGENTS.md, which an override hides.
	codex)
		case "$(codex_instructions)" in
		*/AGENTS.md) printf '%s\n' "${graph_routing}" ;;
		*) printf '%s\n' "${routing}" ;;
		esac
		;;
	# CodeGraph's Antigravity target writes only MCP config, so the shared file
	# gets its section only through Gemini: an explicit gemini, or auto, which
	# wires Gemini whenever ~/.gemini exists. Both ids must render one block.
	antigravity)
		if { [ "${auto_detection}" -eq 1 ] && ! opencode_codegraph_hides; } || agent_selected gemini; then
			printf '%s\n' "${graph_routing}"
		else
			printf '%s\n' "${routing}"
		fi
		;;
	*) printf '%s\n' "${routing}" ;;
	esac
}

# Whether two paths are one file, also before that file exists.
same_file() {
	[ "$1" = "$2" ] || [ "$1" -ef "$2" ] ||
		[ "$(resolve_target "$1" 2>/dev/null || true)" = "$(resolve_target "$2" 2>/dev/null || true)" ]
}

# A file can have one block, however many agents read it through a dotfiles
# symlink, or the agents would overwrite each other on every run. CodeGraph's
# section reaches the file through any one of them, so one is enough to drop the
# Code graph line. Agents an earlier run configured count, so that configuring one
# agent at a time settles on the same block.
agent_block() {
	local id="$1" own file other
	own=$(agent_own_block "${id}")
	if [ "${own}" != "${graph_routing}" ]; then
		file=$(agent_instructions "${id}")
		for other in ${selected_agents} ${prev_configured//,/ }; do
			[ "${other}" != "${id}" ] && [ "${other}" != cursor ] || continue
			same_file "${file}" "$(agent_instructions "${other}")" || continue
			if [ "$(agent_own_block "${other}")" = "${graph_routing}" ]; then
				own="${graph_routing}"
				break
			fi
		done
	fi
	printf '%s\n' "${own}"
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
detect_antigravity() {
	command -v agy >/dev/null 2>&1 || [ -d "${HOME}/.gemini/antigravity" ] ||
		[ -d /Applications/Antigravity.app ] || [ -d "${HOME}/Applications/Antigravity.app" ]
}
detect_copilot() { command -v copilot >/dev/null 2>&1; }
detect_windsurf() {
	command -v windsurf >/dev/null 2>&1 || [ -d "${HOME}/.devin" ] ||
		[ -d /Applications/Windsurf.app ] || [ -d "${HOME}/Applications/Windsurf.app" ]
}
detect_grok() { command -v grok >/dev/null 2>&1; }
detect_opencode() { command -v opencode >/dev/null 2>&1; }
detect_qwen() { command -v qwen >/dev/null 2>&1; }
detect_cline() { command -v cline >/dev/null 2>&1; }
detect_kilo() { command -v kilo >/dev/null 2>&1; }
detect_crush() { command -v crush >/dev/null 2>&1; }
# Unrelated tools own these two names: pressly's goose runs database migrations,
# and dsh is also the distributed shell. Only those are ruled out, by what they
# print, so an agent whose output changes is still detected.
detect_goose() {
	local out
	command -v goose >/dev/null 2>&1 || return 1
	out=$(goose --version 2>&1 </dev/null || true)
	case "${out}" in
	"goose version:"*) return 1 ;;
	esac
}
# DeepSeek Harness is documented through npx, which leaves no dsh on PATH, so its
# home directory counts too.
detect_dsh() {
	local out
	[ ! -d "${DSH_HOME:-${HOME}/.dsh}" ] || return 0
	command -v dsh >/dev/null 2>&1 || return 1
	out=$(dsh --version 2>&1 </dev/null || true)
	case "${out}" in
	*[Dd]istributed*[Ss]hell* | *"ancer's shell"*) return 1 ;;
	esac
}
detect_pi() { command -v pi >/dev/null 2>&1; }

agent_ids="claude codex cursor gemini antigravity copilot windsurf grok opencode qwen cline kilo crush goose dsh pi"
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

# Why this path cannot be written, or nothing when it can. A read-only file is the
# user's choice, so it is refused rather than replaced by the atomic move, which
# only needs a writable directory.
path_problem() {
	local path="$1" dir
	if [ -e "${path}" ] && [ ! -w "${path}" ]; then
		printf 'file is not writable\n'
		return 0
	fi
	dir=$(dirname -- "${path}")
	while [ ! -e "${dir}" ] && [ ! -L "${dir}" ]; do
		dir=$(dirname -- "${dir}")
	done
	if [ ! -d "${dir}" ]; then
		printf '%s is not a directory\n' "${dir}"
	elif [ ! -w "${dir}" ]; then
		printf 'directory %s is not writable\n' "${dir}"
	fi
}

block_state() {
	awk -v s="${start}" -v e="${end}" '
		$0 == s { starts++; start_line = NR }
		$0 == e { ends++; end_line = NR }
		{
			line = $0
			if (sub(/\r$/, "", line) && (line == s || line == e)) crlf = 1
		}
		END {
			if (crlf) print "invalid"
			else if (starts == 0 && ends == 0) print "absent"
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

# Whether the block no longer matches the fingerprint in its own header.
block_has_local_edits() {
	local header digest
	header=$(block_first_line "$1")
	block_has_header "${header}" || return 1
	digest="${header#* sha256:}"
	digest="${digest%% -->*}"
	[ "${digest}" != "$(block_body_hash "$1")" ]
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

# A planned write: reported when it can happen, blocked before any write when not.
preflight_write() {
	local label="$1" verb="$2" requested="$3" target="$4" problem
	problem=$(path_problem "${target}")
	if [ -n "${problem}" ]; then
		preflight_blocked "${label}" "${requested}" other "${problem}"
	else
		preflight_report "${label}" "${verb}" "${requested}"
	fi
}

preflight_instruction() {
	local label="$1" requested="$2" body="$3" target state header digest expected
	target=$(resolve_target "${requested}") || {
		preflight_blocked "${label}" "${requested}" other "unresolvable symlink"
		return 0
	}
	if [ -e "${target}" ] && [ ! -f "${target}" ]; then
		preflight_blocked "${label}" "${requested}" other "not a regular file"
		return 0
	fi
	if [ ! -f "${target}" ]; then
		preflight_write "${label}" "would add" "${requested}" "${target}"
		return 0
	fi
	state=$(block_state "${target}")
	case "${state}" in
	absent)
		preflight_write "${label}" "would add" "${requested}" "${target}"
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
					preflight_write "${label}" "would refresh" "${requested}" "${target}"
				else
					preflight_blocked "${label}" "${requested}" edits ""
				fi
				return 0
			fi
		fi
		if [ "${header}" = "${expected}" ]; then
			preflight_report "${label}" unchanged "${requested}"
		else
			preflight_write "${label}" "would refresh" "${requested}" "${target}"
		fi
		;;
	esac
}

# A block install is about to move must be just as safe to remove as to replace.
preflight_stale() {
	local id="$1" label path state target
	label=$(agent_label "${id}")
	# Which app created ~/.devin is unknown, so the older Windsurf may still be in
	# use: its block stays until uninstall rather than move on install. The same goes
	# for a block left behind by a variable that may only select a profile, and for
	# a CLAUDE.md that Kilo or OpenCode no longer loads but another agent may.
	case "${id}" in
	windsurf | opencode | kilo | crush | goose) return 0 ;;
	esac
	while IFS= read -r path; do
		if ! target=$(resolve_target "${path}"); then
			preflight_blocked "${label}" "${path}" other "unresolvable symlink"
			continue
		fi
		[ -f "${path}" ] || continue
		state=$(block_state "${path}")
		case "${state}" in
		absent) ;;
		invalid) preflight_blocked "${label}" "${path}" markers "" ;;
		present)
			if [ "${force}" -eq 0 ] && block_has_local_edits "${path}"; then
				preflight_blocked "${label}" "${path}" edits ""
			else
				preflight_write "${label}" "would remove the stale block from" "${path}" "${target}"
			fi
			;;
		esac
	done < <(agent_stale_instructions "${id}")
}

retire_stale() {
	local id="$1" label path
	label=$(agent_label "${id}")
	while IFS= read -r path; do
		remove_block "${path}" "${label}"
	done < <(agent_stale_instructions "${id}")
}

preflight_cursor() {
	local label="Cursor" cursor_dir="${HOME}/.cursor" requested legacy state=absent hooks response current=1 problem
	requested="${cursor_dir}/hooks.json"
	legacy="${cursor_dir}/AGENTS.md"
	response="${cursor_dir}/hooks/agent-ready-session-start.json"
	# Only a response that has to change needs a writable path.
	if ! { command -v jq >/dev/null 2>&1 && [ -f "${response}" ] &&
		cmp -s "${response}" <(jq -Rs '{additional_context: .}' "${routing}"); }; then
		problem=$(path_problem "${response}")
		[ -z "${problem}" ] || preflight_blocked "${label}" "${response}" other "${problem}"
	fi
	if [ -f "${legacy}" ]; then
		state=$(block_state "${legacy}")
		case "${state}" in
		invalid) preflight_blocked "${label}" "${legacy}" markers "" ;;
		present)
			if [ "${force}" -eq 0 ] && block_has_local_edits "${legacy}"; then
				preflight_blocked "${label}" "${legacy}" edits ""
			else
				preflight_write "${label}" "would remove the legacy block from" "${legacy}" "$(resolve_target "${legacy}")"
			fi
			;;
		esac
	fi
	if [ ! -f "${requested}" ] && [ ! -L "${requested}" ]; then
		preflight_write "${label}" "would add" "${requested}" "${requested}"
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
		preflight_write "${label}" "would refresh" "${requested}" "${hooks}"
	fi
}

preflight_all() {
	local id
	for id in ${selected_agents}; do
		if [ "${id}" = cursor ]; then
			preflight_cursor
		else
			preflight_instruction "$(agent_label "${id}")" "$(agent_instructions "${id}")" "$(agent_block "${id}")"
			preflight_stale "${id}"
		fi
	done
}

# The whole file as it should read with this block in it.
render_block() {
	local target="$1" state="$2" header="$3" block="$4"
	if [ "${state}" = present ]; then
		awk -v s="${start}" '
			$0 == s { print; exit }
			{ print }
		' "${target}"
		printf '%s\n' "${header}"
		block_body "${block}"
		awk -v e="${end}" '
			found { print }
			$0 == e { found = 1; print }
		' "${target}"
	else
		cat "${target}"
		if [ -s "${target}" ]; then printf '\n'; fi
		printf '%s\n' "${start}"
		printf '%s\n' "${header}"
		block_body "${block}"
		printf '%s\n' "${end}"
	fi
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

	# Compared before any write, so a read-only file needing no change is fine. The
	# x keeps a trailing newline from being stripped by the substitution.
	if [ "$(render_block "${target}" "${state}" "${header}" "${block}"; printf x)" = "$(cat "${target}"; printf x)" ]; then
		printf '%s: routing already configured in %s\n' "${label}" "${requested}"
		return 0
	fi
	tmp=$(mktemp "${target}.XXXXXX") || return 1
	if ! cp -p "${target}" "${tmp}" ||
		! render_block "${target}" "${state}" "${header}" "${block}" >"${tmp}"; then
		rm -f "${tmp}"
		printf '%s: could not write %s\n' "${label}" "${requested}" >&2
		return 1
	fi
	mv "${tmp}" "${target}" || {
		rm -f "${tmp}"
		return 1
	}
	printf '%s: %s routing block in %s\n' "${label}" "$([ "${state}" = present ] && printf refreshed || printf added)" "${requested}"
}

remove_block() {
	local requested="$1" label="$2" target tmp state
	[ -e "${requested}" ] || [ -L "${requested}" ] || return 0
	target=$(resolve_target "${requested}")
	[ -f "${target}" ] || return 0
	state=$(block_state "${target}")
	case "${state}" in
	absent) return 0 ;;
	present) ;;
	*)
		printf '%s: malformed agent-ready markers in %s\n' "${label}" "${requested}" >&2
		return 1
		;;
	esac
	tmp=$(mktemp "${target}.XXXXXX") || return 1
	cp -p "${target}" "${tmp}" || {
		rm -f "${tmp}"
		return 1
	}
	# Install writes one blank line before a block it appends; drop that same
	# separator so the file returns to the bytes it had before the install.
	if ! awk -v s="${start}" -v e="${end}" '
		function flush() { if (have) print prev; have = 0 }
		$0 == s {
			if (have && prev == "") have = 0
			else flush()
			skip = 1
			next
		}
		$0 == e { skip = 0; next }
		skip { next }
		{
			flush()
			prev = $0
			have = 1
		}
		END { flush() }
	' "${target}" >"${tmp}"; then
		rm -f "${tmp}"
		printf '%s: could not write %s\n' "${label}" "${requested}" >&2
		return 1
	fi
	mv "${tmp}" "${target}" || {
		rm -f "${tmp}"
		return 1
	}
	printf '%s: removed routing block from %s\n' "${label}" "${requested}"
}

configure_rtk() {
	local label="$1"
	shift
	rtk init "$@"
	printf '%s: configured RTK integration\n' "${label}"
}

# Installs never upgrade tools by default, so an existing rtk may predate these
# integrations. The routing block still works without the hook.
configure_rtk_optional() {
	local label="$1" agent_id="$2"
	if rtk init -g --agent "${agent_id}" --hook-only --no-patch --no-trust-filters; then
		printf '%s: configured RTK integration\n' "${label}"
	else
		printf '%s: RTK integration failed; upgrade rtk and run rtk init -g --agent %s\n' "${label}" "${agent_id}" >&2
	fi
}

install_cursor_hook() {
	local cursor_dir="${HOME}/.cursor" response hooks requested tmp command merged
	command -v jq >/dev/null 2>&1 || {
		printf 'Cursor: jq is required to merge hooks.json\n' >&2
		return 1
	}
	mkdir -p "${cursor_dir}/hooks"

	response="${cursor_dir}/hooks/agent-ready-session-start.json"
	# Compared before any write, so a read-only path needing no change is fine.
	if ! { [ -f "${response}" ] && cmp -s "${response}" <(jq -Rs '{additional_context: .}' "${routing}"); }; then
		tmp=$(mktemp "${response}.XXXXXX") || return 1
		jq -Rs '{additional_context: .}' "${routing}" >"${tmp}"
		mv "${tmp}" "${response}"
	fi

	requested="${cursor_dir}/hooks.json"
	hooks=$(resolve_target "${requested}")
	command='cat ./hooks/agent-ready-session-start.json'
	if [ -f "${hooks}" ]; then
		merged=$(jq --arg command "${command}" '
			if type != "object" then error("hooks.json root must be an object") else . end
			| .hooks = (.hooks // {})
			| if ((.hooks.sessionStart // []) | type) != "array"
				then error("hooks.sessionStart must be an array") else . end
			| .version = (.version // 1)
			| .hooks.sessionStart = ([.hooks.sessionStart[]?
				| select((type != "object") or (.command != $command))]
				+ [{"command": $command}])
		' "${hooks}") || return 1
	else
		merged=$(jq -n --arg command "${command}" '{version: 1, hooks: {sessionStart: [{command: $command}]}}') || return 1
	fi
	if [ -f "${hooks}" ] && [ "${merged}" = "$(cat "${hooks}")" ]; then
		printf 'Cursor: routing hook already configured in %s\n' "${requested}"
	else
		mkdir -p "$(dirname -- "${hooks}")"
		tmp=$(mktemp "${hooks}.XXXXXX") || return 1
		if [ -f "${hooks}" ] && ! cp -p "${hooks}" "${tmp}"; then
			rm -f "${tmp}"
			return 1
		fi
		printf '%s\n' "${merged}" >"${tmp}" || {
			rm -f "${tmp}"
			return 1
		}
		mv "${tmp}" "${hooks}"
		printf 'Cursor: configured routing hook in %s\n' "${requested}"
	fi

	remove_block "${cursor_dir}/AGENTS.md" "Cursor"
}

# CodeGraph's installer knows each agent's MCP config shape, including
# OpenCode 2's `mcp.servers` migration, so the wiring is delegated to it rather
# than reimplemented here. --no-permissions keeps it out of the agent's
# auto-allow list. The installer reports its own run, so telemetry is off for that
# run through the environment and then off for good through the saved choice.
codegraph_target() {
	case "$1" in
	claude | codex | cursor | opencode | gemini | antigravity) printf '%s\n' "$1" ;;
	copilot) printf 'copilot-cli\n' ;;
	esac
}

configure_codegraph() {
	local id target targets=
	command -v codegraph >/dev/null 2>&1 || return 0
	# Auto would wire OpenCode too, so that one case names the detected agents instead.
	if [ "${auto_detection}" -eq 1 ] && ! opencode_codegraph_hides; then
		targets=auto
	else
		for id in ${selected_agents}; do
			if [ "${id}" = opencode ] && opencode_codegraph_hides; then
				printf 'CodeGraph: skipped MCP setup for OpenCode, because its AGENTS.md would hide %s; the CLI routing still applies\n' "${HOME}/.claude/CLAUDE.md" >&2
				continue
			fi
			target=$(codegraph_target "${id}")
			if [ -n "${target}" ]; then
				targets="${targets}${targets:+,}${target}"
			elif [ "${auto_detection}" -eq 0 ]; then
				printf 'CodeGraph: MCP setup is not available for %s; the CLI routing still applies\n' "${id}" >&2
			fi
		done
	fi
	if [ -n "${targets}" ]; then
		CODEGRAPH_TELEMETRY=0 codegraph install --yes --target="${targets}" --location=global --no-permissions ||
			printf 'CodeGraph: MCP setup failed; run codegraph install manually\n' >&2
	fi
	codegraph telemetry off >/dev/null 2>&1 ||
		printf 'CodeGraph: could not disable telemetry; run codegraph telemetry off\n' >&2
}

# ---------------------------------------------------------------- uninstall
# Uninstall removes only what this repository wrote: the managed blocks, its
# own Cursor hook entry, and agent-ready's state. Tools and third-party
# configuration stay; the exact commands to remove them are printed instead.

uninstall_bin_dir="${AGENT_READY_BIN_DIR:-${HOME}/.local/bin}"
uninstall_versions_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/agent-ready/versions"
uninstall_launcher="${uninstall_bin_dir}/agent-ready"
uninstall_agents=
uninstall_receipt_present=0

uninstall_launcher_owned() {
	local target
	[ -L "${uninstall_launcher}" ] || return 1
	target=$(resolve_target "${uninstall_launcher}") || return 1
	case "${target}" in
	"${uninstall_versions_dir}"/*) return 0 ;;
	esac
	return 1
}

uninstall_cursor_entry_present() {
	local hooks="${HOME}/.cursor/hooks.json"
	[ -f "${hooks}" ] && grep -qF 'cat ./hooks/agent-ready-session-start.json' "${hooks}"
}

uninstall_cursor_present() {
	local response="${HOME}/.cursor/hooks/agent-ready-session-start.json"
	local legacy="${HOME}/.cursor/AGENTS.md" state
	if [ -f "${response}" ] || [ -L "${response}" ]; then
		return 0
	fi
	if [ -f "${legacy}" ] || [ -L "${legacy}" ]; then
		state=$(block_state "${legacy}")
		if [ "${state}" != absent ]; then
			return 0
		fi
	fi
	uninstall_cursor_entry_present
}

# The receipt's configured agents, plus every agent whose file still carries
# agent-ready markers: an earlier install without a receipt, or one run with a
# different --agent, may have left a block the receipt does not name.
uninstall_collect_agents() {
	local id path state
	uninstall_agents=
	for id in ${agent_ids}; do
		if [ "${uninstall_receipt_present}" -eq 1 ]; then
			case ",${receipt_configured}," in
			*",${id},"*)
				uninstall_agents="${uninstall_agents} ${id}"
				continue
				;;
			esac
		fi
		if [ "${id}" = cursor ]; then
			if uninstall_cursor_present; then
				uninstall_agents="${uninstall_agents} ${id}"
			fi
			continue
		fi
		# Gemini and Antigravity share one file: markers there name one agent,
		# Antigravity only when the receipt says it alone configured the file, or
		# when GEMINI_CLI_HOME has moved Gemini's file away from it.
		[ "${id}" != antigravity ] || [ -n "${GEMINI_CLI_HOME:-}" ] || continue
		if [ "${id}" = gemini ] && [ "${uninstall_receipt_present}" -eq 1 ]; then
			case ",${receipt_configured}," in
			*,antigravity,*) continue ;;
			esac
		fi
		while IFS= read -r path; do
			[ -f "${path}" ] || [ -L "${path}" ] || continue
			state=$(block_state "${path}") || state=invalid
			if [ "${state}" != absent ]; then
				uninstall_agents="${uninstall_agents} ${id}"
				break
			fi
		done < <(agent_all_instructions "${id}")
	done
}

agent_all_instructions() {
	agent_instructions "$1"
	agent_stale_instructions "$1"
}

uninstall_preflight_instruction() {
	local id="$1" label requested
	label=$(agent_label "${id}")
	while IFS= read -r requested; do
		uninstall_preflight_file "${label}" "${requested}"
	done < <(agent_all_instructions "${id}")
}

uninstall_preflight_file() {
	local label="$1" requested="$2" target state
	[ -f "${requested}" ] || [ -L "${requested}" ] || return 0
	target=$(resolve_target "${requested}") || {
		preflight_blocked "${label}" "${requested}" other "unresolvable symlink"
		return 0
	}
	[ -f "${target}" ] || return 0
	state=$(block_state "${target}") || state=invalid
	case "${state}" in
	absent) ;;
	invalid) preflight_blocked "${label}" "${requested}" markers "" ;;
	present)
		if [ "${force}" -eq 0 ] && block_has_local_edits "${target}"; then
			preflight_blocked "${label}" "${requested}" edits ""
			return 0
		fi
		preflight_write "${label}" "would remove" "${requested}" "${target}"
		;;
	esac
}

uninstall_preflight_cursor() {
	local cursor_dir="${HOME}/.cursor" requested legacy response hooks target state header digest
	legacy="${cursor_dir}/AGENTS.md"
	if [ -f "${legacy}" ] || [ -L "${legacy}" ]; then
		target=$(resolve_target "${legacy}") || target=
		if [ -z "${target}" ]; then
			preflight_blocked "Cursor" "${legacy}" other "unresolvable symlink"
		elif [ -f "${target}" ]; then
			state=$(block_state "${target}") || state=invalid
			case "${state}" in
			absent) ;;
			invalid) preflight_blocked "Cursor" "${legacy}" markers "" ;;
			present)
				header=$(block_first_line "${target}")
				if block_has_header "${header}"; then
					digest="${header#* sha256:}"
					digest="${digest%% -->*}"
					if [ "${digest}" != "$(block_body_hash "${target}")" ] && [ "${force}" -eq 0 ]; then
						preflight_blocked "Cursor" "${legacy}" edits ""
					else
						preflight_write "Cursor" "would remove legacy routing block from" "${legacy}" "${target}"
					fi
				else
					preflight_write "Cursor" "would remove legacy routing block from" "${legacy}" "${target}"
				fi
				;;
			esac
		fi
	fi
	requested="${cursor_dir}/hooks.json"
	if [ -f "${requested}" ] || [ -L "${requested}" ]; then
		hooks=$(resolve_target "${requested}") || hooks=
		if [ -z "${hooks}" ]; then
			preflight_blocked "Cursor" "${requested}" other "unresolvable symlink"
		elif ! command -v jq >/dev/null 2>&1; then
			if uninstall_cursor_entry_present; then
				preflight_blocked "Cursor" "${requested}" other "jq is required to edit hooks.json"
			fi
		elif ! jq -e -s '
			length == 1
			and (.[0] | type == "object")
			and (((.[0].hooks // {}).sessionStart // []) | type) == "array"
		' "${hooks}" >/dev/null 2>&1; then
			preflight_blocked "Cursor" "${requested}" other "hooks.json must be a JSON object whose hooks.sessionStart is an array or absent"
		elif jq -e --arg command 'cat ./hooks/agent-ready-session-start.json' \
			'([.hooks.sessionStart[]? | select((type == "object") and (.command == $command))] | length) > 0' \
			"${hooks}" >/dev/null 2>&1; then
			preflight_write "Cursor" "would remove the session hook" "${requested}" "${hooks}"
		fi
	fi
	response="${cursor_dir}/hooks/agent-ready-session-start.json"
	if [ -f "${response}" ] || [ -L "${response}" ]; then
		preflight_write "Cursor" "would remove" "${response}" "${response}"
	fi
}

uninstall_remove_instruction() {
	local id="$1" label requested target state
	label=$(agent_label "${id}")
	while IFS= read -r requested; do
		[ -e "${requested}" ] || [ -L "${requested}" ] || continue
		target=$(resolve_target "${requested}") || return 1
		[ -f "${target}" ] || continue
		state=$(block_state "${target}") || state=invalid
		[ "${state}" = present ] || continue
		remove_block "${requested}" "${label}" || return 1
	done < <(agent_all_instructions "${id}")
}

uninstall_remove_cursor() {
	local cursor_dir="${HOME}/.cursor" requested response legacy hooks tmp
	local command='cat ./hooks/agent-ready-session-start.json'
	legacy="${cursor_dir}/AGENTS.md"
	remove_block "${legacy}" "Cursor" || return 1

	requested="${cursor_dir}/hooks.json"
	if [ -e "${requested}" ] || [ -L "${requested}" ]; then
		hooks=$(resolve_target "${requested}") || return 1
		if [ -f "${hooks}" ] && command -v jq >/dev/null 2>&1 &&
			jq -e --arg command "${command}" \
				'([.hooks.sessionStart[]? | select((type == "object") and (.command == $command))] | length) > 0' \
				"${hooks}" >/dev/null 2>&1; then
			tmp=$(mktemp "${hooks}.XXXXXX") || return 1
			cp -p "${hooks}" "${tmp}"
			if ! jq --arg command "${command}" '
				if type != "object" then error("hooks.json root must be an object") else . end
				| .hooks = (.hooks // {})
				| if ((.hooks.sessionStart // []) | type) != "array"
					then error("hooks.sessionStart must be an array") else . end
				| .hooks.sessionStart = ([.hooks.sessionStart[]?
					| select((type != "object") or (.command != $command))])
			' "${hooks}" >"${tmp}"; then
				rm -f "${tmp}"
				return 1
			fi
			mv "${tmp}" "${hooks}" || {
				rm -f "${tmp}"
				return 1
			}
			printf 'Cursor: removed the session hook from %s\n' "${requested}"
		fi
	fi

	response="${cursor_dir}/hooks/agent-ready-session-start.json"
	if [ -e "${response}" ] || [ -L "${response}" ]; then
		rm -f -- "${response}"
		printf 'Cursor: removed %s\n' "${response}"
	fi
}

uninstall_action() {
	local what="$1" path="$2"
	if [ "${dry_run}" -eq 1 ]; then
		printf 'would remove %s %s\n' "${what}" "${path}"
	else
		rm -rf -- "${path}"
		printf 'removed %s %s\n' "${what}" "${path}"
	fi
}

# The tool state files describe installs that are still useful on their own, so
# they outlive the configuration they came with.
uninstall_state_files() {
	local config="$1" state bin keep
	state="${config}/codegraph"
	if [ -f "${state}" ]; then
		if [ -e "${uninstall_bin_dir}/codegraph" ] || command -v codegraph >/dev/null 2>&1; then
			printf 'keeping %s: codegraph is still installed\n' "${state}"
		else
			uninstall_action "codegraph state" "${state}"
		fi
	fi
	state="${config}/binaries"
	if [ -f "${state}" ]; then
		keep=0
		for bin in jq rtk uv uvx sd rg ast-grep gh wt git-wt gitleaks actionlint shellcheck difft yq mdq hyperfine osv-scanner; do
			if [ -e "${uninstall_bin_dir}/${bin}" ]; then
				keep=1
				break
			fi
		done
		if [ "${keep}" -eq 1 ]; then
			printf 'keeping %s: its tools are still installed\n' "${state}"
		else
			uninstall_action "binaries state" "${state}"
		fi
	fi
}

uninstall_state() {
	local receipt config
	receipt=$(receipt_path)
	config=$(dirname -- "${receipt}")
	if [ -e "${receipt}" ] || [ -L "${receipt}" ]; then
		uninstall_action "receipt" "${receipt}"
	fi
	if [ -e "${config}/languages" ] || [ -L "${config}/languages" ]; then
		uninstall_action "languages state" "${config}/languages"
	fi
	if [ -L "${uninstall_launcher}" ]; then
		if uninstall_launcher_owned; then
			uninstall_action "launcher" "${uninstall_launcher}"
		else
			printf 'keeping %s: it was not installed by agent-ready\n' "${uninstall_launcher}"
		fi
	elif [ -e "${uninstall_launcher}" ]; then
		printf 'keeping %s: it was not installed by agent-ready\n' "${uninstall_launcher}"
	fi
	uninstall_state_files "${config}"
	# Last, because a release install runs this tree from inside it.
	if [ -e "${uninstall_versions_dir}" ] || [ -L "${uninstall_versions_dir}" ]; then
		uninstall_action "versions directory" "${uninstall_versions_dir}"
	fi
}

uninstall_tools_hint() {
	local mode bin formula names='' paths='' bundle gemini_file formulae='' target targets=''
	mode="${receipt_tools:-$(receipt_legacy_tools)}"
	if [ "${mode}" = brew ]; then
		# A tool on PATH may not come from Homebrew, and one unknown name makes
		# brew uninstall refuse the whole list.
		if command -v brew >/dev/null 2>&1; then
			formulae=$(brew list --formula -1 2>/dev/null || true)
		fi
		for formula in rtk ripgrep ast-grep sd uv jq yq mdq gh worktrunk difftastic gitleaks \
			actionlint shellcheck hyperfine osv-scanner coreutils gopls; do
			printf '%s\n' "${formulae}" | grep -qFx "${formula}" || continue
			names="${names}${names:+ }${formula}"
		done
		if [ -n "${names}" ]; then
			printf '\nTools are still installed; agent-ready does not remove them:\n'
			printf '  brew uninstall %s\n' "${names}"
		fi
	# A configure-only install put nothing here, so whatever is there is the user's.
	elif [ "${mode}" = binaries ]; then
		for bin in rtk rg ast-grep sd uv uvx jq yq mdq gh wt git-wt difft gitleaks \
			actionlint shellcheck hyperfine osv-scanner gopls; do
			[ ! -e "${uninstall_bin_dir}/${bin}" ] ||
				paths="${paths}${paths:+ }$(printf '%q' "${uninstall_bin_dir}/${bin}")"
		done
		if [ -n "${paths}" ]; then
			printf '\nTools are still installed; agent-ready does not remove them:\n'
			printf '  rm %s\n' "${paths}"
		fi
	fi
	# Only a link into the bundle is ours; any other codegraph is the user's.
	bundle="${AGENT_READY_CODEGRAPH_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/agent-ready/codegraph}"
	case "$(readlink "${uninstall_bin_dir}/codegraph" 2>/dev/null || true)" in
	"${bundle}"/*) printf '  codegraph bundle: rm -rf %q %q\n' "${bundle}" "${uninstall_bin_dir}/codegraph" ;;
	*)
		[ ! -e "${bundle}" ] || printf '  codegraph bundle: rm -rf %q\n' "${bundle}"
		;;
	esac
	case "$(readlink "${uninstall_bin_dir}/timeout" 2>/dev/null || true)" in
	*/gtimeout) printf '  timeout link: rm %q\n' "${uninstall_bin_dir}/timeout" ;;
	esac
	printf '  RTK integration: rtk init -g --uninstall\n'
	# The plain command reaches only Claude Code, OpenCode, and Cursor.
	for id in ${uninstall_agents}; do
		case "${id}" in
		# rtk 1.1.0 deletes the whole GEMINI.md here, whatever else it holds, and
		# Antigravity reads that file too, so the command keeps a copy around it.
		gemini)
			gemini_file="${HOME}/.gemini/GEMINI.md"
			if [ -e "${gemini_file}" ] || [ -L "${gemini_file}" ]; then
				printf '  RTK integration for %s (rtk deletes GEMINI.md, so this restores it): cp -Pp %q %q && rtk init -g --gemini --uninstall; mv %q %q\n' \
					"$(agent_label "${id}")" "${gemini_file}" "${gemini_file}.keep" "${gemini_file}.keep" "${gemini_file}"
			else
				printf '  RTK integration for %s: rtk init -g --gemini --uninstall\n' "$(agent_label "${id}")"
			fi
			;;
		codex | copilot)
			printf '  RTK integration for %s: rtk init -g --%s --uninstall\n' "$(agent_label "${id}")" "${id}"
			;;
		antigravity | pi)
			printf '  RTK integration for %s: rtk init -g --agent %s --uninstall\n' "$(agent_label "${id}")" "${id}"
			;;
		esac
	done
	for id in ${uninstall_agents}; do
		target=$(codegraph_target "${id}")
		[ -z "${target}" ] || targets="${targets}${targets:+,}${target}"
	done
	if [ -n "${targets}" ]; then
		printf '  CodeGraph MCP wiring: codegraph uninstall --location global --keep-cli --target %s\n' "${targets}"
	fi
	if [ "${uninstall_go}" -eq 1 ]; then
		for id in ${uninstall_agents}; do
			case "${id}" in
			claude) printf '  gopls MCP for Claude Code: claude mcp remove --scope user gopls\n' ;;
			codex) printf '  gopls MCP for Codex: codex mcp remove gopls\n' ;;
			cursor) printf '  gopls MCP for Cursor: delete mcpServers.gopls from %s\n' "${HOME}/.cursor/mcp.json" ;;
			esac
		done
	fi
}

uninstall_main() {
	local receipt id
	blocked=0
	receipt=$(receipt_path)
	uninstall_receipt_present=0
	if [ -e "${receipt}" ] || [ -L "${receipt}" ]; then
		receipt_read "${receipt}" || return 1
		uninstall_receipt_present=1
	fi
	# Read now, because uninstall_state removes it before the hint is printed.
	uninstall_go=0
	if [ -f "$(dirname -- "${receipt}")/languages/go" ]; then uninstall_go=1; fi
	uninstall_collect_agents
	for id in ${uninstall_agents}; do
		if [ "${id}" = cursor ]; then
			uninstall_preflight_cursor
		else
			uninstall_preflight_instruction "${id}"
		fi
	done
	if [ "${blocked}" -ne 0 ]; then
		return 1
	fi
	if [ "${dry_run}" -eq 1 ]; then
		uninstall_state
		uninstall_tools_hint
		return 0
	fi
	for id in ${uninstall_agents}; do
		if [ "${id}" = cursor ]; then
			uninstall_remove_cursor || return 1
		else
			uninstall_remove_instruction "${id}" || return 1
		fi
	done
	uninstall_state
	uninstall_tools_hint
	kilo_hiding_notice
	opencode_hiding_notice
}

if [ "${uninstall}" -eq 1 ]; then
	uninstall_main
	exit 0
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

# An automatic run repeats what detection finds, but an agent added with --agent
# may not be detectable, and its block would never be refreshed. One the receipt
# names keeps being configured while its block is still there.
agent_has_block() {
	local file state
	if [ "$1" = cursor ]; then
		uninstall_cursor_present
		return
	fi
	file=$(agent_instructions "$1")
	[ -f "${file}" ] || return 1
	state=$(block_state "${file}") || state=invalid
	[ "${state}" != absent ]
}

if [ "${auto_detection}" -eq 1 ]; then
	for id in ${prev_configured//,/ }; do
		if ! agent_selected "${id}" && agent_has_block "${id}"; then
			selected_agents="${selected_agents} ${id}"
		fi
	done
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
	# macOS ships no `timeout`, and agents call it by reflex. coreutils installs it
	# as `gtimeout`; link only that one name, and never over an existing file.
	if [ "${os}" = Darwin ] && ! command -v timeout >/dev/null 2>&1; then
		gtimeout=$(command -v gtimeout || true)
		timeout_link="${AGENT_READY_BIN_DIR:-${HOME}/.local/bin}/timeout"
		if [ -z "${gtimeout}" ]; then
			printf 'timeout: gtimeout not found; skipped\n' >&2
		elif [ -L "${timeout_link}" ] && [ "$(readlink "${timeout_link}")" = "${gtimeout}" ]; then
			printf 'timeout already linked\n'
		elif [ -e "${timeout_link}" ] || [ -L "${timeout_link}" ]; then
			printf 'timeout: keeping the existing %s\n' "${timeout_link}"
		else
			mkdir -p "$(dirname -- "${timeout_link}")"
			ln -s "${gtimeout}" "${timeout_link}"
			printf 'timeout: linked %s to %s\n' "${timeout_link}" "${gtimeout}"
		fi
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
	retire_stale codex
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
if agent_selected antigravity; then
	found=1
	configure_rtk_optional "$(agent_label antigravity)" antigravity
	install_block "$(agent_instructions antigravity)" "$(agent_label antigravity)" "$(agent_block antigravity)"
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
	opencode_hiding_notice
fi
if agent_selected qwen; then
	found=1
	install_block "$(agent_instructions qwen)" "$(agent_label qwen)" "$(agent_block qwen)"
fi
if agent_selected cline; then
	found=1
	install_block "$(agent_instructions cline)" "$(agent_label cline)" "$(agent_block cline)"
	retire_stale cline
fi
if agent_selected kilo; then
	found=1
	install_block "$(agent_instructions kilo)" "$(agent_label kilo)" "$(agent_block kilo)"
	kilo_hiding_notice
fi
if agent_selected crush; then
	found=1
	install_block "$(agent_instructions crush)" "$(agent_label crush)" "$(agent_block crush)"
fi
if agent_selected goose; then
	found=1
	install_block "$(agent_instructions goose)" "$(agent_label goose)" "$(agent_block goose)"
fi
if agent_selected dsh; then
	found=1
	install_block "$(agent_instructions dsh)" "$(agent_label dsh)" "$(agent_block dsh)"
fi
if agent_selected pi; then
	found=1
	configure_rtk_optional "$(agent_label pi)" pi
	install_block "$(agent_instructions pi)" "$(agent_label pi)" "$(agent_block pi)"
	retire_stale pi
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
