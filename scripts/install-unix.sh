#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DEBUG_PORT="${DEBUG_PORT:-9222}"
CODEX_CONFIG="${CODEX_CONFIG:-${HOME}/.codex/config.toml}"

case "$(uname -s)" in
  Darwin)
    OS_NAME="macos"
    PROFILE_DIR="${PROFILE_DIR:-${HOME}/.codex/chrome-devtools-mcp-native-profile}"
    DEFAULT_CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    LAUNCHER_PATH="${LAUNCHER_PATH:-${HOME}/Applications/Chrome DevTools MCP.command}"
    ;;
  Linux)
    OS_NAME="linux"
    PROFILE_DIR="${PROFILE_DIR:-${HOME}/.codex/chrome-devtools-mcp-native-profile}"
    DEFAULT_CHROME=""
    LAUNCHER_PATH="${LAUNCHER_PATH:-${HOME}/.local/share/applications/chrome-devtools-mcp.desktop}"
    ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    exit 1
    ;;
esac

find_chrome() {
  if [[ -n "${CHROME_BIN:-}" && -x "${CHROME_BIN}" ]]; then
    printf '%s\n' "${CHROME_BIN}"
    return
  fi
  if [[ -n "${DEFAULT_CHROME}" && -x "${DEFAULT_CHROME}" ]]; then
    printf '%s\n' "${DEFAULT_CHROME}"
    return
  fi
  for candidate in google-chrome google-chrome-stable chromium chromium-browser; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      command -v "${candidate}"
      return
    fi
  done
  echo "Could not find Chrome/Chromium. Set CHROME_BIN=/path/to/chrome and retry." >&2
  exit 1
}

find_mcp_command() {
  if command -v chrome-devtools-mcp >/dev/null 2>&1; then
    command -v chrome-devtools-mcp
    return
  fi
  echo "chrome-devtools-mcp not found. Install it first: npm install -g chrome-devtools-mcp@latest" >&2
  exit 1
}

backup_file() {
  local path="$1"
  [[ -e "${path}" ]] || return 0
  local backup_dir="${HOME}/.codex/backups/chrome-mcp-fix-info"
  mkdir -p "${backup_dir}"
  cp -p "${path}" "${backup_dir}/$(basename "${path}").$(date +%Y%m%d-%H%M%S).bak"
}

CHROME_BIN_RESOLVED="$(find_chrome)"
MCP_COMMAND="$(find_mcp_command)"

echo "==> Patching chrome-devtools-mcp package"
python3 "${REPO_ROOT}/scripts/patch-mcp-package.py"

echo "==> Creating Chrome profile"
mkdir -p "${PROFILE_DIR}"

if [[ "${OS_NAME}" == "macos" ]]; then
  echo "==> Creating macOS launcher: ${LAUNCHER_PATH}"
  mkdir -p "$(dirname "${LAUNCHER_PATH}")"
  backup_file "${LAUNCHER_PATH}"
  cat > "${LAUNCHER_PATH}" <<EOF
#!/usr/bin/env bash
exec "${CHROME_BIN_RESOLVED}" \\
  --remote-debugging-port=${DEBUG_PORT} \\
  --user-data-dir="${PROFILE_DIR}" \\
  --no-first-run \\
  --no-default-browser-check \\
  --disable-blink-features=AutomationControlled \\
  --hide-crash-restore-bubble \\
  "\$@"
EOF
  chmod +x "${LAUNCHER_PATH}"
  echo "Pin or launch this file when you want an agent-controllable Chrome session."
else
  echo "==> Creating Linux desktop entry: ${LAUNCHER_PATH}"
  mkdir -p "$(dirname "${LAUNCHER_PATH}")"
  backup_file "${LAUNCHER_PATH}"
  cat > "${LAUNCHER_PATH}" <<EOF
[Desktop Entry]
Type=Application
Name=Chrome DevTools MCP
Comment=Google Chrome profile configured for local Chrome DevTools MCP control
Exec=${CHROME_BIN_RESOLVED} --remote-debugging-port=${DEBUG_PORT} --user-data-dir=${PROFILE_DIR} --no-first-run --no-default-browser-check --disable-blink-features=AutomationControlled --hide-crash-restore-bubble %U
Icon=google-chrome
Terminal=false
Categories=Network;WebBrowser;
StartupNotify=true
EOF
  chmod +x "${LAUNCHER_PATH}"
fi

echo "==> Updating Codex MCP config: ${CODEX_CONFIG}"
mkdir -p "$(dirname "${CODEX_CONFIG}")"
backup_file "${CODEX_CONFIG}"
python3 - "$CODEX_CONFIG" "$MCP_COMMAND" "$PROFILE_DIR" <<'PY'
from __future__ import annotations

import pathlib
import re
import sys

config_path = pathlib.Path(sys.argv[1])
command = sys.argv[2]
profile = sys.argv[3]

section = f'''[mcp_servers."chrome-devtools"]
args = ["--autoConnect", "--channel=stable", "--userDataDir={profile}", "--chromeArg=--disable-blink-features=AutomationControlled", "--no-usage-statistics"]
command = '{command}'
startup_timeout_sec = 120

'''

content = config_path.read_text(encoding="utf-8") if config_path.exists() else ""
pattern = re.compile(r'(?ms)^\[mcp_servers\."chrome-devtools"\]\n.*?(?=^\[|\Z)')
if pattern.search(content):
    content = pattern.sub(section, content, count=1)
else:
    if content and not content.endswith("\n"):
        content += "\n"
    content += "\n" + section
config_path.write_text(content, encoding="utf-8", newline="\n")
PY

echo "==> Done"
echo "Close existing Chrome windows, launch the new Chrome DevTools MCP launcher, then restart Codex or your MCP client."
