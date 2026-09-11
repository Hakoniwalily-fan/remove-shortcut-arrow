<#
    Shortcut overlay tweak for Windows 10 / 11
    ------------------------------------------------------------------
    Hides the two shell overlays that are painted on top of icons:

      Shell Icons value 29  ->  the shortcut arrow
      Shell Icons value 77  ->  the UAC shield (elevation indicator)

    Both are pure overlay icons. Replacing them with a fully transparent
    icon hides the overlay without touching anything else.

    Why not just delete IsShortcut?
      Deleting HKCR\lnkfile\IsShortcut also hides the arrow, but it makes
      Windows stop treating .lnk as a shortcut. Known fallout:
        - "Pin to taskbar" / "Pin to Start" disappear or stop working
        - Launching a shortcut may fail with
          "This file does not have an app associated with it"
        - Drag & drop onto the taskbar breaks
      This script never touches IsShortcut.

    ABOUT THE SHIELD - READ THIS
      The shield is a WARNING, not a protection. Hiding it does NOT stop
      the program from requesting administrator rights: the UAC prompt
      still appears and the program still elevates. What you lose is the
      visual hint that a program is about to ask for admin.

      Hiding the shield is opt-in (-IncludeShield) and is never done by
      default. This script does NOT and will NOT edit executable
      manifests or disable UAC.

    Usage:
      ShortcutArrow.ps1 -Action Remove                     # arrow only
      ShortcutArrow.ps1 -Action Remove -IncludeShield      # arrow + shield
      ShortcutArrow.ps1 -Action Restore                    # restore both

    Options:
      -Action         Remove (default) | Restore
      -IncludeShield  also hide the UAC shield overlay (value 77)
      -UseSystemIcon  use a built-in blank icon instead of a generated .ico
      -NoRestart      do not restart explorer.exe

    The transparent icon is stored in
      %LOCALAPPDATA%\ShortcutArrow\blank.ico
    so that moving this script does not break the registry entry.
#>
[CmdletBinding()]
param(
    [ValidateSet('Remove', 'Restore')]
    [string]$Action = 'Remove',

    [switch]$IncludeShield,

    [switch]$UseSystemIcon,

    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.2.0'
$BaseDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$IcoDir   = Join-Path $env:LOCALAPPDATA 'ShortcutArrow'
$IcoPath  = Join-Path $IcoDir 'blank.ico'
$LogPath  = Join-Path $BaseDir 'ShortcutArrow.log'
$KeyTail  = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons'

# Overlay slot numbers. 29 = shortcut arrow, 77 = UAC shield.
$ArrowSlot  = '29'
$ShieldSlot = '77'

# Built-in fully transparent icons, verified with a pixel scan:
#   imageres.dll,195   Alpha = 0 on Windows 11 build 26200
#   shell32.dll,50     Alpha = 0, and is what most published guides use
$SystemIcon = '%SystemRoot%\System32\shell32.dll,50'

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
                    try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop }
                    catch { Write-Log ('  cache locked, skipped: ' + $_.Name) }
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

function Set-OverlaySlot {
    param([string]$Hive, [string]$Slot, [string]$IconValue)

    $path = Join-Path $Hive $KeyTail
    try {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -Path $path -Force | Out-Null
        }
        New-ItemProperty -Path $path -Name $Slot -Value $IconValue -PropertyType String -Force | Out-Null
        Write-Log ('  OK   ' + $Hive + ' value ' + $Slot + ' = ' + $IconValue)
        return $true
    } catch {
        Write-Log ('  FAIL ' + $Hive + ' value ' + $Slot + ' not writable (run as Administrator)')
        return $false
    }
}

function Remove-OverlaySlot {
    param([string]$Hive, [string]$Slot)

    $path = Join-Path $Hive $KeyTail
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Log ('  skip ' + $Hive + ' value ' + $Slot + ' (key absent)')
        return
    }
    $existing = Get-ItemProperty -Path $path -Name $Slot -ErrorAction SilentlyContinue
    if ($null -eq $existing) {
        Write-Log ('  skip ' + $Hive + ' value ' + $Slot + ' (not set)')
        return
    }
    $old = $existing.$Slot
    try {
        Remove-ItemProperty -Path $path -Name $Slot -Force -ErrorAction Stop
        Write-Log ('  OK   ' + $Hive + ' value ' + $Slot + ' removed (was: ' + $old + ')')
    } catch {
        Write-Log ('  FAIL ' + $Hive + ' value ' + $Slot + ' not writable (run as Administrator)')
    }
}

# ----------------------------------------------------------------------------
# main
# ----------------------------------------------------------------------------
$isAdmin = Test-IsAdmin
Write-Log ('=== ShortcutArrow v' + $ScriptVersion + '  Action=' + $Action + '  IncludeShield=' + [bool]$IncludeShield + '  Admin=' + $isAdmin + ' ===')

if ($Action -eq 'Remove') {

    $slots = @($ArrowSlot)
    if ($IncludeShield) { $slots += $ShieldSlot }

    if ($UseSystemIcon) {
        $iconValue = $SystemIcon
        Write-Log ('  using built-in transparent icon: ' + $iconValue)
    }
    else {
        if (-not (Test-Path -LiteralPath $IcoPath)) {
            Write-Log ('  generating transparent icon: ' + $IcoPath)
            New-BlankIco -Path $IcoPath
        }
        $iconValue = $IcoPath
        Write-Log ('  icon ready (' + (Get-Item -LiteralPath $IcoPath).Length + ' bytes)')
    }

    foreach ($slot in $slots) {
        if ($slot -eq $ShieldSlot) {
            Write-Log '  note: hiding the shield only hides the warning icon.'
            Write-Log '        Programs that need admin will still raise a UAC prompt.'
        }
        if ($isAdmin) {
            [void](Set-OverlaySlot -Hive 'HKLM:' -Slot $slot -IconValue $iconValue)
        } else {
            Write-Log ('  not elevated - HKLM value ' + $slot + ' cannot be written, using HKCU only')
        }
        [void](Set-OverlaySlot -Hive 'HKCU:' -Slot $slot -IconValue $iconValue)
    }

    Clear-IconCache
    if (-not $NoRestart) { Restart-Explorer }

    Write-Log '=== done. ==='
    if (-not $isAdmin) {
        Write-Log 'NOTE: re-run as Administrator for a system-wide effect.'
    }
    if (-not $IncludeShield) {
        Write-Log 'NOTE: the UAC shield was left untouched. Add -IncludeShield to hide it too.'
    }
}
else {
    # Restore always clears BOTH slots, so a hidden shield can never linger
    # by accident after a partial run.
    foreach ($slot in @($ArrowSlot, $ShieldSlot)) {
        if ($isAdmin) { Remove-OverlaySlot -Hive 'HKLM:' -Slot $slot }
        else { Write-Log ('  not elevated - HKLM value ' + $slot + ' not checked') }
        Remove-OverlaySlot -Hive 'HKCU:' -Slot $slot
    }

    Clear-IconCache
    if (-not $NoRestart) { Restart-Explorer }

    Write-Log '=== done. Shortcut arrow and UAC shield restored to Windows defaults. ==='
    if (Test-Path -LiteralPath $IcoDir) {
        Write-Log ('NOTE: generated icon folder left in place: ' + $IcoDir)
    }
}
