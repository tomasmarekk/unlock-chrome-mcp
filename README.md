# Chrome MCP Fix Info

[![Windows](https://img.shields.io/badge/Windows-supported-0078D4)](#windows)
[![macOS](https://img.shields.io/badge/macOS-supported-000000)](#macos)
[![Linux](https://img.shields.io/badge/Linux-supported-FCC624)](#linux)
[![Chrome DevTools MCP](https://img.shields.io/badge/Chrome%20DevTools-MCP-4285F4)](https://github.com/ChromeDevTools/chrome-devtools-mcp)
[![CDP](https://img.shields.io/badge/Chrome%20DevTools%20Protocol-CDP-34A853)](https://chromedevtools.github.io/devtools-protocol/)

Make `chrome-devtools-mcp` control OS-installed native Chrome instead of an isolated automation browser. It reuses visible Chrome windows launched from your OS, and it can start the same dedicated native Chrome profile when no compatible session is running.

This repo is a practical recovery kit for people who want an agent tool such as Codex, Claude Code, Cursor, Gemini CLI, OpenCode, or another MCP client to use OS-installed visible native Chrome instead of a disconnected automation-only browser.

## What This Solves

Default browser automation often opens a separate Chrome profile/window. That is awkward when you already have:

- a logged-in Chrome profile,
- several tabs open,
- multiple Chrome windows,
- a website state you prepared manually,
- a login flow that rejects obviously automated browsers.

The target behavior is:

1. Your normal OS launcher opens a dedicated native Chrome profile with local DevTools enabled.
2. If that Chrome profile is already running, the agent reuses the visible windows and tabs you opened manually.
3. If no compatible Chrome session is running, `chrome-devtools-mcp` can launch that same native Chrome profile.
4. The agent sees all debuggable tabs as MCP pages and can select/control each one, even across multiple Chrome windows.
5. It never silently falls back to a second unrelated Chrome window while a compatible native session is available.

On a working setup, `list_pages` looks like:

```text
## Pages
1: https://example.com/
2: https://app.example.test/dashboard
3: https://docs.example.org/
```

Chrome windows are exposed as a flat list of page targets. The agent can still control each tab by page id.

## Copy-Paste Prompt For Your Agent

Give this to the coding agent that should configure your machine:

```text
Go to https://github.com/tomasmarekk/chrome-mcp-fix-info and configure my Chrome DevTools MCP setup exactly as described there.

Goal:
- chrome-devtools-mcp must control the OS-installed native Chrome profile configured by this repo, not an isolated automation-only browser.
- If that native Chrome profile is already running, it must reuse the existing visible windows and tabs.
- It must see tabs from all Chrome windows in the configured profile.
- It must not silently open a second unrelated Chrome window when a Chrome window is already open.
- If no compatible Chrome session is open, it may launch the configured native Chrome profile.

Read the README, apply the platform-specific installer, verify with the included verify script, and then test through the actual MCP tool by listing pages.

Important: explain the security implications before enabling it, because the agent will be able to inspect and control the configured Chrome session.
```

## Security Warning

Use this at your own risk.

This setup gives your local agent tooling access to the configured Chrome session through Chrome DevTools Protocol. A connected agent can inspect pages, read visible page content, click buttons, type into forms, navigate tabs, inspect network traffic exposed through DevTools, and generally act inside that browser profile.

Do not use the configured profile for unrelated sensitive browsing unless you are comfortable with the connected agent seeing and controlling it.

Practical safety rules:

- Use the dedicated profile created by this setup, not your default personal Chrome profile.
- Close sensitive tabs before asking an agent to use Chrome.
- Only run agent tools you trust.
- Keep the debug port bound to localhost.
- Re-run the installer after upgrading `chrome-devtools-mcp`, because package upgrades can overwrite the patch.

This repo is not affiliated with Google, Chrome, OpenAI, Anthropic, or the Chrome DevTools MCP project.

## Why A Dedicated Profile Is Needed

Modern Chrome restricts remote debugging on the default user data directory to protect profile data. A normal Chrome launched with no flags usually does not expose a DevTools endpoint, and current Chrome intentionally blocks some remote debugging use cases against the default profile.

The reliable pattern is:

1. Create a non-default persistent Chrome profile for agent-controlled browsing.
2. Launch that profile with a local remote debugging port.
3. Configure `chrome-devtools-mcp` to auto-connect to the same profile.
4. Patch the installed MCP package so it attaches first and only launches Chrome when no compatible window exists.

References:

- [Chrome remote debugging profile restrictions](https://developer.chrome.com/blog/remote-debugging-port)
- [Chrome DevTools MCP connection docs](https://github.com/ChromeDevTools/chrome-devtools-mcp#connecting-to-a-running-chrome-instance)

## Quick Start

This is the normal install flow.

### 1. Install official Chrome DevTools MCP in your agent tool

First install and register the official Chrome DevTools MCP server in your "clicker" / coding agent / MCP client.

For Codex, Claude Code, Cursor, Gemini CLI, OpenCode, or similar tools, follow that tool's normal MCP setup flow and point it at the official package:

```bash
npm install -g chrome-devtools-mcp@latest
```

At this stage it is fine if the official MCP still opens its own Chrome window. This repo is the second step that changes the behavior to prefer your already-open visible Chrome session.

### 2. Give this repo to your agent

After the official MCP exists, give your agent this repository and ask it to set up the machine from it:

```text
Use https://github.com/tomasmarekk/chrome-mcp-fix-info to configure Chrome DevTools MCP on this machine.
Read the README, explain the security risk, run the installer for my OS, verify it, and test that you can see my open Chrome tabs through the actual MCP tool.
```

The agent should clone the repo:

```bash
git clone https://github.com/tomasmarekk/chrome-mcp-fix-info.git
cd chrome-mcp-fix-info
```

### 3. Run the platform installer

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-windows.ps1
```

macOS/Linux:

```bash
bash ./scripts/install-unix.sh
```

### 4. Restart and verify

After the installer:

1. Close all Chrome windows.
2. Open Chrome from the configured launcher/shortcut.
3. Open a few tabs, ideally across multiple Chrome windows.
4. Restart the agent tool so it reloads the MCP server.
5. Ask the agent to list Chrome DevTools MCP pages.

Expected result:

```text
## Pages
1: https://...
2: https://...
3: https://...
```

### 5. Re-run after upgrades

If you later upgrade or reinstall `chrome-devtools-mcp`, run this repo's installer again. The npm package patch is local and package upgrades can overwrite it.

## Windows

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install-windows.ps1
```

The Windows installer:

- patches the globally installed `chrome-devtools-mcp` package,
- creates/updates the dedicated Chrome profile at `%LOCALAPPDATA%\Codex\ChromeDevToolsMcpNativeProfile`,
- updates the Start menu `Google Chrome` shortcut to launch that profile with `--remote-debugging-port=9222`,
- updates `~\.codex\config.toml` with the matching MCP config,
- backs up edited files under `%LOCALAPPDATA%\Codex\backups\chrome-mcp-fix-info`.

After install:

1. Close all Chrome windows.
2. Open Google Chrome from the Windows Start menu.
3. Open a few tabs, optionally in multiple Chrome windows.
4. Restart Codex or your MCP client.
5. Ask the agent to list Chrome DevTools MCP pages.

Verify:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\verify-windows.ps1
```

## macOS

Run:

```bash
bash ./scripts/install-unix.sh
```

The macOS installer creates:

```text
~/Applications/Chrome DevTools MCP.command
```

Launch Chrome through that command file when you want the agent-controllable session. It uses:

```text
~/.codex/chrome-devtools-mcp-native-profile
```

Verify:

```bash
bash ./scripts/verify-unix.sh
```

Optional overrides:

```bash
CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
PROFILE_DIR="$HOME/.codex/chrome-devtools-mcp-native-profile" \
DEBUG_PORT=9222 \
bash ./scripts/install-unix.sh
```

## Linux

Run:

```bash
bash ./scripts/install-unix.sh
```

The Linux installer creates a desktop launcher:

```text
~/.local/share/applications/chrome-devtools-mcp.desktop
```

Launch that desktop entry when you want the agent-controllable session. It uses:

```text
~/.codex/chrome-devtools-mcp-native-profile
```

Verify:

```bash
bash ./scripts/verify-unix.sh
```

If Chrome is not auto-detected:

```bash
CHROME_BIN=/usr/bin/google-chrome-stable bash ./scripts/install-unix.sh
```

## How It Works

The installer changes three things.

1. It patches the installed npm package:

```text
<global npm root>/chrome-devtools-mcp/build/src/browser.js
<global npm root>/chrome-devtools-mcp/build/src/index.js
```

2. It creates a launcher/shortcut that opens Chrome with:

```text
--remote-debugging-port=9222
--user-data-dir=<dedicated persistent profile>
--disable-blink-features=AutomationControlled
```

3. It configures the MCP client, currently Codex by default, with:

```text
--autoConnect
--channel=stable
--userDataDir=<same dedicated profile>
```

Behavior after the patch:

- If the configured Chrome profile is already running, MCP attaches to it.
- If `DevToolsActivePort` is missing but Chrome is listening on the configured debug port, MCP discovers the port from the running Chrome process.
- If Chrome is open but not attachable, MCP fails loudly instead of silently opening a second unrelated window.
- If no Chrome window exists, MCP can launch Chrome with the configured profile.

## Repository Layout

```text
docs/
  setup-notes.md        deeper implementation notes
scripts/
  install-windows.ps1   Windows installer
  verify-windows.ps1    Windows verifier
  install-unix.sh       macOS/Linux installer
  verify-unix.sh        macOS/Linux verifier
  patch-mcp-package.py  shared npm package patcher
```

## Troubleshooting

If the agent does not see your tabs:

1. Make sure Chrome was opened through the configured launcher/shortcut.
2. Run the platform verify script.
3. Confirm `http://127.0.0.1:9222/json/version` responds.
4. Restart the agent tool so the MCP server reloads.
5. Re-run the installer if `chrome-devtools-mcp` was upgraded.

If the agent opens another Chrome window:

- It is probably not using this patched config, or the currently open Chrome window is from a different profile.
- Re-run the installer, close Chrome, launch Chrome from the configured launcher, then restart the MCP client.

If the patcher fails:

- The upstream `chrome-devtools-mcp` package may have changed its compiled JavaScript structure.
- Open an issue or inspect the expected blocks in `scripts/patch-mcp-package.py`.

## License

MIT. See [LICENSE](LICENSE).
