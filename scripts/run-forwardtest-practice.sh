#!/usr/bin/env bash
set -euo pipefail

# Noninteractive research entry point. Credentials must be supplied by the
# operator's approved secret injector; this script never prints or persists
# them and never falls back to the app's access-controlled Keychain item.
: "${OANDA_API_TOKEN:?OANDA_API_TOKEN is required from the approved secret injector}"
: "${OANDA_ACCOUNT_ID:?OANDA_ACCOUNT_ID is required from the approved secret injector}"
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
