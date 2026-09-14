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


    CHANGELOG
    ------------------------------------------------------------------
    v1.3.0
      * DEFAULT ICON FORMAT CHANGED to 1bpp mask-based transparency.

        A fully transparent 32bpp icon (BGRA 0,0,0,0) is composited as
        OPAQUE BLACK by the shell on some systems, which paints a solid
        black square over the ENTIRE shortcut icon instead of hiding a
        small overlay. First-hand reproduction, Windows 11 build 26200,
        Intel + NVIDIA hybrid laptop:

          32bpp alpha=0 overlay  ->  every shortcut = a pure black square
          1bpp mask=all-ones     ->  overlay invisible, icon untouched

        Same registry slots, same machine, same icon cache. Only the icon
        format differed. A 1bpp image carries no alpha channel at all:
        "transparent" is expressed purely by the AND mask, so there is no
        alpha path left for the compositor to get wrong.

      * Ten icon sizes (16/20/24/32/40/48/64/96/128/256) instead of three.
      * The generated icon is verified before the registry is touched.
      * An existing blank.ico is re-checked on every run and regenerated
        when it is still in the old 32bpp format. v1.2.0 and earlier only
        generated the file when it was missing, so simply re-running the
        old version could never repair an affected machine.
      * -Action Verify: a read-only diagnostic that reports what is applied
        right now and whether the icon in use is a safe format.
      * -UseSystemIcon is deprecated: shell32.dll,50 is a 32bpp icon and
        therefore sits in the risky format class.

    v1.2.0
      * Opt-in hiding of the UAC shield overlay (slot 77).

    v1.1.0
      * Icon written to %LOCALAPPDATA% so the registry path stays valid.

    v1.0.0
      * Initial release.


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
      ShortcutArrow.ps1 -Action Verify                     # diagnose only

    Options:
      -Action         Remove (default) | Restore | Verify
      -IncludeShield  also hide the UAC shield overlay (value 77)
      -IconFormat     Mask1bpp (default, safe) | Legacy32bpp (known-risky)
      -UseSystemIcon  DEPRECATED, see the warning printed by -Action Remove
      -Force          regenerate the icon even if it already exists
      -NoRestart      do not restart explorer.exe

    The transparent icon is stored in
      %LOCALAPPDATA%\ShortcutArrow\blank.ico
    so that moving this script does not break the registry entry.
#>
[CmdletBinding()]
param(
    [ValidateSet('Remove', 'Restore', 'Verify')]
    [string]$Action = 'Remove',

    [switch]$IncludeShield,

    [ValidateSet('Mask1bpp', 'Legacy32bpp')]
    [string]$IconFormat = 'Mask1bpp',

    [switch]$UseSystemIcon,

    [switch]$Force,

    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'

$ScriptVersion = '1.3.0'
$BaseDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$IcoDir   = Join-Path $env:LOCALAPPDATA 'ShortcutArrow'
$IcoPath  = Join-Path $IcoDir 'blank.ico'
$LogPath  = Join-Path $BaseDir 'ShortcutArrow.log'
$KeyTail  = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Icons'

# Overlay slot numbers. 29 = shortcut arrow, 77 = UAC shield.
$ArrowSlot  = '29'
$ShieldSlot = '77'

# Every size Explorer may ask an overlay for, from small icons up to jumbo
# (256 px). A missing size forces Windows to scale another image, which is
# one more code path that can go wrong.
$IcoSizes = @(16, 20, 24, 32, 40, 48, 64, 96, 128, 256)

# Built-in blank icon, kept only for -UseSystemIcon.
# NOTE: this is a 32bpp icon, i.e. exactly the format that renders as an
# opaque black square on affected systems. Prefer the generated 1bpp icon.
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

function New-TransparentIco {
    <#
        Hand-assembles a fully transparent .ico.

        Mask1bpp (default, recommended)
            1bpp images: no alpha channel exists. Transparency is expressed
            by the AND mask, where every bit set means "leave the screen
            unchanged". There is nothing for a renderer to misinterpret.

        Legacy32bpp
            The format written by v1.2.0 and earlier: BGRA 0,0,0,0 pixels
            plus an all-ones mask. Correct on paper, and correct on most
            machines - but on affected systems the shell paints those
            pixels as opaque black, covering the whole icon.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Mask1bpp', 'Legacy32bpp')][string]$Format = 'Mask1bpp',
        [int[]]$Sizes = $IcoSizes
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $images = @()
    foreach ($s in $Sizes) {
        $rowBytes = [int]([Math]::Ceiling($s / 32.0) * 4)   # 1bpp row padded to 4 bytes
        $ms = New-Object System.IO.MemoryStream
        $bw = New-Object System.IO.BinaryWriter($ms)

        # BITMAPINFOHEADER. biHeight is doubled: XOR bitmap + AND mask.
        $bw.Write([int]40)                                   # biSize
        $bw.Write([int]$s)                                   # biWidth
        $bw.Write([int](2 * $s))                             # biHeight
        $bw.Write([int16]1)                                  # biPlanes

        if ($Format -eq 'Mask1bpp') {
            $bw.Write([int16]1)                              # biBitCount = 1
            $bw.Write([int]0)                                # BI_RGB
            $bw.Write([int]($rowBytes * $s))                 # biSizeImage
            $bw.Write([int]0); $bw.Write([int]0)             # pels per meter
            $bw.Write([int]2); $bw.Write([int]2)             # clrUsed / clrImportant

            $bw.Write([byte[]](0, 0, 0, 0))                  # palette[0] = black
            $bw.Write([byte[]](255, 255, 255, 0))            # palette[1] = white

            $bw.Write((New-Object byte[] ($rowBytes * $s)))  # XOR bitmap, all index 0
        }
        else {
            $bw.Write([int16]32)                             # biBitCount = 32
            $bw.Write([int]0)                                # BI_RGB
            $bw.Write([int]($s * $s * 4))                    # biSizeImage
            $bw.Write([int]0); $bw.Write([int]0)
            $bw.Write([int]0); $bw.Write([int]0)

            $bw.Write((New-Object byte[] ($s * $s * 4)))     # BGRA 0,0,0,0
        }

        # AND mask: every bit set => "leave screen unchanged" (transparent).
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
        $bpp = 1
        $colors = 2
        if ($Format -eq 'Legacy32bpp') { $bpp = 32; $colors = 0 }
        $bw.Write([byte]$dim)            # width  (0 means 256)
        $bw.Write([byte]$dim)            # height (0 means 256)
        $bw.Write([byte]$colors)         # colour count
        $bw.Write([byte]0)               # reserved
        $bw.Write([int16]1)              # planes
        $bw.Write([int16]$bpp)           # bit count
        $bw.Write([int]$img.Data.Length) # bytes in resource
        $bw.Write([int]$offset)          # offset
        $offset += $img.Data.Length
    }
    foreach ($img in $images) { $bw.Write($img.Data) }

    $bw.Flush()
    $bw.Dispose()
    $fs.Dispose()
}

function Get-IcoInfo {
    <#  Read-only: one object per image inside an .ico, or $null. #>
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 6) { return $null }
    if ([BitConverter]::ToUInt16($bytes, 0) -ne 0) { return $null }
    if ([BitConverter]::ToUInt16($bytes, 2) -ne 1) { return $null }

    $count = [BitConverter]::ToUInt16($bytes, 4)
    $list = @()
    for ($i = 0; $i -lt $count; $i++) {
        $o = 6 + (16 * $i)
        if (($o + 16) -gt $bytes.Length) { break }
        $w = [int]$bytes[$o]
        if ($w -eq 0) { $w = 256 }
        $list += [pscustomobject]@{
            Width        = $w
            BitsPerPixel = [BitConverter]::ToUInt16($bytes, $o + 6)
            Bytes        = [BitConverter]::ToUInt32($bytes, $o + 8)
            Offset       = [BitConverter]::ToUInt32($bytes, $o + 12)
        }
    }
    return $list
}

function Get-IcoFormat {
    param([Parameter(Mandatory)]$Info)
    $bpps = @($Info | ForEach-Object { $_.BitsPerPixel } | Sort-Object -Unique)
    if ($bpps.Count -eq 0) { return 'unknown' }
    if ($bpps.Count -eq 1 -and $bpps[0] -eq 1) { return 'Mask1bpp' }
    if ($bpps -contains 32) { return 'Legacy32bpp' }
    return ('mixed:' + ($bpps -join '/'))
}

function Test-TransparentIco {
    <#
        Two independent checks, and it matters which one does the work:

        1) FORMAT check - the real protection. A 32bpp icon is refused when
           Mask1bpp was requested. The shell-side bug that paints 32bpp
           alpha=0 overlays as opaque black is invisible to user-mode pixel
           readback, so no amount of pixel inspection can detect it.
           Avoiding the format is the only reliable defence.

        2) PIXEL sanity check - catches a malformed or accidentally opaque
           icon: a transparent overlay must contain zero opaque-black
           pixels. Skipped gracefully when System.Drawing is unavailable.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Mask1bpp', 'Legacy32bpp', 'Any')][string]$ExpectFormat = 'Any'
    )

    $r = [pscustomobject]@{
        Ok          = $true
        Format      = 'unknown'
        Sizes       = @()
        OpaqueBlack = 0
        PixelCheck  = 'skipped'
        Message     = ''
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        $r.Ok = $false; $r.Message = 'file not found'; return $r
    }
    $info = Get-IcoInfo -Path $Path
    if (-not $info) {
        $r.Ok = $false; $r.Message = 'not a valid .ico'; return $r
    }

    $r.Format = Get-IcoFormat -Info $info
    $r.Sizes  = @($info | ForEach-Object { $_.Width })

    if ($ExpectFormat -ne 'Any' -and $r.Format -ne $ExpectFormat) {
        $r.Ok = $false
        $r.Message = ('format is {0}, expected {1}' -f $r.Format, $ExpectFormat)
        return $r
    }

    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        $check = @(16, 32, 48) | Where-Object { $r.Sizes -contains $_ }
        if (-not $check) { $check = @($r.Sizes[0]) }
        foreach ($s in $check) {
            $ico = [System.Drawing.Icon]::new($Path, $s, $s)
            $bm  = $ico.ToBitmap()
            $rect = [System.Drawing.Rectangle]::new(0, 0, $bm.Width, $bm.Height)
            $data = $bm.LockBits($rect,
                        [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $buf = New-Object byte[] ($data.Stride * $bm.Height)
            [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buf, 0, $buf.Length)
            $bm.UnlockBits($data)
            for ($y = 0; $y -lt $bm.Height; $y++) {
                $rowOff = $y * $data.Stride
                for ($x = 0; $x -lt $bm.Width; $x++) {
                    $p = $rowOff + ($x * 4)
                    if (($buf[$p + 3] -ge 200) -and
                        ($buf[$p] -le 12) -and ($buf[$p + 1] -le 12) -and ($buf[$p + 2] -le 12)) {
                        $r.OpaqueBlack++
                    }
                }
            }
            $bm.Dispose(); $ico.Dispose()
        }
        $r.PixelCheck = 'ok'
    }
    catch {
        $r.PixelCheck = 'unavailable'
        $r.Message = $_.Exception.Message
    }

    if ($r.OpaqueBlack -gt 0) {
        $r.Ok = $false
        $r.Message = ('{0} opaque black pixel(s) found' -f $r.OpaqueBlack)
    }
    return $r
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

function Get-ShellIconValue {
    param([string]$Hive, [string]$Slot)
    $path = Join-Path $Hive $KeyTail
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return (Get-ItemProperty -Path $path -Name $Slot -ErrorAction SilentlyContinue).$Slot
}

function Set-OverlaySlot {
    param([string]$Hive, [string]$Slot, [string]$IconValue)

    $path = Join-Path $Hive $KeyTail
    try {
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -Path $path -Force | Out-Null
        }
        New-ItemProperty -Path $path -Name $Slot -Value $IconValue -PropertyType String -Force | Out-Null
        $readback = (Get-ItemProperty -Path $path -Name $Slot -ErrorAction SilentlyContinue).$Slot
        if ($readback -ne $IconValue) {
            Write-Log ('  FAIL ' + $Hive + ' value ' + $Slot + ' did not read back correctly')
            return $false
        }
        Write-Log ('  OK   ' + $Hive + ' value ' + $Slot + ' = ' + $IconValue)
        return $true
    }
    catch {
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
    }
    catch {
        Write-Log ('  FAIL ' + $Hive + ' value ' + $Slot + ' not writable (run as Administrator)')
    }
}

function Resolve-IconReference {
    <#  Turn a registry icon value into a real file path. #>
    param([string]$Value)
    if (-not $Value) { return $null }
    $file = $Value
    if ($file -match '^\s*"([^"]+)"') { $file = $Matches[1] }
    elseif ($file -match ',')          { $file = ($file -split ',')[0] }
    $file = [Environment]::ExpandEnvironmentVariables($file.Trim())
    return $file
}

# ----------------------------------------------------------------------------
# main
# ----------------------------------------------------------------------------
$isAdmin = Test-IsAdmin

# ------------------------------------------------------------------ Verify --
if ($Action -eq 'Verify') {
    Write-Log ('=== ShortcutArrow v' + $ScriptVersion + '  Action=Verify  (read-only) ===')
    $problems = 0
    $seen = @{}
    foreach ($hive in @('HKLM:', 'HKCU:')) {
        foreach ($slot in @($ArrowSlot, $ShieldSlot)) {
            if ($slot -eq $ArrowSlot) { $name = 'shortcut arrow' } else { $name = 'UAC shield' }
            $val = Get-ShellIconValue -Hive $hive -Slot $slot
            if (-not $val) {
                Write-Log ('  {0,-6} slot {1,-3} ({2,-14}) : not set  (Windows default)' -f $hive, $slot, $name)
                continue
            }
            Write-Log ('  {0,-6} slot {1,-3} ({2,-14}) : {3}' -f $hive, $slot, $name, $val)

            $file = Resolve-IconReference -Value $val
            if (-not (Test-Path -LiteralPath $file)) {
                Write-Log ('         -> file NOT FOUND: {0}' -f $file)
                Write-Log  '         -> PROBLEM: the overlay path is stale, the arrow will come back.'
                $problems++
                continue
            }
            if ($seen.ContainsKey($file)) { continue }
            $seen[$file] = $true

            if ($file -notmatch '\.ico$') {
                Write-Log '         -> external icon reference (not an .ico); cannot be inspected here.'
                Write-Log '         -> NOTE: a 32bpp alpha=0 overlay renders as an opaque black square'
                Write-Log '            over the whole icon on affected systems. Prefer the generated icon.'
                continue
            }

            $info = Get-IcoInfo -Path $file
            if ($info) { $fmt = Get-IcoFormat -Info $info } else { $fmt = 'unreadable' }
            $test  = Test-TransparentIco -Path $file -ExpectFormat 'Any'
            $sizes = ($test.Sizes | Sort-Object -Unique) -join ','
            Write-Log ('         -> {0}  format={1}  sizes={2}  pixelCheck={3}' -f $file, $fmt, $sizes, $test.PixelCheck)

            if ($fmt -eq 'Legacy32bpp') {
                Write-Log '         -> PROBLEM: this is the 32bpp format that paints entire shortcuts'
                Write-Log '            black on affected systems. Run -Action Remove to replace it.'
                $problems++
            }
            elseif (-not $test.Ok) {
                Write-Log ('         -> PROBLEM: icon failed verification ({0})' -f $test.Message)
                $problems++
            }
            else {
                Write-Log '         -> OK: mask-based transparency, safe format.'
            }
        }
    }
    if ($problems -eq 0) {
        Write-Log '=== no problems found. ==='
    }
    else {
        Write-Log ('=== {0} problem(s) found. ===' -f $problems)
        exit 1
    }
    return
}

Write-Log ('=== ShortcutArrow v' + $ScriptVersion + '  Action=' + $Action + '  IncludeShield=' + [bool]$IncludeShield + '  Format=' + $IconFormat + '  Admin=' + $isAdmin + ' ===')

if ($Action -eq 'Remove') {

    $slots = @($ArrowSlot)
    if ($IncludeShield) { $slots += $ShieldSlot }

    if ($UseSystemIcon) {
        Write-Log '  WARNING: -UseSystemIcon is deprecated.'
        Write-Log ('           {0} is a 32bpp icon - the same format class' -f $SystemIcon)
        Write-Log '           that renders as an opaque black square over the whole icon'
        Write-Log '           on affected systems. The generated 1bpp icon is the safe path.'
        $iconValue = $SystemIcon
    }
    else {
        $needGenerate = $true
        $reason = ''
        if (Test-Path -LiteralPath $IcoPath) {
            $existing = Test-TransparentIco -Path $IcoPath -ExpectFormat $IconFormat
            if ($Force) {
                $reason = 'forced'
            }
            elseif (-not $existing.Ok) {
                $reason = 'the existing icon failed verification (' + $existing.Message + ')'
            }
            else {
                $needGenerate = $false
            }
        }
        else {
            $reason = 'not present'
        }

        if ($needGenerate) {
            if ($reason) { Write-Log ('  regenerating transparent icon: ' + $reason) }
            else         { Write-Log ('  generating transparent icon: ' + $IcoPath) }
            if (Test-Path -LiteralPath $IcoPath) {
                Remove-Item -LiteralPath $IcoPath -Force -ErrorAction SilentlyContinue
            }
            New-TransparentIco -Path $IcoPath -Format $IconFormat -Sizes $IcoSizes
        }

        $test = Test-TransparentIco -Path $IcoPath -ExpectFormat $IconFormat
        $len  = (Get-Item -LiteralPath $IcoPath).Length
        $sz   = ($test.Sizes | Sort-Object -Unique) -join ','
        $hash = (Get-FileHash -LiteralPath $IcoPath -Algorithm SHA256).Hash
        Write-Log ('  icon ready: {0} bytes  format={1}  sizes={2}  pixelCheck={3}' -f $len, $test.Format, $sz, $test.PixelCheck)
        Write-Log ('  sha256    : ' + $hash)

        if (-not $test.Ok) {
            Write-Log '  ABORT: the generated icon did not pass verification, so the'
            Write-Log '         registry was left untouched. Nothing was changed.'
            exit 1
        }
        $iconValue = $IcoPath
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
    Write-Log 'NOTE: if every shortcut ever turns into a black square, run'
    Write-Log '      -Action Restore right away and report it.'
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
        Write-Log '      Re-running -Action Remove regenerates the icon in the current format.'
    }
}
