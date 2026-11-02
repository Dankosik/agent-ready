# shellcheck shell=bash
# The install receipt records how agent-ready configured this machine so a
# later update can repeat the install. It is read as data only: never sourced,
# never evaluated.

receipt_agent_ids='claude codex cursor gemini copilot windsurf grok opencode qwen cline kilo crush goose'

receipt_path() {
	printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/agent-ready/receipt"
}

# An install from v1.2.x or earlier wrote no receipt, so an update can only read
# the tool mode from the machine: the release-binary state file, then Homebrew,
# then nothing. The agents were auto-detected by that installer.
receipt_legacy_tools() {
	local config
	config=$(dirname -- "$(receipt_path)")
	if [ -f "${config}/binaries" ]; then
		printf 'binaries\n'
	elif command -v brew >/dev/null 2>&1; then
		printf 'brew\n'
	else
		printf 'none\n'
	fi
}

receipt_valid_version() {
	[[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

receipt_valid_timestamp() {
	[[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

receipt_valid_agent_list() {
	local list="$1" item rest
	[ -n "${list}" ] || return 0
	case "${list}" in
	*, | ,*) return 1 ;;
	esac
	rest="${list},"
	while [ -n "${rest}" ]; do
		item="${rest%%,*}"
		rest="${rest#*,}"
		case " ${receipt_agent_ids} " in
		*" ${item} "*) ;;
		*) return 1 ;;
		esac
	done
}

receipt_valid_agents() {
	case "$1" in
	auto) return 0 ;;
	'') return 1 ;;
	esac
	receipt_valid_agent_list "$1"
}

receipt_valid_languages() {
	local list="$1" item rest
	[ -n "${list}" ] || return 0
	case "${list}" in
	*, | ,*) return 1 ;;
	esac
	rest="${list},"
	while [ -n "${rest}" ]; do
		item="${rest%%,*}"
		rest="${rest#*,}"
		case "${item}" in
		'' | *[!a-z0-9_-]*) return 1 ;;
		esac
	done
}

# Strict reader: only known keys, only valid values, and the file is never
# executed. Returns non-zero and names the file on anything unexpected.
# shellcheck disable=SC2034 # receipt_* are read by the sourcing script
receipt_read() {
	local file="$1" line key value bad=0 schema='' version='' agents='' configured=''
	local languages='' tools='' updated_at='' seen=' '
	receipt_version=
	receipt_agents=
	receipt_configured=
	receipt_languages=
	receipt_tools=
	receipt_updated_at=
	[ -f "${file}" ] || bad=1
	if [ "${bad}" -eq 0 ]; then
		while IFS= read -r line || [ -n "${line}" ]; do
			[ -n "${line}" ] || continue
			case "${line}" in
			*=*) ;;
			*)
				bad=1
				break
				;;
			esac
			key="${line%%=*}"
			value="${line#*=}"
			case " ${seen} " in
			*" ${key} "*)
				bad=1
				break
				;;
			esac
			seen="${seen}${key} "
			case "${key}" in
			schema)
				if [ "${value}" = 1 ]; then schema=1; else bad=1; fi
				;;
			version)
				if receipt_valid_version "${value}"; then version="${value}"; else bad=1; fi
				;;
			agents)
				if receipt_valid_agents "${value}"; then agents="${value}"; else bad=1; fi
				;;
			configured)
				if receipt_valid_agent_list "${value}"; then configured="${value}"; else bad=1; fi
				;;
			languages)
				if receipt_valid_languages "${value}"; then languages="${value}"; else bad=1; fi
				;;
			tools)
				case "${value}" in
				brew | binaries | none) tools="${value}" ;;
				*) bad=1 ;;
				esac
				;;
			updated_at)
				if receipt_valid_timestamp "${value}"; then updated_at="${value}"; else bad=1; fi
				;;
			*)
				bad=1
				;;
			esac
			[ "${bad}" -eq 0 ] || break
		done <"${file}"
	fi
	if [ "${bad}" -eq 0 ] && { [ -z "${schema}" ] || [ -z "${version}" ]; }; then
		bad=1
	fi
	if [ "${bad}" -ne 0 ]; then
		printf 'malformed agent-ready receipt: %s\n' "${file}" >&2
		return 1
	fi
	receipt_version="${version}"
	receipt_agents="${agents}"
	receipt_configured="${configured}"
	receipt_languages="${languages}"
	receipt_tools="${tools}"
	receipt_updated_at="${updated_at}"
}

# Same-directory temporary file plus an atomic move, so an interrupted write
# leaves the previous receipt intact.
receipt_write() {
	local file="$1" tmp
	mkdir -p "$(dirname -- "${file}")" || return 1
	tmp=$(mktemp "${file}.XXXXXX") || return 1
	{
		printf 'schema=1\n'
		printf 'version=%s\n' "$2"
		printf 'agents=%s\n' "$3"
		printf 'configured=%s\n' "$4"
		printf 'languages=%s\n' "$5"
		printf 'tools=%s\n' "$6"
		printf 'updated_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	} >"${tmp}" || {
		rm -f "${tmp}"
		return 1
	}
	mv "${tmp}" "${file}"
}
