#!/usr/bin/env bash
set -euo pipefail

DEBUG_PORT="${DEBUG_PORT:-9222}"
PROFILE_DIR="${PROFILE_DIR:-${HOME}/.codex/chrome-devtools-mcp-native-profile}"

ok=true

check() {
  local name="$1"
  local status="$2"
  local detail="${3:-}"
  if [[ "${status}" == "true" ]]; then
    printf '[OK] %s%s\n' "${name}" "${detail:+ - ${detail}}"
  else
    printf '[FAIL] %s%s\n' "${name}" "${detail:+ - ${detail}}"
    ok=false
  fi
}

if ps -axo args= | grep -F -- "--remote-debugging-port=${DEBUG_PORT}" | grep -F -- "--user-data-dir=${PROFILE_DIR}" >/dev/null 2>&1; then
  check "Chrome process with target profile/debug port" true
else
  check "Chrome process with target profile/debug port" false "launch the configured Chrome launcher first"
fi

if command -v curl >/dev/null 2>&1 && curl -fsS "http://127.0.0.1:${DEBUG_PORT}/json/version" >/tmp/chrome-mcp-version.json 2>/dev/null; then
  check "CDP /json/version" true "$(python3 - <<'PY'
import json
from pathlib import Path
data = json.loads(Path('/tmp/chrome-mcp-version.json').read_text())
print(data.get('Browser', 'unknown'))
PY
)"
else
  check "CDP /json/version" false "http://127.0.0.1:${DEBUG_PORT}/json/version did not respond"
fi

if command -v curl >/dev/null 2>&1 && curl -fsS "http://127.0.0.1:${DEBUG_PORT}/json/list" >/tmp/chrome-mcp-tabs.json 2>/dev/null; then
  python3 - <<'PY'
import json
from pathlib import Path
tabs = [item for item in json.loads(Path('/tmp/chrome-mcp-tabs.json').read_text()) if item.get('type') == 'page']
print(f"[OK] CDP page list - pageCount={len(tabs)}" if tabs else "[FAIL] CDP page list - no page targets")
for tab in tabs:
    print(f"  - {tab.get('url')}")
raise SystemExit(0 if tabs else 1)
PY
else
  check "CDP page list" false "http://127.0.0.1:${DEBUG_PORT}/json/list did not respond"
fi

if npm_root="$(npm root -g 2>/dev/null)" && [[ -d "${npm_root}/chrome-devtools-mcp" ]]; then
  browser_js="${npm_root}/chrome-devtools-mcp/build/src/browser.js"
  index_js="${npm_root}/chrome-devtools-mcp/build/src/index.js"
  if grep -Eq "discoverChromeDebuggingPort|discoverWindowsDebuggingPort" "${browser_js}" && grep -q "hasRunningChromeWindow" "${index_js}"; then
    check "chrome-devtools-mcp patch markers" true "${npm_root}/chrome-devtools-mcp"
  else
    check "chrome-devtools-mcp patch markers" false "run scripts/install-unix.sh"
  fi
else
  check "chrome-devtools-mcp package" false "global npm package not found"
fi

if [[ "${ok}" != "true" ]]; then
  exit 1
fi
