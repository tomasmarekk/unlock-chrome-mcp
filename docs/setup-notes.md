# Setup Notes

These notes describe the exact process this repository captures.

## Problem

The default `chrome-devtools-mcp` behavior can launch a separate Chrome instance. That is not ideal when the user already has a normal visible Chrome window open and wants the agent to control those tabs.

There are two separate constraints:

- Chrome DevTools Protocol can only attach to a Chrome instance that exposes a debugging endpoint.
- Modern Chrome restricts remote debugging against the default Chrome profile.

Therefore, an already-running default Chrome window cannot be retroactively controlled over CDP.

## Solution Shape

Use a dedicated persistent profile:

```text
%LOCALAPPDATA%\Codex\ChromeDevToolsMcpNativeProfile
```

On macOS/Linux the default from this repo is:

```text
~/.codex/chrome-devtools-mcp-native-profile
```

Make the Start menu Chrome shortcut open that profile with:

```text
--remote-debugging-port=9222
```

Then configure `chrome-devtools-mcp` with:

```text
--autoConnect
--userDataDir=<same profile>
```

Finally patch MCP so it handles Chrome versions that expose the HTTP debug endpoint but do not create a `DevToolsActivePort` file in the profile directory.

## Observed Working State

The working Chrome process command line looked like:

```text
"C:\Program Files\Google\Chrome\Application\chrome.exe" --remote-debugging-port=9222 --user-data-dir="%LOCALAPPDATA%\Codex\ChromeDevToolsMcpNativeProfile" --no-first-run --no-default-browser-check --disable-blink-features=AutomationControlled --hide-crash-restore-bubble
```

The debug endpoint responded at:

```text
http://127.0.0.1:9222/json/version
```

`chrome-devtools-mcp` then sees tabs from multiple Chrome windows as a flat list:

```text
1: https://example.com/
2: https://app.example.test/dashboard
3: https://docs.example.org/
```

## Limitations

- CDP lists browser targets/pages, not a high-level tree grouped by Chrome window.
- Multiple windows in the same profile are visible, but they appear as one flat page list.
- Windows opened in another Chrome profile will not be controlled by this MCP instance.
- Upgrading `chrome-devtools-mcp` can overwrite the local patch.
- This is not an official upstream feature or support guarantee. It is a local recovery kit.
