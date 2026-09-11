# One-line installer for remove-shortcut-arrow.
#
#   irm https://raw.githubusercontent.com/Hakoniwalily-fan/remove-shortcut-arrow/main/install.ps1 | iex
#
# Downloads the current ShortcutArrow.ps1 into %LOCALAPPDATA%\ShortcutArrow\ and
# runs it, re-launching elevated when needed.
#
# ASCII-only on purpose: non-ASCII inside a .ps1 breaks under non-UTF8 code pages.

[CmdletBinding()]
param(
    [ValidateSet('Remove', 'Restore')]
    [string]$Action = 'Remove',

    # Also hide the UAC shield overlay (Shell Icons value 77).
    # Opt-in: the shield is a warning indicator, so it is never hidden by default.
    [switch]$IncludeShield,

    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'

$Repo    = 'Hakoniwalily-fan/remove-shortcut-arrow'
$Branch  = 'main'
$BaseUrl = 'https://raw.githubusercontent.com/' + $Repo + '/' + $Branch
$ScriptName = 'ShortcutArrow.ps1'
$DestDir = Join-Path $env:LOCALAPPDATA 'ShortcutArrow'
$Target  = Join-Path $DestDir $ScriptName
$BatFiles = @('Remove-ShortcutArrow.bat', 'Remove-ArrowAndShield.bat', 'Restore-ShortcutArrow.bat')

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-RemoteFile {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile
    )

    # Windows PowerShell 5.1 may still default to TLS 1.0, which GitHub rejects.
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {
        # PowerShell 7+ ignores this; not fatal either way.
    }

    $webClient = $null
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
    } catch {
        # Fallback for hosts where Invoke-WebRequest is unavailable or proxied oddly.
        $webClient = New-Object System.Net.WebClient
        $webClient.Headers.Add('User-Agent', 'remove-shortcut-arrow-installer')
        $webClient.DownloadFile($Url, $OutFile)
    }
    finally {
        if ($webClient) { $webClient.Dispose() }
    }
}

Write-Host ''
Write-Host '  remove-shortcut-arrow installer' -ForegroundColor Cyan
Write-Host '  ------------------------------'
Write-Host ''

# ---------------------------------------------------------------- 1. download
if (-not (Test-Path -LiteralPath $DestDir)) {
    New-Item -ItemType Directory -Path $DestDir -Force | Out-Null
}

Write-Host ('  Downloading ' + $ScriptName + ' ...')
$tmp = $Target + '.tmp'
try {
    Get-RemoteFile -Url ($BaseUrl + '/' + $ScriptName) -OutFile $tmp
    Move-Item -LiteralPath $tmp -Destination $Target -Force
} catch {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host ('  Download failed: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host '  If you are behind a proxy, set HTTPS_PROXY and retry, or just'
    Write-Host '  download the release zip manually from:'
    Write-Host ('  https://github.com/' + $Repo + '/releases/latest')
    exit 1
}
Write-Host ('    -> ' + $Target) -ForegroundColor DarkGray

# Optional convenience: keep the double-click launchers alongside the script.
foreach ($bat in $BatFiles) {
    try {
        Get-RemoteFile -Url ($BaseUrl + '/' + $bat) -OutFile (Join-Path $DestDir $bat)
    } catch {
        Write-Host ('    (skipped ' + $bat + ')') -ForegroundColor DarkGray
    }
}

# ----------------------------------------------------------------- 2. elevate
if (-not (Test-IsAdmin)) {
    Write-Host ''
    Write-Host '  Administrator rights are required for a machine-wide change.' -ForegroundColor Yellow
    Write-Host '  Requesting elevation - approve the UAC prompt to continue.'
    Write-Host ''
    $argList = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $Target + '"'),
        '-Action', $Action
    )
    if ($IncludeShield) { $argList += '-IncludeShield' }
    if ($NoRestart)     { $argList += '-NoRestart' }
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argList | Out-Null
    } catch {
        Write-Host '  Elevation was cancelled - nothing was changed.' -ForegroundColor Yellow
        exit 1
    }
    exit 0
}

# -------------------------------------------------------------------- 3. run
Write-Host ''
$forward = @('-Action', $Action)
if ($IncludeShield) { $forward += '-IncludeShield' }
if ($NoRestart)     { $forward += '-NoRestart' }
& $Target @forward
