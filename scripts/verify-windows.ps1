param(
    [string]$ProfileDir = "$env:LOCALAPPDATA\Codex\ChromeDevToolsMcpNativeProfile",
    [int]$DebugPort = 9222,
    [string]$ShortcutPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Google Chrome.lnk"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Write-Check {
    param(
        [string]$Name,
        [bool]$Ok,
        [string]$Detail = ""
    )

    $status = if ($Ok) { "OK" } else { "FAIL" }
    if ($Detail) {
        Write-Host "[$status] $Name - $Detail"
    }
    else {
        Write-Host "[$status] $Name"
    }
}

$allOk = $true

try {
    $wsh = New-Object -ComObject WScript.Shell
    $shortcut = $wsh.CreateShortcut($ShortcutPath)
    $shortcutArgs = $shortcut.Arguments
    $shortcutOk = $shortcutArgs -like "*--remote-debugging-port=$DebugPort*" -and $shortcutArgs -like "*$ProfileDir*"
    Write-Check "Start menu shortcut" $shortcutOk $shortcutArgs
    $allOk = $allOk -and $shortcutOk
}
catch {
    Write-Check "Start menu shortcut" $false $_.Exception.Message
    $allOk = $false
}

$chromeProcesses = @(Get-CimInstance Win32_Process -Filter "name = 'chrome.exe'" | Where-Object {
    $_.CommandLine -and
    $_.CommandLine -like "*--remote-debugging-port=$DebugPort*" -and
    $_.CommandLine -like "*$ProfileDir*"
})
$chromeOk = $chromeProcesses.Count -gt 0
Write-Check "Chrome process with target profile/debug port" $chromeOk "count=$($chromeProcesses.Count)"
$allOk = $allOk -and $chromeOk

try {
    $version = Invoke-RestMethod -Uri "http://127.0.0.1:$DebugPort/json/version" -TimeoutSec 3
    $endpointOk = [string]::IsNullOrWhiteSpace($version.webSocketDebuggerUrl) -eq $false
    Write-Check "CDP /json/version" $endpointOk $version.Browser
    $allOk = $allOk -and $endpointOk
}
catch {
    Write-Check "CDP /json/version" $false $_.Exception.Message
    $allOk = $false
}

try {
    $tabs = @(Invoke-RestMethod -Uri "http://127.0.0.1:$DebugPort/json/list" -TimeoutSec 3 | Where-Object { $_.type -eq "page" })
    Write-Check "CDP page list" ($tabs.Count -gt 0) "pageCount=$($tabs.Count)"
    foreach ($tab in $tabs) {
        Write-Host "  - $($tab.url)"
    }
    $allOk = $allOk -and ($tabs.Count -gt 0)
}
catch {
    Write-Check "CDP page list" $false $_.Exception.Message
    $allOk = $false
}

try {
    $npmRoot = (& npm root -g 2>$null | Select-Object -First 1).Trim()
    $packageRoot = Join-Path $npmRoot "chrome-devtools-mcp"
    $browserJs = Join-Path $packageRoot "build\src\browser.js"
    $indexJs = Join-Path $packageRoot "build\src\index.js"
    $browserContent = Get-Content -LiteralPath $browserJs -Raw
    $indexContent = Get-Content -LiteralPath $indexJs -Raw
    $patchOk = ($browserContent.Contains("discoverWindowsDebuggingPort") -or $browserContent.Contains("discoverChromeDebuggingPort")) -and $indexContent.Contains("hasRunningChromeWindow")
    Write-Check "chrome-devtools-mcp patch markers" $patchOk $packageRoot
    $allOk = $allOk -and $patchOk
}
catch {
    Write-Check "chrome-devtools-mcp patch markers" $false $_.Exception.Message
    $allOk = $false
}

if (-not $allOk) {
    exit 1
}
