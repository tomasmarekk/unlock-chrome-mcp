# Security Model

This setup is powerful because it lets an MCP client control a real browser session. That is also the main risk.

## Trust Boundary

The trust boundary is the configured Chrome profile:

- Windows: `%LOCALAPPDATA%\Codex\ChromeDevToolsMcpNativeProfile`
- macOS/Linux: `~/.codex/chrome-devtools-mcp-native-profile`

Anything open in that profile can be inspected or controlled by a connected local MCP client.

## Local Debug Port

The launcher starts Chrome with a local DevTools endpoint:

```text
--remote-debugging-port=9222
```

The scripts expect that endpoint at:

```text
http://127.0.0.1:9222
```

Do not expose this port to a network interface. Keep it local.

## Recommended Practice

- Use this as a dedicated agent-assisted browsing profile.
- Do not use it as your everyday personal browser profile.
- Close tabs with sensitive sessions before asking an agent to use the browser.
- Use separate Chrome profiles for banking, password managers, admin dashboards, and private accounts.
- Re-run verification after changing Chrome, Node, npm, Codex, or `chrome-devtools-mcp`.

## Why Not The Default Profile?

Modern Chrome restricts remote debugging on the default profile because it can expose cookies and profile data. This repository follows the safer pattern: a non-default profile that is explicitly used for agent-controlled browsing.
