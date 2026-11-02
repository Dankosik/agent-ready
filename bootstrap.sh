#!/usr/bin/env bash

set -euo pipefail

work=
cleanup() { [ -z "${work}" ] || rm -rf "${work}"; }
trap cleanup EXIT

# A checkout is a bootstrap.sh with install.sh beside it. Anything else,
# including a lone copy, is the documented `curl | bash` download path.
checkout=
verified=0
source_path="${BASH_SOURCE[0]:-}"
if [ -n "${source_path}" ] && [ -f "${source_path}" ]; then
	source_dir=$(cd -- "$(dirname -- "${source_path}")" && pwd)
	if [ -f "${source_dir}/install.sh" ]; then
		checkout="${source_dir}"
	fi
fi

if [ -n "${checkout}" ]; then
	root="${checkout}"
else
	die() {
		printf '%s\n' "$*" >&2
		exit 1
	}

	work=$(mktemp -d)
	archive="${work}/agent-ready.tar.gz"
	listing="${work}/archive.list"
	ref="${AGENT_READY_REF:-main}"
	api="${AGENT_READY_GITHUB_API:-https://api.github.com}"
	repo=Dankosik/agent-ready

	# The token is only ever sent to the real GitHub API, never to an override.
	fetch() {
		local url="$1" out="$2" code token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
		local auth=()
		case "${url}" in
		https://api.github.com/*) [ -z "${token}" ] || auth=(-H "Authorization: Bearer ${token}") ;;
		esac
		code=$(curl -sSL --retry 3 ${auth[@]+"${auth[@]}"} -w '%{http_code}' -o "${out}" "${url}") ||
			die "download failed: ${url}"
		case "${code}" in
		200 | 000) ;;
		403 | 429) die "GitHub API rate limit reached; set GITHUB_TOKEN or retry later (${url})" ;;
		*) die "download failed with HTTP ${code}: ${url}" ;;
		esac
	}

	sha256() {
		if command -v sha256sum >/dev/null 2>&1; then
			sha256sum "$1" | cut -d' ' -f1
		else
			shasum -a 256 "$1" | cut -d' ' -f1
		fi
	}

	# Every string value of one JSON field, one per line. Only used without jq;
	# the release branch explains why reading the response this way is safe.
	json_values() {
		{ grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$2" || true; } |
			sed 's/.*"\([^"]*\)"$/\1/'
	}

	unpack() {
		tar -tzf "${archive}" >"${listing}"
		if grep -Eq '^/|(^|/)\.\.(/|$)' "${listing}"; then
			die "archive contains an unsafe path"
		fi
		tar -xzf "${archive}" -C "${work}"
		root=$(find "${work}" -mindepth 1 -maxdepth 1 -type d -print -quit)
		[ -n "${root}" ] || die "agent-ready installer not found"
	}

	printf 'Downloading agent-ready %s\n' "${ref}"
	if [ -n "${AGENT_READY_ARCHIVE_URL:-}" ]; then
		printf 'agent-ready %s: archive override is not verified\n' "${ref}" >&2
		command -v curl >/dev/null 2>&1 || die "curl is required"
		fetch "${AGENT_READY_ARCHIVE_URL}" "${archive}"
		unpack
	elif [[ "${ref}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		# A release archive is verified before anything inside it runs.
		asset="agent-ready-${ref}.tar.gz"
		missing=
		for command in curl tar gzip; do
			command -v "${command}" >/dev/null 2>&1 || missing="${missing} ${command}"
		done
		command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 ||
			missing="${missing} sha256sum"
		[ -z "${missing}" ] || die "missing:${missing}"
		json="${work}/release.json"
		fetch "${api}/repos/${repo}/releases/tags/${ref}" "${json}"
		if command -v jq >/dev/null 2>&1; then
			# shellcheck disable=SC2016 # $a is a jq variable
			release=$(jq -c --arg a "${asset}" '[.assets[] | select(.name == $a)]' "${json}")
			[ "$(jq length <<<"${release}")" -eq 1 ] ||
				die "agent-ready ${ref} has no verified release archive; use a newer release"
			url=$(jq -r '.[0].browser_download_url' <<<"${release}")
			digest=$(jq -r '.[0].digest // empty' <<<"${release}")
		else
			# A fresh Linux has no jq. grep is enough here only because a release
			# publishes one asset: exactly one digest in the whole response and
			# exactly one download URL for our asset name are required, so any
			# unexpected or ambiguous response fails closed.
			[ "$(json_values name "${json}" | awk -v a="${asset}" '$0 == a { n++ } END { print n + 0 }')" -eq 1 ] ||
				die "agent-ready ${ref} has no verified release archive; use a newer release"
			digests=$(json_values digest "${json}" | awk 'END { print NR + 0 }')
			[ "${digests}" -ne 0 ] ||
				die "agent-ready ${ref}: GitHub publishes no SHA-256 digest for ${asset}; refusing to install it"
			[ "${digests}" -eq 1 ] ||
				die "agent-ready ${ref}: expected one ${asset} digest, found ${digests}"
			digest=$(json_values digest "${json}")
			url=$(json_values browser_download_url "${json}" |
				awk -v a="/${asset}" 'index($0, a) { print; n++ } END { exit n == 1 ? 0 : 1 }') ||
				die "agent-ready ${ref}: expected one download URL for ${asset}"
		fi
		[[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] ||
			die "agent-ready ${ref}: GitHub publishes no SHA-256 digest for ${asset}; refusing to install it"
		fetch "${url}" "${archive}"
		[ "$(sha256 "${archive}")" = "${digest#sha256:}" ] ||
			die "checksum mismatch for ${asset}; nothing installed"
		# Build provenance is an extra check where gh can verify it; the digest
		# above already guards the download when it cannot.
		if [ "${api}" = https://api.github.com ] && command -v gh >/dev/null 2>&1 &&
			gh auth status >/dev/null 2>&1; then
			gh attestation verify "${archive}" --repo "${repo}" >/dev/null ||
				die "agent-ready ${ref}: build provenance verification failed"
		fi
		unpack
		[ "$(cat "${root}/VERSION" 2>/dev/null || true)" = "${ref}" ] ||
			die "agent-ready ${ref}: archive VERSION does not match the tag"
		verified=1
	else
		printf 'agent-ready %s is a development archive and is not verified\n' "${ref}" >&2
		command -v curl >/dev/null 2>&1 || die "curl is required"
		fetch "https://codeload.github.com/${repo}/tar.gz/${ref}" "${archive}"
		unpack
	fi
fi

[ -n "${root}" ] && [ -f "${root}/install.sh" ] && [ -f "${root}/agent-ready" ] ||
	{ printf 'agent-ready installer not found\n' >&2; exit 1; }

# The dispatch lives in agent-ready. A verified release tree also installs that
# command itself; a checkout, a dev ref, or an unverified archive only runs the
# requested install.
if [ "${verified}" -eq 1 ]; then
	bash "${root}/agent-ready" --self-install "$@"
else
	bash "${root}/agent-ready" "$@"
fi
