#!/usr/bin/env bash
set -euo pipefail

# Authorized local research entry point. Credentials are opened only by the
# ForwardTest process through DeskCredentials; they are never placed in this
# shell environment and are not available to the build process.
if [[ "${OANDA_ENV:-practice}" != "practice" ]]; then
  echo "OANDA_ENV must be practice for ForwardTest research" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${repo_root}/.build/out/Products/Release/ForwardTest"
if [[ ! -x "$binary" ]]; then
  swift build -c release --target ForwardTest >/dev/null
fi

exec "$binary" "$@"
