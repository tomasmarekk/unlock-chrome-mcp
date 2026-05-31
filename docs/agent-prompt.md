# Agent Prompt

Use this prompt when you want another coding agent to recreate the setup from this repository.

```text
Please configure Chrome DevTools MCP on this machine using this repository:
https://github.com/tomasmarekk/chrome-mcp-fix-info

Read the README and use the platform-specific installer.

Acceptance criteria:
- chrome-devtools-mcp controls the OS-installed native Chrome profile configured by this repo, not an isolated automation-only browser.
- If that native Chrome profile is already running, chrome-devtools-mcp reuses the existing visible windows and tabs.
- Tabs from multiple Chrome windows in the configured profile are visible through the MCP page list.
- The MCP server must not silently open a second unrelated Chrome window while a compatible native Chrome session is available.
- If no compatible Chrome session exists, it may launch the configured dedicated native Chrome profile.
- Run the included verification script and then test through the actual MCP tool by listing pages.

Before making changes, explain that this gives the local agent access to the configured Chrome session and should be used at the user's own risk.
```

## What The Agent Should Not Do

- Do not enable remote debugging on the user's default personal Chrome profile.
- Do not hardcode someone else's username or profile path.
- Do not claim success from package patching alone; verify the CDP endpoint and the MCP page list.
- Do not leave the user thinking this is risk-free. The agent can inspect and control the configured browser session.
