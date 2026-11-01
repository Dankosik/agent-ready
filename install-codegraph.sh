#!/usr/bin/env bash
# install-codegraph.sh — install the self-contained CodeGraph release bundle.
#
# CodeGraph publishes no Homebrew formula. Upstream ships one archive per
# platform, each carrying its own Node runtime, so this installer resolves the
# latest release through the GitHub API, checks the downloaded archive against
# the SHA-256 digest GitHub records for that asset, unpacks it into a versioned
# directory, and links only the launcher onto PATH. The installed tag is
# recorded under ~/.config/agent-ready so --upgrade only touches an install this
# script owns; a codegraph from npm or the upstream installer is not replaced.
#
# Usage: install-codegraph.sh [--upgrade]

set -euo pipefail

upgrade=0
case "${1:-}" in
"") ;;
--upgrade) upgrade=1 ;;
*)
	printf 'usage: %s [--upgrade]\n' "$0" >&2
	exit 2
	;;
esac

bin_dir="${AGENT_READY_BIN_DIR:-${HOME}/.local/bin}"
state_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/agent-ready"
state="${state_dir}/codegraph"
bundle_root="${AGENT_READY_CODEGRAPH_DIR:-${XDG_DATA_HOME:-${HOME}/.local/share}/agent-ready/codegraph}"
api="${AGENT_READY_GITHUB_API:-https://api.github.com}"
launcher="${bin_dir}/codegraph"

die() {
	printf '%s\n' "$*" >&2
	exit 1
}

platform="${AGENT_READY_OS:-$(uname -s)}"
case "${platform}" in
Darwin) os=darwin ;;
Linux) os=linux ;;
*) die "unsupported platform: ${platform} (macOS and Linux are supported)" ;;
esac
machine="${AGENT_READY_ARCH:-$(uname -m)}"
case "${machine}" in
x86_64 | amd64) arch=x64 ;;
aarch64 | arm64) arch=arm64 ;;
*) die "unsupported architecture: ${machine} (x86_64 and arm64 are supported)" ;;
esac
asset="codegraph-${os}-${arch}.tar.gz"

recorded=$(cat "${state}" 2>/dev/null || true)

# A codegraph this script did not install belongs to the user (npm or the
# upstream installer). Keep it rather than shadowing it with a second copy.
if [ -e "${launcher}" ] || [ -L "${launcher}" ]; then
	if [ -z "${recorded}" ]; then
		printf 'codegraph: keeping the existing installation at %s\n' "${launcher}"
		exit 0
	fi
	if [ "${upgrade}" -eq 0 ] && [ -x "${bundle_root}/versions/${recorded}/bin/codegraph" ]; then
		printf 'codegraph %s already installed\n' "${recorded}"
		exit 0
	fi
fi

PATH="${bin_dir}:${PATH}"
for command in curl tar gzip jq; do
	command -v "${command}" >/dev/null 2>&1 ||
		die "${command} is required to install codegraph; run install.sh first"
done
command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 ||
	die "sha256sum or shasum is required to verify codegraph"

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	else
		shasum -a 256 "$1" | cut -d' ' -f1
	fi
}

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

work=$(mktemp -d)
stage=
cleanup() {
	rm -rf "${work}"
	[ -z "${stage}" ] || rm -rf "${stage}"
}
trap cleanup EXIT
mkdir -p "${bin_dir}" "${state_dir}"

fetch "${api}/repos/colbymchenry/codegraph/releases/latest" "${work}/release.json"
tag=$(jq -r '.tag_name // empty' "${work}/release.json")
[ -n "${tag}" ] || die "codegraph: no release found"
case "${tag}" in
*[!A-Za-z0-9._-]*) die "codegraph: unexpected release tag: ${tag}" ;;
esac

if [ "${upgrade}" -eq 1 ] && [ "${recorded}" = "${tag}" ] && [ -x "${bundle_root}/versions/${tag}/bin/codegraph" ]; then
	printf 'codegraph %s is up to date\n' "${tag}"
	exit 0
fi

# shellcheck disable=SC2016 # $a is a jq variable
release_asset=$(jq -c --arg a "${asset}" '[.assets[] | select(.name == $a)]' "${work}/release.json")
[ "$(jq length <<<"${release_asset}")" -eq 1 ] ||
	die "codegraph: release ${tag} has no ${asset}"
url=$(jq -r '.[0].browser_download_url' <<<"${release_asset}")
digest=$(jq -r '.[0].digest // empty' <<<"${release_asset}")
case "${digest}" in
sha256:*) ;;
*) die "codegraph: GitHub publishes no SHA-256 digest for ${asset}; refusing to install it" ;;
esac

fetch "${url}" "${work}/${asset}"
[ "$(sha256 "${work}/${asset}")" = "${digest#sha256:}" ] ||
	die "codegraph: checksum mismatch for ${asset}; nothing installed"

dest="${bundle_root}/versions/${tag}"
mkdir -p "${bundle_root}/versions"
stage=$(mktemp -d "${bundle_root}/versions/.${tag}.XXXXXX")
tar -xzf "${work}/${asset}" -C "${stage}" --strip-components=1
[ -x "${stage}/bin/codegraph" ] ||
	die "codegraph: ${asset} does not contain bin/codegraph"

# Swap the bundle in, then point the launcher at it; both stay inside the
# directories this script documents. Older bundles are pruned afterwards.
rm -rf "${dest}"
mv "${stage}" "${dest}"
stage=
link="${bin_dir}/.codegraph.XXXXXX"
tmp_link=$(mktemp "${link}")
rm -f "${tmp_link}"
ln -s "${dest}/bin/codegraph" "${tmp_link}"
mv -f "${tmp_link}" "${launcher}"
for old in "${bundle_root}/versions"/*; do
	[ ! -d "${old}" ] || [ "${old}" = "${dest}" ] || rm -rf "${old}"
done

tmp=$(mktemp "${state}.XXXXXX")
printf '%s\n' "${tag}" >"${tmp}"
mv "${tmp}" "${state}"

printf 'codegraph %s installed\n' "${tag}"

case ":${PATH}:" in
*":${bin_dir}:"*) ;;
*) # shellcheck disable=SC2016 # $PATH is printed literally for the profile
	printf '\n%s is not on PATH. Add this to your shell profile:\n  export PATH="%s:$PATH"\n' "${bin_dir}" "${bin_dir}" ;;
esac
