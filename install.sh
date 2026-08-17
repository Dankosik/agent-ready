#!/usr/bin/env bash

set -euo pipefail

root=$(cd -- "$(dirname -- "$0")" && pwd)

[ "$#" -eq 0 ] || {
	printf 'usage: %s\n' "$0" >&2
	exit 2
}
command -v brew >/dev/null 2>&1 || {
	printf 'Homebrew is required: https://brew.sh\n' >&2
	exit 1
}
brew bundle --file "${root}/Brewfile"
