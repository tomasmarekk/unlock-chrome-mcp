param(
    [string]$ChromeExe = "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    [string]$ProfileDir = "$env:LOCALAPPDATA\Codex\ChromeDevToolsMcpNativeProfile",
    [int]$DebugPort = 9222,
    [string]$CodexConfigPath = "$env:USERPROFILE\.codex\config.toml",
    [string]$ShortcutPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk",
    [switch]$SkipPackagePatch,
    [switch]$SkipCodexConfig,
    [switch]$SkipShortcut
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

function Backup-File {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $backupRoot = Join-Path $env:LOCALAPPDATA "Codex\backups\unlock-chrome-mcp"
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $leaf = Split-Path -Leaf $Path
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path $backupRoot "$leaf.$stamp.bak"
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    return $backupPath
}

function Get-PythonCommand {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        return @($python.Source)
    }

    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        return @($py.Source, "-3")
    }

    throw "Python was not found. Install Python 3 or make sure python.exe is on PATH."
}

function Update-Shortcut {
    Write-Step "Updating Start menu Chrome shortcut"

    if (-not (Test-Path -LiteralPath $ChromeExe)) {
        throw "Chrome executable not found: $ChromeExe"
    }

    New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
    New-Item -ItemType Directory -Path (Split-Path -Parent $ShortcutPath) -Force | Out-Null

    $backup = Backup-File -Path $ShortcutPath
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($ShortcutPath)
    $shortcut.TargetPath = $ChromeExe
    $shortcut.Arguments = "--remote-debugging-port=$DebugPort --user-data-dir=`"$ProfileDir`" --no-first-run --no-default-browser-check --disable-blink-features=AutomationControlled --hide-crash-restore-bubble"
    $shortcut.WorkingDirectory = Split-Path -Parent $ChromeExe
    $shortcut.IconLocation = "$ChromeExe,0"
    $shortcut.Description = "Google Chrome, configured for local Chrome DevTools MCP control"
    $shortcut.Save()

    Write-Host "Shortcut updated: $ShortcutPath"
    if ($backup) {
        Write-Host "Shortcut backup: $backup"
    }
}

function Update-CodexConfig {
    Write-Step "Updating Codex MCP config"

    $commandPath = Join-Path $env:APPDATA "npm\chrome-devtools-mcp.cmd"
    if (-not (Test-Path -LiteralPath $commandPath)) {
        $whereResult = where.exe chrome-devtools-mcp.cmd 2>$null | Select-Object -First 1
        if ($whereResult) {
            $commandPath = $whereResult
        }
        else {
            throw "Could not find chrome-devtools-mcp.cmd. Install it globally first: npm install -g chrome-devtools-mcp@latest"
        }
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $CodexConfigPath) -Force | Out-Null
    $backup = Backup-File -Path $CodexConfigPath

    $escapedProfileDir = $ProfileDir.Replace("\", "\\")
    $section = @"
[mcp_servers."chrome-devtools"]
args = ["--autoConnect", "--channel=stable", "--userDataDir=$escapedProfileDir", "--chromeArg=--disable-blink-features=AutomationControlled", "--no-usage-statistics"]
command = '$commandPath'
startup_timeout_sec = 120

"@

    $content = ""
    if (Test-Path -LiteralPath $CodexConfigPath) {
        $content = Get-Content -LiteralPath $CodexConfigPath -Raw
    }

    $pattern = '(?ms)^\[mcp_servers\."chrome-devtools"\]\r?\n.*?(?=^\[|\z)'
    if ([regex]::IsMatch($content, $pattern)) {
        $content = [regex]::Replace($content, $pattern, $section, 1)
    }
    else {
        if ($content -and -not $content.EndsWith("`n")) {
            $content += "`n"
        }
        $content += "`n$section"
    }

    Set-Content -LiteralPath $CodexConfigPath -Value $content -Encoding UTF8NoBOM
    Write-Host "Codex config updated: $CodexConfigPath"
    if ($backup) {
        Write-Host "Codex config backup: $backup"
    }
}

if (-not $SkipPackagePatch) {
    Write-Step "Patching global chrome-devtools-mcp package"
    $pythonCommand = @(Get-PythonCommand)
    $patchScript = Join-Path $PSScriptRoot "patch-mcp-package.py"
    if ($pythonCommand.Length -gt 1) {
        & $pythonCommand[0] $pythonCommand[1] $patchScript
    }
    else {
        & $pythonCommand[0] $patchScript
    }
}

if (-not $SkipShortcut) {
    Update-Shortcut
}

if (-not $SkipCodexConfig) {
    Update-CodexConfig
}

Write-Step "Done"
Write-Host "Close all Chrome windows, open Chrome from the Start menu, then restart Codex or your MCP client."
