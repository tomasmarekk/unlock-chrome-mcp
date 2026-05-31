#!/usr/bin/env python3
"""Patch a globally installed chrome-devtools-mcp package for native Chrome reuse.

The patch is intentionally source-text based because chrome-devtools-mcp ships
compiled JavaScript in the npm package. It backs up files before writing and
fails loudly if the expected upstream blocks are not present.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import pathlib
import re
import shutil
import subprocess
import sys


def run_text(command: list[str]) -> str:
    return subprocess.check_output(command, text=True, stderr=subprocess.DEVNULL).strip()


def find_package_root(explicit: str | None) -> pathlib.Path:
    if explicit:
        root = pathlib.Path(explicit)
        if root.exists():
            return root
        raise SystemExit(f"Package root does not exist: {root}")

    candidates: list[pathlib.Path] = []
    try:
        npm_root = run_text(["npm", "root", "-g"])
        candidates.append(pathlib.Path(npm_root) / "chrome-devtools-mcp")
    except Exception:
        pass

    appdata = os.environ.get("APPDATA")
    if appdata:
        candidates.append(pathlib.Path(appdata) / "npm" / "node_modules" / "chrome-devtools-mcp")

    candidates.extend(
        [
            pathlib.Path("/usr/local/lib/node_modules/chrome-devtools-mcp"),
            pathlib.Path("/opt/homebrew/lib/node_modules/chrome-devtools-mcp"),
            pathlib.Path.home() / ".npm-global" / "lib" / "node_modules" / "chrome-devtools-mcp",
        ]
    )

    for candidate in candidates:
        if candidate.exists():
            return candidate

    raise SystemExit("Could not find global chrome-devtools-mcp. Install it with: npm install -g chrome-devtools-mcp@latest")


def backup(path: pathlib.Path) -> pathlib.Path:
    backup_dir = pathlib.Path(os.environ.get("LOCALAPPDATA", pathlib.Path.home() / ".cache")) / "Codex" / "backups" / "unlock-chrome-mcp"
    backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    target = backup_dir / f"{path.name}.{stamp}.bak"
    shutil.copy2(path, target)
    return target


def replace_required(content: str, old: str, new: str, description: str) -> str:
    if new in content:
        return content
    if old not in content:
        raise SystemExit(f"Could not find expected source block for {description}. The installed package version may have changed.")
    return content.replace(old, new, 1)


HELPERS = r"""export function hasRunningChromeWindow() {
    if (os.platform() === 'win32') {
        try {
            const output = execSync('powershell.exe -NoProfile -Command "(Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }).Count"', {
                encoding: 'utf8',
                stdio: ['ignore', 'pipe', 'ignore'],
            }).trim();
            const count = parseInt(output, 10);
            return Number.isFinite(count) && count > 0;
        }
        catch {
            return false;
        }
    }
    try {
        const output = execSync('ps -axo args=', {
            encoding: 'utf8',
            stdio: ['ignore', 'pipe', 'ignore'],
        });
        return output.split(/\r?\n/).some(line => {
            return /(^|\/)(Google Chrome|google-chrome|google-chrome-stable|chromium|chromium-browser)(\s|$)/.test(line) &&
                !line.includes('--type=');
        });
    }
    catch {
        return false;
    }
}
function normalizeProfilePath(profilePath) {
    return path.resolve(profilePath).replace(/[\\\/]+$/, '').toLowerCase();
}
function parseDebuggingPortFromCommandLine(commandLine, userDataDir) {
    const portMatch = commandLine.match(/--remote-debugging-port=(\d+)/);
    if (!portMatch) {
        return;
    }
    const dirMatch = commandLine.match(/--user-data-dir=(?:"([^"]+)"|'([^']+)'|([^ ]+))/);
    if (!dirMatch) {
        return;
    }
    const rawDir = dirMatch[1] ?? dirMatch[2] ?? dirMatch[3];
    if (normalizeProfilePath(rawDir) !== normalizeProfilePath(userDataDir)) {
        return;
    }
    const port = parseInt(portMatch[1], 10);
    if (Number.isFinite(port) && port > 0 && port <= 65535) {
        return port;
    }
}
function discoverWindowsDebuggingPort(userDataDir) {
    const escapedUserDataDir = userDataDir.replaceAll("'", "''");
    const psScript = `
$target = [System.IO.Path]::GetFullPath('${escapedUserDataDir}').TrimEnd('\')
$found = $null
foreach ($process in Get-CimInstance Win32_Process -Filter "name = 'chrome.exe'") {
  $cmd = $process.CommandLine
  if (-not $cmd) { continue }
  $portMatch = [regex]::Match($cmd, '--remote-debugging-port=(\d+)')
  if (-not $portMatch.Success) { continue }
  $dirMatch = [regex]::Match($cmd, '--user-data-dir=(?:"([^"]+)"|([^ ]+))')
  if (-not $dirMatch.Success) { continue }
  $dir = if ($dirMatch.Groups[1].Success) { $dirMatch.Groups[1].Value } else { $dirMatch.Groups[2].Value }
  $full = [System.IO.Path]::GetFullPath($dir).TrimEnd('\')
  if ([System.String]::Equals($full, $target, [System.StringComparison]::OrdinalIgnoreCase)) {
    $found = $portMatch.Groups[1].Value
    break
  }
}
if ($found) { $found }
`;
    try {
        const encoded = Buffer.from(psScript, 'utf16le').toString('base64');
        const output = execSync(`powershell.exe -NoProfile -EncodedCommand ${encoded}`, {
            encoding: 'utf8',
            stdio: ['ignore', 'pipe', 'ignore'],
        }).trim();
        const port = parseInt(output.split(/\r?\n/).find(Boolean) ?? '', 10);
        if (Number.isFinite(port) && port > 0 && port <= 65535) {
            return port;
        }
    }
    catch {
        return;
    }
}
function discoverPosixDebuggingPort(userDataDir) {
    try {
        const output = execSync('ps -axo args=', {
            encoding: 'utf8',
            stdio: ['ignore', 'pipe', 'ignore'],
        });
        for (const line of output.split(/\r?\n/)) {
            const port = parseDebuggingPortFromCommandLine(line, userDataDir);
            if (port) {
                return port;
            }
        }
    }
    catch {
        return;
    }
}
function discoverChromeDebuggingPort(userDataDir) {
    return os.platform() === 'win32'
        ? discoverWindowsDebuggingPort(userDataDir)
        : discoverPosixDebuggingPort(userDataDir);
}
"""


def patch_browser_js(path_: pathlib.Path) -> None:
    content = path_.read_text(encoding="utf-8")
    original = content

    content = replace_required(
        content,
        "import { spawn } from 'node:child_process';",
        "import { execSync, spawn } from 'node:child_process';",
        "child_process import",
    )

    has_discovery_patch = (
        "discoverChromeDebuggingPort(userDataDir)" in content
        or "discoverWindowsDebuggingPort(userDataDir)" in content
    )
    if not has_discovery_patch:
        content = replace_required(content, "let launchedChromeProcess;\n", f"let launchedChromeProcess;\n{HELPERS}", "Chrome process discovery helpers")

    old_catch = """            catch (error) {
                throw new Error(`Could not connect to Chrome in ${userDataDir}. Check if Chrome is running and remote debugging is enabled by going to chrome://inspect/#remote-debugging.`, {
                    cause: error,
                });
            }
"""
    new_catch = """            catch (error) {
                const discoveredPort = discoverChromeDebuggingPort(userDataDir);
                if (!discoveredPort) {
                    throw new Error(`Could not connect to Chrome in ${userDataDir}. Check if Chrome is running and remote debugging is enabled by going to chrome://inspect/#remote-debugging.`, {
                        cause: error,
                    });
                }
                logger(`DevToolsActivePort was not available for ${userDataDir}; using discovered Chrome debugging port ${discoveredPort}.`);
                connectOptions.browserURL = `http://127.0.0.1:${discoveredPort}`;
            }
"""
    has_fallback_patch = (
        "const discoveredPort = discoverChromeDebuggingPort(userDataDir);" in content
        or "const discoveredPort = discoverWindowsDebuggingPort(userDataDir);" in content
    )
    if not has_fallback_patch:
        content = replace_required(content, old_catch, new_catch, "DevToolsActivePort fallback")

    old_profile = "        userDataDir = path.join(os.homedir(), '.cache', options.viaCli ? 'chrome-devtools-mcp-cli' : 'chrome-devtools-mcp', profileDirName);\n"
    new_profile = """        userDataDir = os.platform() === 'win32'
            ? path.join(process.env.LOCALAPPDATA ?? path.join(os.homedir(), 'AppData', 'Local'), 'Codex', options.viaCli ? 'ChromeDevToolsMcpCliNativeProfile' : 'ChromeDevToolsMcpNativeProfile')
            : path.join(os.homedir(), '.codex', options.viaCli ? 'chrome-devtools-mcp-cli-native-profile' : 'chrome-devtools-mcp-native-profile');
"""
    if new_profile not in content:
        if old_profile in content:
            content = content.replace(old_profile, new_profile, 1)
        elif "ChromeDevToolsMcpNativeProfile" in content:
            # Compatible older Windows-only patch. Leave it untouched instead of
            # failing a reinstall on an already-configured Windows machine.
            print("Default launch profile already appears patched for Windows.")
        else:
            raise SystemExit("Could not find expected source block for default launch profile. The installed package version may have changed.")

    if content != original:
        saved = backup(path_)
        path_.write_text(content, encoding="utf-8", newline="\n")
        print(f"Patched {path_} (backup: {saved})")
    else:
        print(f"Already patched: {path_}")


def patch_index_js(path_: pathlib.Path) -> None:
    content = path_.read_text(encoding="utf-8")
    original = content

    content = replace_required(
        content,
        "import { ensureBrowserConnected, ensureBrowserLaunched } from './browser.js';",
        "import { ensureBrowserConnected, ensureBrowserLaunched, hasRunningChromeWindow } from './browser.js';",
        "browser import",
    )

    if "A Chrome window is already open, but Chrome DevTools MCP could not attach to it." not in content:
        pattern = re.compile(
            r"const browser = serverArgs\.browserUrl \|\| serverArgs\.wsEndpoint \|\| serverArgs\.autoConnect\s*\?\s*await ensureBrowserConnected\(\{.*?channel: serverArgs\.autoConnect\s*\?\s*serverArgs\.channel\s*:\s*undefined,\s*userDataDir: serverArgs\.userDataDir,\s*devtools,\s*\}\)\s*:\s*await ensureBrowserLaunched\(\{.*?viaCli: serverArgs\.viaCli,\s*\}\);",
            re.DOTALL,
        )
        replacement = """let browser;
        if (serverArgs.browserUrl || serverArgs.wsEndpoint) {
            browser = await ensureBrowserConnected({
                browserURL: serverArgs.browserUrl,
                wsEndpoint: serverArgs.wsEndpoint,
                wsHeaders: serverArgs.wsHeaders,
                channel: undefined,
                userDataDir: serverArgs.userDataDir,
                devtools,
            });
        }
        else if (serverArgs.autoConnect) {
            try {
                browser = await ensureBrowserConnected({
                    // Important: only pass channel, if autoConnect is true.
                    channel: serverArgs.channel,
                    userDataDir: serverArgs.userDataDir,
                    devtools,
                });
            }
            catch (error) {
                if (hasRunningChromeWindow()) {
                    throw new Error('A Chrome window is already open, but Chrome DevTools MCP could not attach to it. Do not open a second Chrome window. Open Chrome from the configured MCP launcher/shortcut or make sure the configured Chrome profile is running with remote debugging enabled, then retry the agent browser action.', {
                        cause: error,
                    });
                }
                logger('Auto-connect failed and no visible Chrome window was detected; launching a Chrome window for MCP control.', error);
                browser = await ensureBrowserLaunched({
                    headless: serverArgs.headless,
                    executablePath: serverArgs.executablePath,
                    channel: serverArgs.channel,
                    isolated: serverArgs.isolated ?? false,
                    userDataDir: serverArgs.userDataDir,
                    logFile: options.logFile,
                    viewport: serverArgs.viewport,
                    chromeArgs,
                    ignoreDefaultChromeArgs,
                    acceptInsecureCerts: serverArgs.acceptInsecureCerts,
                    devtools,
                    enableExtensions: serverArgs.categoryExtensions,
                    viaCli: serverArgs.viaCli,
                });
            }
        }
        else {
            browser = await ensureBrowserLaunched({
                headless: serverArgs.headless,
                executablePath: serverArgs.executablePath,
                channel: serverArgs.channel,
                isolated: serverArgs.isolated ?? false,
                userDataDir: serverArgs.userDataDir,
                logFile: options.logFile,
                viewport: serverArgs.viewport,
                chromeArgs,
                ignoreDefaultChromeArgs,
                acceptInsecureCerts: serverArgs.acceptInsecureCerts,
                devtools,
                enableExtensions: serverArgs.categoryExtensions,
                viaCli: serverArgs.viaCli,
            });
        }"""
        content, count = pattern.subn(replacement, content, count=1)
        if count != 1:
            raise SystemExit("Could not find expected launch/connect block in index.js. The installed package version may have changed.")

    if content != original:
        saved = backup(path_)
        path_.write_text(content, encoding="utf-8", newline="\n")
        print(f"Patched {path_} (backup: {saved})")
    else:
        print(f"Already patched: {path_}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Patch global chrome-devtools-mcp to control OS-installed native Chrome sessions.")
    parser.add_argument("--package-root", help="Path to global chrome-devtools-mcp package root.")
    args = parser.parse_args()

    root = find_package_root(args.package_root)
    src = root / "build" / "src"
    browser_js = src / "browser.js"
    index_js = src / "index.js"
    if not browser_js.exists() or not index_js.exists():
        raise SystemExit(f"Could not find expected build files under {src}")

    patch_browser_js(browser_js)
    patch_index_js(index_js)

    subprocess.check_call(["node", "--check", str(browser_js)])
    subprocess.check_call(["node", "--check", str(index_js)])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
