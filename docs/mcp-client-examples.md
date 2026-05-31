# MCP Client Examples

This repo's scripts update Codex config by default. Other MCP clients can use the same server arguments.

## Generic Args

Use the official `chrome-devtools-mcp` command with:

```text
--autoConnect
--channel=stable
--userDataDir=<dedicated profile path>
--chromeArg=--disable-blink-features=AutomationControlled
--no-usage-statistics
```

The dedicated profile path must match the profile used by the Chrome launcher.

## JSON-style MCP Config

```json
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "chrome-devtools-mcp",
      "args": [
        "--autoConnect",
        "--channel=stable",
        "--userDataDir=/absolute/path/to/dedicated/profile",
        "--chromeArg=--disable-blink-features=AutomationControlled",
        "--no-usage-statistics"
      ]
    }
  }
}
```

## Codex TOML Config

```toml
[mcp_servers."chrome-devtools"]
args = ["--autoConnect", "--channel=stable", "--userDataDir=/absolute/path/to/dedicated/profile", "--chromeArg=--disable-blink-features=AutomationControlled", "--no-usage-statistics"]
command = 'chrome-devtools-mcp'
startup_timeout_sec = 120
```

## Verification Prompt

Ask the agent:

```text
Use Chrome DevTools MCP list_pages. Confirm you see the tabs I opened manually in the configured Chrome launcher. Then select one tab and take a snapshot.
```
