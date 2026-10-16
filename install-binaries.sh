#!/usr/bin/env bash
# install-binaries.sh — install the generic tools on Linux without Homebrew.
#
# Each tool comes from its latest upstream GitHub release. Every download is
# checked against the SHA-256 digest GitHub records for that release asset
# before it is unpacked, then installed atomically into one directory
# (~/.local/bin by default). Root is not required and nothing else on the
# system is touched; the installed release tags are recorded under
# ~/.config/agent-ready so --upgrade only downloads what changed.
#
# Usage: install-binaries.sh [--upgrade]

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
state="${state_dir}/binaries"
api="${AGENT_READY_GITHUB_API:-https://api.github.com}"

# name, repository, installed binaries, then the release asset for x86_64 and
# aarch64 as anchored regexes ("-" where upstream publishes none). Static musl
# builds are preferred where they exist.
tools() {
	cat <<'EOF'
jq jqlang/jq jq ^jq-linux-amd64$ ^jq-linux-arm64$
rtk rtk-ai/rtk rtk ^rtk-x86_64-unknown-linux-musl\.tar\.gz$ ^rtk-aarch64-unknown-linux-gnu\.tar\.gz$
uv astral-sh/uv uv,uvx ^uv-x86_64-unknown-linux-musl\.tar\.gz$ ^uv-aarch64-unknown-linux-musl\.tar\.gz$
sd chmln/sd sd ^sd-v[^-]+-x86_64-unknown-linux-musl\.tar\.gz$ ^sd-v[^-]+-aarch64-unknown-linux-musl\.tar\.gz$
ripgrep BurntSushi/ripgrep rg ^ripgrep-[^-]+-x86_64-unknown-linux-musl\.tar\.gz$ ^ripgrep-[^-]+-aarch64-unknown-linux-musl\.tar\.gz$
ast-grep ast-grep/ast-grep ast-grep ^app-x86_64-unknown-linux-gnu\.zip$ ^app-aarch64-unknown-linux-gnu\.zip$
gh cli/cli gh ^gh_[^_]+_linux_amd64\.tar\.gz$ ^gh_[^_]+_linux_arm64\.tar\.gz$
worktrunk max-sixty/worktrunk wt,git-wt ^worktrunk-x86_64-unknown-linux-musl\.tar\.xz$ ^worktrunk-aarch64-unknown-linux-musl\.tar\.xz$
gitleaks gitleaks/gitleaks gitleaks ^gitleaks_[^_]+_linux_x64\.tar\.gz$ ^gitleaks_[^_]+_linux_arm64\.tar\.gz$
actionlint rhysd/actionlint actionlint ^actionlint_[^_]+_linux_amd64\.tar\.gz$ ^actionlint_[^_]+_linux_arm64\.tar\.gz$
shellcheck koalaman/shellcheck shellcheck ^shellcheck-v[^.]+\.[^.]+\.[^.]+\.linux\.x86_64\.tar\.gz$ ^shellcheck-v[^.]+\.[^.]+\.[^.]+\.linux\.aarch64\.tar\.gz$
difftastic Wilfred/difftastic difft ^difft-[^-]+-x86_64-unknown-linux-musl\.tar\.gz$ ^difft-[^-]+-aarch64-unknown-linux-gnu\.tar\.gz$
yq mikefarah/yq yq ^yq_linux_amd64$ ^yq_linux_arm64$
mdq yshavit/mdq mdq ^mdq-linux-x64-musl\.tar\.gz$ -
hyperfine sharkdp/hyperfine hyperfine ^hyperfine-v[^-]+-x86_64-unknown-linux-musl\.tar\.gz$ ^hyperfine-v[^-]+-aarch64-unknown-linux-musl\.tar\.gz$
EOF
}

die() {
	printf '%s\n' "$*" >&2
	exit 1
}

case "${AGENT_READY_ARCH:-$(uname -m)}" in
x86_64 | amd64) arch=x86_64 ;;
aarch64 | arm64) arch=aarch64 ;;
*) die "unsupported architecture: $(uname -m) (x86_64 and aarch64 are supported)" ;;
esac

# Check every prerequisite before the first download, and name them all at once.
missing=
for command in curl tar gzip xz; do
	command -v "${command}" >/dev/null 2>&1 || missing="${missing} ${command}"
done
command -v unzip >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1 || missing="${missing} unzip"
command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || missing="${missing} sha256sum"
if [ -n "${missing}" ]; then
	printf 'missing:%s\n' "${missing}" >&2
	printf 'Debian/Ubuntu: apt-get install -y curl ca-certificates xz-utils unzip\n' >&2
	printf 'Fedora/RHEL:   dnf install -y curl xz unzip\n' >&2
	printf 'Alpine:        apk add bash curl xz unzip gcompat\n' >&2
	exit 1
fi

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	else
		shasum -a 256 "$1" | cut -d' ' -f1
	fi
}

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
mkdir -p "${bin_dir}" "${state_dir}"

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

recorded_tag() { awk -v n="$1" '$1 == n { print $2 }' "${state}" 2>/dev/null || true; }

record_tag() {
	local tmp
	tmp=$(mktemp "${state}.XXXXXX")
	{
		awk -v n="$1" '$1 != n' "${state}" 2>/dev/null || true
		printf '%s %s\n' "$1" "$2"
	} >"${tmp}"
	mv "${tmp}" "${state}"
}

have_all() {
	local bin
	for bin in ${1//,/ }; do
		[ -x "${bin_dir}/${bin}" ] || return 1
	done
}

place() {
	local src="$1" bin="$2" tmp
	tmp=$(mktemp "${bin_dir}/.${bin}.XXXXXX")
	cp "${src}" "${tmp}"
	chmod 755 "${tmp}"
	mv -f "${tmp}" "${bin_dir}/${bin}"
}

unpack() {
	local file="$1" name="$2" dir="$3"
	mkdir -p "${dir}"
	case "${name}" in
	*.tar.gz | *.tgz) tar -xzf "${file}" -C "${dir}" ;;
	*.tar.xz) tar -xJf "${file}" -C "${dir}" ;;
	*.zip)
		if command -v unzip >/dev/null 2>&1; then
			unzip -q "${file}" -d "${dir}"
		else
			python3 -m zipfile -e "${file}" "${dir}"
		fi
		;;
	*) return 1 ;;
	esac
}

# jq reads every other release; without one, take jq itself from its release,
# checked against the sha256sum.txt published with it.
jq_bin=$( { [ -x "${bin_dir}/jq" ] && printf "%s\n" "${bin_dir}/jq"; } || command -v jq || true)
bootstrap_jq() {
	local regex="$1" json="${work}/jq.json" url sums tag
	fetch "${api}/repos/jqlang/jq/releases/latest" "${json}"
	tag=$(grep -o '"tag_name": *"[^"]*"' "${json}" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
	url=$(grep -o '"browser_download_url": *"[^"]*"' "${json}" | sed 's/.*"\([^"]*\)"$/\1/' |
		grep -E "/${regex#^}" | head -1)
	sums=$(grep -o '"browser_download_url": *"[^"]*/sha256sum\.txt"' "${json}" | sed 's/.*"\([^"]*\)"$/\1/')
	[ -n "${tag}" ] && [ -n "${url}" ] && [ -n "${sums}" ] || die "jq: release layout not recognised"
	fetch "${url}" "${work}/jq.bin"
	fetch "${sums}" "${work}/jq.sums"
	[ "$(sha256 "${work}/jq.bin")" = "$(awk -v f="${url##*/}" '$2 == f { print $1 }' "${work}/jq.sums")" ] ||
		die "jq: checksum mismatch for ${url##*/}; nothing installed"
	place "${work}/jq.bin" jq
	record_tag jq "${tag}"
	jq_bin="${bin_dir}/jq"
	printf 'jq %s installed\n' "${tag}"
}

install_tool() {
	local name="$1" repo="$2" bins="$3" regex="$4"
	local json="${work}/${name}.json" tag asset asset_name url digest file dir bin found
	if [ "${regex}" = - ]; then
		printf '%s: no Linux %s build is published upstream; skipped\n' "${name}" "${arch}" >&2
		return 0
	fi
	if [ "${upgrade}" -eq 0 ] && have_all "${bins}"; then
		printf '%s already installed\n' "${name}"
		return 0
	fi
	if [ -z "${jq_bin}" ]; then
		[ "${name}" = jq ] || die "jq is required before ${name}"
		bootstrap_jq "${regex}"
		return 0
	fi

	fetch "${api}/repos/${repo}/releases/latest" "${json}"
	tag=$("${jq_bin}" -r '.tag_name // empty' "${json}")
	[ -n "${tag}" ] || die "${name}: no release found for ${repo}"
	if [ "${upgrade}" -eq 1 ] && [ "$(recorded_tag "${name}")" = "${tag}" ] && have_all "${bins}"; then
		printf '%s %s is up to date\n' "${name}" "${tag}"
		return 0
	fi

	# shellcheck disable=SC2016 # $re is a jq variable
	asset=$("${jq_bin}" -c --arg re "${regex}" '[.assets[] | select(.name | test($re))]' "${json}")
	[ "$("${jq_bin}" length <<<"${asset}")" -eq 1 ] ||
		die "${name}: expected one release asset matching ${regex} in ${repo} ${tag}, found $("${jq_bin}" length <<<"${asset}")"
	asset_name=$("${jq_bin}" -r '.[0].name' <<<"${asset}")
	url=$("${jq_bin}" -r '.[0].browser_download_url' <<<"${asset}")
	digest=$("${jq_bin}" -r '.[0].digest // empty' <<<"${asset}")
	case "${digest}" in
	sha256:*) ;;
	*) die "${name}: GitHub publishes no SHA-256 digest for ${asset_name}; refusing to install it" ;;
	esac

	file="${work}/${asset_name}"
	fetch "${url}" "${file}"
	[ "$(sha256 "${file}")" = "${digest#sha256:}" ] ||
		die "${name}: checksum mismatch for ${asset_name}; nothing installed"

	dir="${work}/${name}"
	if unpack "${file}" "${asset_name}" "${dir}"; then
		for bin in ${bins//,/ }; do
			found=$(find "${dir}" -type f -name "${bin}" | head -1)
			[ -n "${found}" ] || die "${name}: ${bin} not found in ${asset_name}"
			place "${found}" "${bin}"
		done
	else
		# A bare executable: the asset is the only binary of this tool.
		place "${file}" "${bins}"
	fi
	record_tag "${name}" "${tag}"
	printf '%s %s installed\n' "${name}" "${tag}"
}

while read -r name repo bins x86_64 aarch64; do
	if [ "${arch}" = x86_64 ]; then
		install_tool "${name}" "${repo}" "${bins}" "${x86_64}" </dev/null
	else
		install_tool "${name}" "${repo}" "${bins}" "${aarch64}" </dev/null
	fi
done < <(tools)

case ":${PATH}:" in
*":${bin_dir}:"*) ;;
*) # shellcheck disable=SC2016 # $PATH is printed literally for the profile
	printf '\n%s is not on PATH. Add this to your shell profile:\n  export PATH="%s:$PATH"\n' "${bin_dir}" "${bin_dir}" ;;
esac
