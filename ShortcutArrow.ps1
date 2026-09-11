<#
    Shortcut Arrow overlay tweak for Windows 10 / 11
    ------------------------------------------------------------------
    Removes the little arrow overlay drawn on shortcut icons by
    overriding the shell overlay icon (Shell Icons value 29) with a
    fully transparent icon.

    Why not just delete IsShortcut?
      Deleting HKCR\lnkfile\IsShortcut also hides the arrow, but it
      makes Windows stop treating .lnk as a shortcut. Known fallout:
        - "Pin to taskbar" / "Pin to Start" disappear or stop working
        - Launching a shortcut may fail with
          "This file does not have an app associated with it"
        - Drag & drop onto the taskbar breaks
      This script never touches IsShortcut.

    Usage:
      ShortcutArrow.ps1 -Action Remove
      ShortcutArrow.ps1 -Action Restore

    Options:
      -Action         Remove (default) | Restore
      -UseSystemIcon  use "%SystemRoot%\System32\imageres.dll,195"
                      instead of a generated .ico file
      -NoRestart      do not restart explorer.exe

    The transparent icon is stored in
      %LOCALAPPDATA%\ShortcutArrow\blank.ico
    so that moving this script does not break the registry entry.
#>
[CmdletBinding()]
param(
    [ValidateSet('Remove', 'Restore')]
    [string]$Action = 'Remove',

    [switch]$UseSystemIcon,

    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.1.0'
$BaseDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$IcoDir   = Join-Path $env:LOCALAPPDATA 'ShortcutArrow'
$IcoPath  = Join-Path $IcoDir 'blank.ico'
$LogPath  = Join-Path $BaseDir 'ShortcutArrow.log'
$KeyTail  = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons'
$SysIcon  = '%SystemRoot%\System32\imageres.dll,195'

function Write-Log {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-BlankIco {
    param(
        [string]$Path,
        [int[]]$Sizes = @(16, 32, 48)
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $images = @()
    foreach ($s in $Sizes) {
        $ms = New-Object System.IO.MemoryStream
        $bw = New-Object System.IO.BinaryWriter($ms)

        # BITMAPINFOHEADER - biHeight is doubled (XOR bitmap + AND mask)
        $bw.Write([int]40)
        $bw.Write([int]$s)
        $bw.Write([int](2 * $s))
        $bw.Write([int16]1)                      # biPlanes
        $bw.Write([int16]32)                     # biBitCount
        $bw.Write([int]0)                        # biCompression = BI_RGB
        $bw.Write([int]($s * $s * 4))            # biSizeImage
        $bw.Write([int]0); $bw.Write([int]0)     # pels per meter
        $bw.Write([int]0); $bw.Write([int]0)     # clrUsed / clrImportant

        # XOR bitmap: all zero bytes => transparent black (BGRA)
        $bw.Write((New-Object byte[] ($s * $s * 4)))

        # AND mask: every bit set => "leave screen unchanged" (transparent).
        # Row stride is padded to a 4-byte boundary.
        $rowBytes = [int]([math]::Ceiling($s / 32.0) * 4)
        $row = New-Object byte[] $rowBytes
        for ($i = 0; $i -lt $rowBytes; $i++) { $row[$i] = 0xFF }
        for ($y = 0; $y -lt $s; $y++) { $bw.Write($row) }

        $bw.Flush()
        $images += , @{ Size = $s; Data = $ms.ToArray() }
        $bw.Dispose()
        $ms.Dispose()
    }

    $fs = [System.IO.File]::Create($Path)
    $bw = New-Object System.IO.BinaryWriter($fs)

    # ICONDIR
    $bw.Write([int16]0)                  # reserved
    $bw.Write([int16]1)                  # type = icon
    $bw.Write([int16]$images.Count)

    # ICONDIRENTRY table (16 bytes each)
    $offset = 6 + (16 * $images.Count)
    foreach ($img in $images) {
        $dim = 0
        if ($img.Size -lt 256) { $dim = $img.Size }
        $bw.Write([byte]$dim)            # width  (0 means 256)
        $bw.Write([byte]$dim)            # height
        $bw.Write([byte]0)               # color count
        $bw.Write([byte]0)               # reserved
        $bw.Write([int16]1)              # planes
        $bw.Write([int16]32)             # bit count
        $bw.Write([int]$img.Data.Length) # bytes in resource
        $bw.Write([int]$offset)          # offset
        $offset += $img.Data.Length
    }
    foreach ($img in $images) { $bw.Write($img.Data) }

    $bw.Flush()
    $bw.Dispose()
    $fs.Dispose()
}

function Clear-IconCache {
    $explorerDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    $targets = @(
        @{ Dir = $env:LOCALAPPDATA; Filter = 'IconCache.db' },
        @{ Dir = $explorerDir;      Filter = 'iconcache_*.db' },
        @{ Dir = $explorerDir;      Filter = 'thumbcache_*.db' }
    )
    foreach ($t in $targets) {
        if (Test-Path -LiteralPath $t.Dir) {
            Get-ChildItem -LiteralPath $t.Dir -Filter $t.Filter -Force -ErrorAction SilentlyContinue |
                ForEach-Object {
                    try {
                        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop
                    } catch {
                        Write-Log ('  cache locked, skipped: ' + $_.Name)
                    }
                }
        }
    }
    Write-Log '  icon cache cleared'
}

function Restart-Explorer {
    Write-Log '  restarting explorer.exe ...'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
        Start-Process 'explorer.exe'
        Start-Sleep -Seconds 2
    }
}

function Set-ArrowOverride {
    param([string]$Hive, [string]$Value)

    $path = Join-Path $Hive $KeyTail
    try {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -Path $path -Force | Out-Null
        }
        New-ItemProperty -Path $path -Name '29' -Value $Value -PropertyType String -Force | Out-Null
        Write-Log ('  OK   ' + $Hive + ' value 29 = ' + $Value)
        return $true
    } catch {
        Write-Log ('  FAIL ' + $Hive + ' not writable (run as Administrator)')
        return $false
    }
}

function Remove-ArrowOverride {
    param([string]$Hive)

    $path = Join-Path $Hive $KeyTail
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Log ('  skip ' + $Hive + ' (key absent)')
        return
    }
    $existing = Get-ItemProperty -Path $path -Name '29' -ErrorAction SilentlyContinue
    if ($null -eq $existing) {
        Write-Log ('  skip ' + $Hive + ' (value absent)')
        return
    }
    try {
        Remove-ItemProperty -Path $path -Name '29' -Force -ErrorAction Stop
        Write-Log ('  OK   ' + $Hive + ' value 29 removed')
    } catch {
        Write-Log ('  FAIL ' + $Hive + ' not writable (run as Administrator)')
    }
}

# ----------------------------------------------------------------------------
# main
# ----------------------------------------------------------------------------
$isAdmin = Test-IsAdmin
Write-Log ('=== ShortcutArrow v' + $ScriptVersion + '  Action=' + $Action + '  Admin=' + $isAdmin + ' ===')

if ($Action -eq 'Remove') {

    if ($UseSystemIcon) {
        $iconValue = $SysIcon
        Write-Log ('  using built-in icon: ' + $iconValue)
    }
    else {
        if (-not (Test-Path -LiteralPath $IcoPath)) {
            Write-Log ('  generating transparent icon: ' + $IcoPath)
            New-BlankIco -Path $IcoPath
        }
        $iconValue = $IcoPath
        Write-Log ('  icon ready (' + (Get-Item -LiteralPath $IcoPath).Length + ' bytes)')
    }

    if ($isAdmin) {
        [void](Set-ArrowOverride -Hive 'HKLM:' -Value $iconValue)
    } else {
        Write-Log '  not elevated - HKLM cannot be written, using HKCU only'
    }
    [void](Set-ArrowOverride -Hive 'HKCU:' -Value $iconValue)

    Clear-IconCache
    if (-not $NoRestart) { Restart-Explorer }

    Write-Log '=== done. Shortcut arrows are hidden. ==='
    if (-not $isAdmin) {
        Write-Log 'NOTE: re-run as Administrator for a system-wide effect.'
    }
    if ($UseSystemIcon) {
        Write-Log 'NOTE: if the arrow looks wrong, re-run without -UseSystemIcon.'
    }
}
else {
    if ($isAdmin) { Remove-ArrowOverride -Hive 'HKLM:' }
    else { Write-Log '  not elevated - HKLM not checked' }
    Remove-ArrowOverride -Hive 'HKCU:'

    Clear-IconCache
    if (-not $NoRestart) { Restart-Explorer }

    Write-Log '=== done. Shortcut arrows restored. ==='
    if (Test-Path -LiteralPath $IcoDir) {
        Write-Log ('NOTE: generated icon folder left in place: ' + $IcoDir)
    }
}
