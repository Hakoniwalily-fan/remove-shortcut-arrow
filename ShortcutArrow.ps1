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
    v1.4.0
      * ROOT CAUSE CORRECTED. v1.3.0 blamed the 32bpp pixel format and
        switched to 1bpp. That was wrong: a 1bpp icon with an all-ones
        AND mask is a COMPLETELY EMPTY icon, and an empty overlay icon
        is what the shell composites as an opaque black square.

        Measured on Windows 11 build 26200, Intel iGPU + NVIDIA dGPU:

          fully transparent icon (zero pixels with alpha > 0), whether
            1bpp/all-ones-mask or 32bpp/alpha=0 ......... black square
          same slots, same icon cache, same paths, icon carrying a
            single pixel at alpha = 2/255 ............... no black square

        The variable is "is the icon empty", not the bit depth - and not
        the file path either (a non-ASCII %LOCALAPPDATA% path was tested
        separately and behaves correctly). v1.4.0 therefore generates a
        32bpp icon that is almost empty: every pixel transparent except
        ONE pixel at alpha = 2/255. That is invisible (0.8% opacity) but
        keeps the icon non-empty. The AND mask matches the ink exactly.

      * -Action Remove now verifies the result END TO END: after the
        restart it extracts the icons of real desktop shortcuts and
        measures how many of their pixels are opaque black. If every
        sample comes back pure black the change is rolled back
        automatically and the script exits non-zero. v1.3.0 shipped a
        regression that blackened every shortcut on this hardware while
        -Action Verify cheerfully reported "no problems found".

        Two traps were found while building that check, and both are now
        handled:

          - The process that makes the change CANNOT see the result. With
            an empty overlay installed, the script's own process reported
            38% ("fine") at t+5s through t+60s while a freshly spawned
            process reported 100% at the very same moments. The
            measurement is therefore delegated to a child process.

          - The shell can serve stale composites for a moment after the
            registry change and the cache clear, so the child is sampled
            repeatedly over a short window and the WORST reading decides.
            In the regression test the first sample read 38% and the
            second read 100% - which is what triggered the rollback.

      * Operation order fixed: the registry is written FIRST, then the shell is
        stopped, its icon cache deleted, and the shell started again.
        v1.3.0 deleted the cache while explorer was still running, which
        silently failed (measured: 30 files present, 0 deleted). Writing the
        registry AFTER restarting the shell is just as bad: Windows restarts
        explorer.exe by itself (AutoRestartShell is on by default), and a shell
        that comes back before the registry write rebuilds its icon cache from
        the OLD value. The desktop then keeps showing the previous overlay while
        every fresh process reads the new registry value and reports "normal".
        Reproduced live on the affected machine: shortcuts stayed red after a
        red probe icon was removed. The number of cache files actually deleted
        is logged instead of an unconditional "icon cache cleared".

      * Measured how slots 29/77 are actually painted on the affected machine,
        by registering an opaque RED probe icon: the overlay covers the ENTIRE
        shortcut icon (all 1024 pixels of a 32x32 icon turn red) and nothing is
        layered on top of it - the overlay REPLACES the arrow rather than
        sitting under it. That is why a completely empty overlay is so
        destructive there (the whole icon goes black) and why a single faint
        ink pixel is enough to make it invisible.

      * -IconFormat values renamed to say what they do:
          Faint32bpp  (default, safe)   one ink pixel at alpha = 2/255
          Empty1bpp   (unsafe, legacy)  the v1.3.0 icon: empty
          Empty32bpp  (unsafe, legacy)  the v1.2.0 icon: empty
        Mask1bpp and Legacy32bpp are still accepted as aliases.

      * tests/Test-ShortcutArrow.ps1 added. It pins the contract: the
        generated icon must not be empty, must stay faint, and the
        validator must reject both legacy empty formats.

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
      -IconFormat     Faint32bpp (default, safe) | Empty1bpp | Empty32bpp
                      The Empty* formats are the pre-1.4.0 icons. Both are
                      completely empty and both blacken every shortcut on
                      affected systems, so -Action Remove refuses them: they
                      exist so the failure stays reproducible in the tests.
                      Mask1bpp / Legacy32bpp are accepted as aliases.
      -UseSystemIcon  DEPRECATED, see the warning printed by -Action Remove
      -Force          regenerate the icon even if it already exists
      -NoRestart      do not restart explorer.exe

    The transparent icon is stored in
      %LOCALAPPDATA%\ShortcutArrow\blank.ico
    so that moving this script does not break the registry entry. (The path
    itself is not a factor in the black-square bug: a non-ASCII
    %LOCALAPPDATA% path was measured and behaves correctly.)
#>
[CmdletBinding()]
param(
    [ValidateSet('Remove', 'Restore', 'Verify')]
    [string]$Action = 'Remove',

    [switch]$IncludeShield,

    # Faint32bpp is the safe default. The Empty* formats reproduce the old
    # (broken) behaviour: they exist so the failure can be demonstrated and so
    # that old command lines keep parsing. Mask1bpp / Legacy32bpp are aliases.
    [ValidateSet('Faint32bpp', 'Empty1bpp', 'Empty32bpp', 'Mask1bpp', 'Legacy32bpp')]
    [string]$IconFormat = 'Faint32bpp',

    [switch]$UseSystemIcon,

    [switch]$Force,

    [switch]$NoRestart
)

$ErrorActionPreference = 'Stop'

# Dot-sourcing the script (` . .\ShortcutArrow.ps1`) only defines the functions,
# which is how tests/Test-ShortcutArrow.ps1 drives them. Executing the file
# normally runs the main block at the bottom.
$Script:DotSourced = ($MyInvocation.InvocationName -eq '.')

$ScriptVersion = '1.4.0'
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

# The overlay must NOT be completely empty. An empty overlay icon is what the
# shell composites as an opaque black square over the whole shortcut; one pixel
# at this alpha keeps the icon non-empty while remaining invisible (0.8%
# opacity). Verified on the affected machine: alpha = 2 shows nothing and the
# black squares stay away.
$InkAlpha = 2

# Built-in blank icon, kept only for -UseSystemIcon.
# NOTE: shell32.dll,50 is itself a fully transparent (i.e. EMPTY) icon, so it
# sits in the same risky class as the Empty* formats. Kept for backwards
# compatibility only.
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

function Test-IconFormatAlias {
    <#  Map a possibly-legacy -IconFormat value onto its canonical name. #>
    param([Parameter(Mandatory)][string]$Name)
    switch ($Name) {
        'Mask1bpp'    { return 'Empty1bpp' }
        'Legacy32bpp' { return 'Empty32bpp' }
        default       { return $Name }
    }
}

function New-TransparentIco {
    <#
        Hand-assembles the overlay .ico.

        Faint32bpp (default, safe)
            32bpp BGRA. Every pixel is transparent (0,0,0,0) except ONE
            pixel at alpha = $InkAlpha, whose AND-mask bit is cleared to
            match. The icon is therefore non-empty - and being non-empty is
            exactly what stops the shell from compositing it as an opaque
            black square - while the ink stays invisible in practice.

            Why not a "cleaner" all-transparent icon: on Windows 11 build
            26200 (Intel iGPU + NVIDIA dGPU) ANY fully transparent overlay
            is painted as an opaque black square over the whole shortcut,
            whether it is 1bpp with an all-ones mask or 32bpp with alpha=0.
            One faint pixel removes the failure. The bit depth does not
            matter - and a 1bpp image cannot express "faint": it can only
            be completely empty or show an opaque black pixel, which is why
            v1.3.0's 1bpp "fix" still blackened every icon.

        Empty1bpp / Empty32bpp (unsafe, legacy)
            The v1.3.0 and v1.2.0 icons. Both are completely empty and both
            blacken every shortcut on affected systems. They are kept so the
            bug can be reproduced in tests; -Action Remove refuses to
            install them.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Faint32bpp', 'Empty1bpp', 'Empty32bpp', 'Mask1bpp', 'Legacy32bpp')]
        [string]$Format = 'Faint32bpp',
        [int[]]$Sizes = $IcoSizes
    )

    $Format = Test-IconFormatAlias -Name $Format

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $images = @()
    foreach ($s in $Sizes) {
        $isFaint = ($Format -eq 'Faint32bpp')

        if ($isFaint -or $Format -eq 'Empty32bpp') {
            $bpp    = 32
            $xorRow = $s * 4
        }
        else {
            $bpp    = 1
            $xorRow = [int]([Math]::Ceiling($s / 32.0) * 4)   # 1bpp row padded to 4 bytes
        }
        $maskRow = [int]([Math]::Ceiling($s / 32.0) * 4)

        $ms = New-Object System.IO.MemoryStream
        $bw = New-Object System.IO.BinaryWriter($ms)

        # BITMAPINFOHEADER. biHeight is doubled: XOR bitmap + AND mask.
        $bw.Write([int]40)                                   # biSize
        $bw.Write([int]$s)                                   # biWidth
        $bw.Write([int](2 * $s))                             # biHeight
        $bw.Write([int16]1)                                  # biPlanes
        $bw.Write([int16]$bpp)                               # biBitCount
        $bw.Write([int]0)                                    # BI_RGB
        $bw.Write([int]($xorRow * $s))                       # biSizeImage
        $bw.Write([int]0); $bw.Write([int]0)                 # pels per meter
        if ($bpp -eq 1) {
            $bw.Write([int]2); $bw.Write([int]2)             # clrUsed / clrImportant
            $bw.Write([byte[]](0, 0, 0, 0))                  # palette[0] = black
            $bw.Write([byte[]](255, 255, 255, 0))            # palette[1] = white
        }
        else {
            $bw.Write([int]0); $bw.Write([int]0)             # clrUsed / clrImportant
        }

        # XOR bitmap: all zeros (transparent black) except the single ink pixel
        # that keeps the icon from being completely empty.
        $xor = New-Object byte[] ($xorRow * $s)

        # AND mask: a set bit means "leave the screen unchanged".
        $mask = New-Object byte[] ($maskRow * $s)
        for ($i = 0; $i -lt $mask.Length; $i++) { $mask[$i] = 0xFF }

        if ($isFaint) {
            # Visual top-left pixel. BMP rows are stored bottom-up, so it lives
            # in the last file row; clear bit 0 of that row's first mask byte.
            $xor[(($s - 1) * $s) * 4 + 3] = [byte]$InkAlpha
            $mi = ($s - 1) * $maskRow
            $mask[$mi] = [byte]([int]$mask[$mi] -band 0x7F)
        }

        $bw.Write($xor)
        $bw.Write($mask)

        $bw.Flush()
        $images += , @{ Size = $s; Bpp = $bpp; Data = $ms.ToArray() }
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
        $colors = 0
        if ($img.Bpp -eq 1) { $colors = 2 }
        $bw.Write([byte]$dim)            # width  (0 means 256)
        $bw.Write([byte]$dim)            # height (0 means 256)
        $bw.Write([byte]$colors)         # colour count
        $bw.Write([byte]0)               # reserved
        $bw.Write([int16]1)              # planes
        $bw.Write([int16]$img.Bpp)       # bit count
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

function Get-IcoContent {
    <#
        Read-only inspection of what an .ico actually contains, straight from
        the bytes - no GDI+ involved, so it reports what the file says rather
        than what one particular renderer makes of it.

        TotalInk is the number of pixels that are not fully transparent:
          32bpp -> pixels whose alpha byte is > 0
          1bpp  -> bits set in the XOR bitmap (a visible pixel)

        TotalInk = 0 means a COMPLETELY EMPTY icon. That is the condition the
        shell turns into an opaque black square, and it is the one thing
        v1.3.0's format-only check could not see.
    #>
    param([Parameter(Mandatory)][string]$Path)

    $r = [pscustomobject]@{
        Ok           = $false
        Sizes        = @()
        Bpp          = @()
        TotalInk     = 0
        MaxInkAlpha  = 0
        OpaqueBlack  = 0
        MaskMismatch = 0
        Empty        = $true
        Images       = @()
        Message      = ''
    }

    if (-not (Test-Path -LiteralPath $Path)) { $r.Message = 'file not found'; return $r }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if (($bytes.Length -lt 6) -or
        ([BitConverter]::ToUInt16($bytes, 0) -ne 0) -or
        ([BitConverter]::ToUInt16($bytes, 2) -ne 1)) {
        $r.Message = 'not a valid .ico'
        return $r
    }

    $count  = [BitConverter]::ToUInt16($bytes, 4)
    $images = @()

    for ($i = 0; $i -lt $count; $i++) {
        $o = 6 + (16 * $i)
        if (($o + 16) -gt $bytes.Length) { break }

        $w   = [int]$bytes[$o]
        if ($w -eq 0) { $w = 256 }
        $bpp = [BitConverter]::ToUInt16($bytes, $o + 6)
        $off = [BitConverter]::ToUInt32($bytes, $o + 12)

        $img = [pscustomobject]@{
            Width = $w; Bpp = $bpp; Ink = 0; MaxAlpha = 0; Opaque = 0; MaskMismatch = 0
        }

        if (($off + 40) -gt $bytes.Length) { $images += $img; continue }
        if (($bytes[$off] -eq 0x89) -and ($bytes[$off + 1] -eq 0x50)) {
            # PNG-compressed image: no AND mask, alpha lives inside the PNG.
            $img.MaxAlpha = -1
            $images += $img
            continue
        }

        $biSize  = [BitConverter]::ToUInt32($bytes, $off)
        $biBpp   = [BitConverter]::ToUInt16($bytes, $off + 14)
        $palLen  = 0
        if ($biBpp -le 8) { $palLen = (1 -shl $biBpp) * 4 }
        $xorRow  = [int]([Math]::Floor(($w * $biBpp + 31) / 32) * 4)
        $maskRow = [int]([Math]::Floor(($w + 31) / 32) * 4)
        $xorOff  = $off + $biSize + $palLen
        $maskOff = $xorOff + ($xorRow * $w)

        for ($y = 0; $y -lt $w; $y++) {
            for ($x = 0; $x -lt $w; $x++) {
                $ink = $false

                if ($biBpp -eq 32) {
                    $p = $xorOff + ((($y * $w) + $x) * 4)
                    if (($p + 3) -lt $bytes.Length) {
                        $a = [int]$bytes[$p + 3]
                        if ($a -gt 0) {
                            $ink = $true
                            $img.Ink = $img.Ink + 1
                            if ($a -gt $img.MaxAlpha) { $img.MaxAlpha = $a }
                            if (($a -ge 200) -and ($bytes[$p] -le 12) -and
                                ($bytes[$p + 1] -le 12) -and ($bytes[$p + 2] -le 12)) {
                                $img.Opaque = $img.Opaque + 1
                            }
                        }
                    }
                }
                else {
                    $p = $xorOff + ($y * $xorRow) + [int][Math]::Floor($x / 8)
                    if ($p -lt $bytes.Length) {
                        $bit = 7 - ($x % 8)
                        if (((([int]$bytes[$p]) -shr $bit) -band 1) -eq 1) {
                            $ink = $true
                            $img.Ink = $img.Ink + 1
                            $img.MaxAlpha = 255
                            $img.Opaque = $img.Opaque + 1
                        }
                    }
                }

                # AND mask: a cleared bit should mean "ink", a set bit "transparent".
                $mp = $maskOff + ($y * $maskRow) + [int][Math]::Floor($x / 8)
                if ($mp -lt $bytes.Length) {
                    $mbit = 7 - ($x % 8)
                    $mval = (([int]$bytes[$mp]) -shr $mbit) -band 1
                    if (($mval -eq 0) -ne $ink) { $img.MaskMismatch = $img.MaskMismatch + 1 }
                }
            }
        }

        $r.TotalInk     = $r.TotalInk + $img.Ink
        $r.OpaqueBlack  = $r.OpaqueBlack + $img.Opaque
        $r.MaskMismatch = $r.MaskMismatch + $img.MaskMismatch
        if ($img.MaxAlpha -gt $r.MaxInkAlpha) { $r.MaxInkAlpha = $img.MaxAlpha }
        $images += $img
    }

    $r.Images = $images
    $r.Sizes  = @($images | ForEach-Object { $_.Width })
    $r.Bpp    = @($images | ForEach-Object { $_.Bpp } | Sort-Object -Unique)
    $r.Empty  = ($r.TotalInk -eq 0)
    $r.Ok     = ((-not $r.Empty) -and ($r.OpaqueBlack -eq 0))
    return $r
}

function Get-IcoFormat {
    <#  Detected format. Says EMPTY when the icon carries no ink at all. #>
    param([Parameter(Mandatory)]$Info, $Content)

    $bpps = @($Info | ForEach-Object { $_.BitsPerPixel } | Sort-Object -Unique)
    if ($bpps.Count -eq 0) { return 'unknown' }

    $empty = $true
    if ($Content) { $empty = [bool]$Content.Empty }

    if (($bpps.Count -eq 1) -and ($bpps[0] -eq 1)) {
        if ($empty) { return 'Empty1bpp' } else { return '1bpp-ink' }
    }
    if ($bpps -contains 32) {
        if ($empty) { return 'Empty32bpp' } else { return '32bpp-ink' }
    }
    return ('mixed:' + ($bpps -join '/'))
}

function Test-TransparentIco {
    <#
        Answers one question: is this icon SAFE to install as the overlay?

        A safe overlay icon
          * is NOT completely empty. An empty overlay is what the shell
            composites as an opaque black square over the whole shortcut on
            affected systems. This is the check v1.3.0 lacked: it inspected
            the FORMAT and declared a completely empty 1bpp icon "safe".
          * contains no opaque black pixels (a blank icon that paints black
            is not blank)
          * has an AND mask that agrees with its ink

        ExpectFormat optionally pins the pixel-format class. The legacy
        Empty1bpp / Empty32bpp classes can never pass, because being empty is
        exactly the defect this function exists to catch.
    #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('Faint32bpp', 'Empty1bpp', 'Empty32bpp', 'Mask1bpp', 'Legacy32bpp', 'Any')]
        [string]$ExpectFormat = 'Any'
    )

    $r = [pscustomobject]@{
        Ok           = $true
        Format       = 'unknown'
        Sizes        = @()
        Empty        = $false
        TotalInk     = 0
        MaxInkAlpha  = 0
        OpaqueBlack  = 0
        MaskMismatch = 0
        Message      = ''
    }

    $content = Get-IcoContent -Path $Path
    if ($content.Message) { $r.Ok = $false; $r.Message = $content.Message; return $r }

    $info = Get-IcoInfo -Path $Path
    if (-not $info) { $r.Ok = $false; $r.Message = 'not a valid .ico'; return $r }

    $r.Format       = Get-IcoFormat -Info $info -Content $content
    $r.Sizes        = $content.Sizes
    $r.Empty        = $content.Empty
    $r.TotalInk     = $content.TotalInk
    $r.MaxInkAlpha  = $content.MaxInkAlpha
    $r.OpaqueBlack  = $content.OpaqueBlack
    $r.MaskMismatch = $content.MaskMismatch

    if ($r.Empty) {
        $r.Ok = $false
        $r.Message = 'icon is completely empty - the shell paints an empty overlay as an opaque black square over the whole shortcut'
        return $r
    }
    if ($r.OpaqueBlack -gt 0) {
        $r.Ok = $false
        $r.Message = ('{0} opaque black pixel(s) found - this icon is not blank' -f $r.OpaqueBlack)
        return $r
    }
    if ($r.MaskMismatch -gt 0) {
        $r.Ok = $false
        $r.Message = ('{0} pixel(s) where the AND mask disagrees with the ink' -f $r.MaskMismatch)
        return $r
    }

    $want = Test-IconFormatAlias -Name $ExpectFormat
    if ($want -eq 'Faint32bpp') {
        if (($content.Bpp.Count -ne 1) -or (-not ($content.Bpp -contains 32))) {
            $r.Ok = $false
            $r.Message = ('expected a 32bpp icon, found {0}' -f ($content.Bpp -join '/'))
            return $r
        }
    }
    return $r
}

function Measure-OverlayBlack {
    <#
        ONE observation of how black the desktop shortcuts look, measured in a
        FRESHLY SPAWNED process.

        Why a child process: the process that just changed the overlay registry
        value and cleared the icon cache can keep reporting the PREVIOUS
        composites for as long as it lives. Measured on the affected machine
        with a deliberately empty overlay installed:

            t+5s .. t+60s   the process that made the change: 38%  ("fine")
            t+5s .. t+60s   a fresh process, same moments:    100% (black)

        An in-process check is therefore blind to exactly the regression it is
        meant to catch - which is how v1.3.0 could ship a machine where every
        shortcut was a black square while reporting "no problems found".

        Read-only; the child process only reads icons.
    #>
    param(
        [int]$MaxBlackPercent = 95,
        [int]$SampleCount = 6
    )

    $r = [pscustomobject]@{
        Ok              = $true
        Sampled         = 0
        MaxBlackPercent = 0
        Verdict         = 'not sampled'
        Details         = @()
    }

    $desktop = [Environment]::GetFolderPath('Desktop')
    $links = @()
    if ($desktop -and (Test-Path -LiteralPath $desktop)) {
        $links = @(Get-ChildItem -LiteralPath $desktop -Filter '*.lnk' -ErrorAction SilentlyContinue |
                   Select-Object -First $SampleCount)
    }
    if ($links.Count -lt 2) {
        $r.Verdict = 'skipped: fewer than two desktop shortcuts to sample'
        return $r
    }

    $desktop = [Environment]::GetFolderPath('Desktop')
    $outFile = Join-Path $env:TEMP ('sa-overlay-' + [guid]::NewGuid().ToString('N') + '.txt')
    $sample  = $SampleCount

    $code = @"
`$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Drawing
`$lines = @()
foreach (`$p in (Get-ChildItem -LiteralPath "$desktop" -Filter '*.lnk' | Select-Object -First $sample)) {
    `$pct = -1
    try {
        `$ic = [System.Drawing.Icon]::ExtractAssociatedIcon(`$p.FullName)
        `$bm = `$ic.ToBitmap()
        `$w = `$bm.Width; `$h = `$bm.Height; `$op = 0; `$dk = 0
        for (`$y = 0; `$y -lt `$h; `$y++) {
            for (`$x = 0; `$x -lt `$w; `$x++) {
                `$c = `$bm.GetPixel(`$x, `$y)
                if (`$c.A -gt 200) { `$op++; if (`$c.R -lt 24 -and `$c.G -lt 24 -and `$c.B -lt 24) { `$dk++ } }
            }
        }
        `$bm.Dispose(); `$ic.Dispose()
        if (`$op -gt 0) { `$pct = [math]::Round(100 * `$dk / `$op, 1) }
    } catch { }
    `$lines += ('{0}={1}' -f `$p.BaseName, `$pct)
}
Set-Content -LiteralPath "$outFile" -Value (`$lines -join ';') -Encoding UTF8
"@

    $b64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    try {
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand',$b64) `
            -WindowStyle Hidden -Wait -ErrorAction Stop
    }
    catch {
        $r.Verdict = 'skipped: could not start the measurement process'
        return $r
    }
    if (-not (Test-Path -LiteralPath $outFile)) {
        $r.Verdict = 'skipped: the measurement process produced no result'
        return $r
    }

    $raw = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue

    foreach ($part in ($raw -split ';')) {
        if ($part -match '^(.*)=(-?\d+(?:\.\d+)?)$') {
            $pct = [double]$Matches[2]
            if ($pct -lt 0) { $pct = $null }
            $r.Details += [pscustomobject]@{ Name = $Matches[1]; BlackPercent = $pct }
            if ($null -ne $pct) {
                $r.Sampled++
                if ($pct -gt $r.MaxBlackPercent) { $r.MaxBlackPercent = $pct }
            }
        }
    }

    if ($r.Sampled -lt 2) {
        $r.Verdict = 'skipped: could not read enough shortcut icons'
        return $r
    }
    if ($r.MaxBlackPercent -gt $MaxBlackPercent) {
        $r.Ok = $false
        $r.Verdict = ('FAIL: shortcuts are rendered as solid black squares (max {0}% opaque black pixels) - the overlay composite is broken' -f $r.MaxBlackPercent)
    }
    else {
        $r.Verdict = ('OK: sampled {0} shortcut(s), max {1}% opaque black pixels' -f $r.Sampled, $r.MaxBlackPercent)
    }
    return $r
}

function Test-OverlayResult {
    <#
        End-to-end check: does the desktop actually LOOK right?

        Every observation runs in a fresh process (see Measure-OverlayBlack)
        and the check repeats over a short window, letting the WORST reading
        decide: right after explorer restarts the shell may still be mid
        rebuild, and a single sample taken then is not evidence either way.

        This is the check that would have caught the v1.3.0 regression, whose
        own verification inspected the icon FILE's format, found nothing wrong
        and declared the machine healthy while every shortcut on the desktop
        was painted as a black square.

        Read-only; safe to call at any time.
    #>
    param(
        [int]$MaxBlackPercent = 95,
        [int]$SampleCount = 6,
        [int]$Attempts = 3,
        [int]$AttemptDelaySeconds = 3
    )

    $r = [pscustomobject]@{
        Ok              = $true
        Sampled         = 0
        MaxBlackPercent = 0
        Attempts        = 0
        Verdict         = 'not sampled'
        Details         = @()
    }

    $worstMax    = -1
    $worstDetail = @()
    $bestSampled = 0

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        Start-Sleep -Seconds $AttemptDelaySeconds
        $m = Measure-OverlayBlack -SampleCount $SampleCount

        if ($m.Sampled -lt 2) {
            if ($attempt -eq $Attempts) { $r.Verdict = 'skipped: ' + $m.Verdict; return $r }
            continue
        }

        $r.Attempts = $attempt
        if ($m.Sampled -gt $bestSampled) { $bestSampled = $m.Sampled }
        if ($m.MaxBlackPercent -gt $worstMax) {
            $worstMax    = $m.MaxBlackPercent
            $worstDetail = $m.Details
        }

        Write-Log ('    overlay check {0}/{1}: worst {2}% opaque black over {3} shortcut(s)' -f $attempt, $Attempts, $m.MaxBlackPercent, $m.Sampled)

        if ($m.MaxBlackPercent -gt $MaxBlackPercent) { break }
    }

    $r.Sampled = $bestSampled
    if ($worstMax -ge 0) { $r.MaxBlackPercent = $worstMax }
    $r.Details = $worstDetail

    if ($r.Sampled -lt 2) {
        $r.Verdict = 'skipped: could not read enough shortcut icons'
        return $r
    }
    if ($r.MaxBlackPercent -gt $MaxBlackPercent) {
        $r.Ok = $false
        $r.Verdict = ('FAIL: shortcuts are rendered as solid black squares (worst of {0} observation(s): {1}% opaque black pixels) - the overlay composite is broken' -f $r.Attempts, $r.MaxBlackPercent)
    }
    else {
        $r.Verdict = ('OK: sampled {0} shortcut(s) over {1} observation(s), worst {2}% opaque black pixels' -f $r.Sampled, $r.Attempts, $r.MaxBlackPercent)
    }
    return $r
}

function Stop-Explorer {
    <#
        Kill the shell and wait for it to be gone, so its icon cache files can
        be deleted (the shell holds them open).

        Windows restarts explorer.exe on its own (AutoRestartShell is on by
        default), sometimes within a second or two. That is harmless now,
        because the caller writes the registry BEFORE stopping the shell: a
        shell that comes back already reads the new value. Clear-IconCache
        retries if a cache file still turns out to be locked.
    #>
    Write-Log '  stopping explorer.exe ...'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    for ($i = 0; $i -lt 16; $i++) {
        if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
            Start-Sleep -Milliseconds 400
            if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) { return }
        }
        Start-Sleep -Milliseconds 250
    }
    Write-Log '  note: explorer.exe is running again (Windows restarts the shell itself);'
    Write-Log '        the cache step retries if a file is locked.'
}

function Start-Explorer {
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
        Write-Log '  starting explorer.exe ...'
        Start-Process 'explorer.exe'
        Start-Sleep -Seconds 3
    }
    # Let the shell settle before the result is measured.
    Start-Sleep -Seconds 6
}

function Clear-IconCache {
    <#
        Must run while explorer.exe is STOPPED.

        v1.3.0 deleted these files with the shell still running, which fails
        silently - measured on the affected machine: 30 files present, 0
        deleted - and leaves the wrong (black) composites cached. That is why
        "rebuild the icon cache" appeared not to help. The counts are logged
        now instead of an unconditional "icon cache cleared".
    #>
    $explorerDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'
    $targets = @(
        @{ Dir = $env:LOCALAPPDATA; Filter = 'IconCache.db' },
        @{ Dir = $explorerDir;      Filter = 'iconcache_*.db' },
        @{ Dir = $explorerDir;      Filter = 'thumbcache_*.db' }
    )

    $existed = 0; $deleted = 0; $locked = 0
    for ($pass = 1; $pass -le 2; $pass++) {
        $existed = 0; $deleted = 0; $locked = 0
        foreach ($t in $targets) {
            if (Test-Path -LiteralPath $t.Dir) {
                foreach ($f in @(Get-ChildItem -LiteralPath $t.Dir -Filter $t.Filter -Force -ErrorAction SilentlyContinue)) {
                    $existed++
                    try {
                        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                        $deleted++
                    }
                    catch {
                        $locked++
                        Write-Log ('  cache file could not be deleted: ' + $f.Name)
                    }
                }
            }
        }
        if ($locked -eq 0) { break }
        if ($pass -eq 1) {
            # Almost always a freshly auto-restarted shell holding the files.
            Write-Log '  some cache files were locked - stopping explorer.exe again and retrying'
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
    }

    Write-Log ('  icon cache: {0} file(s) found, {1} deleted, {2} locked' -f $existed, $deleted, $locked)
    if ($locked -gt 0) {
        Write-Log '  WARNING: some cache files stayed locked. Stale composites may survive this run.'
        Write-Log '           Reboot and run again if the desktop still looks wrong.'
    }
    return [pscustomobject]@{ Existed = $existed; Deleted = $deleted; Locked = $locked }
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
if (-not $Script:DotSourced) {

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
                Write-Log '         -> NOTE: an EMPTY overlay icon renders as an opaque black square'
                Write-Log '            over the whole icon on affected systems. Prefer the generated icon.'
                continue
            }

            $info    = Get-IcoInfo -Path $file
            $content = Get-IcoContent -Path $file
            if ($info) { $fmt = Get-IcoFormat -Info $info -Content $content } else { $fmt = 'unreadable' }
            $test  = Test-TransparentIco -Path $file -ExpectFormat 'Any'
            $sizes = ($test.Sizes | Sort-Object -Unique) -join ','
            Write-Log ('         -> {0}  format={1}  sizes={2}  ink={3}  maxInkAlpha={4}' -f $file, $fmt, $sizes, $content.TotalInk, $content.MaxInkAlpha)

            if (-not $test.Ok) {
                Write-Log ('         -> PROBLEM: icon failed verification ({0})' -f $test.Message)
                $problems++
            }
            else {
                Write-Log '         -> OK: the icon is non-empty and contains no opaque black pixels.'
            }
        }
    }
    # The check that actually matters: what does the desktop look like?
    $result = Test-OverlayResult
    Write-Log ('  overlay check: ' + $result.Verdict)
    foreach ($d in $result.Details) {
        Write-Log ('    {0} = {1}% opaque black' -f $d.Name, $d.BlackPercent)
    }
    if (-not $result.Ok) {
        Write-Log '         -> PROBLEM: shortcuts are painted as black squares right now.'
        Write-Log '            Run -Action Restore (or delete both Shell Icons values) to recover.'
        $problems++
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
        Write-Log ('           {0} is itself a fully transparent icon, i.e. an EMPTY one,' -f $SystemIcon)
        Write-Log '           so it sits in the same risky class as the Empty* formats: an'
        Write-Log '           empty overlay can be composited as an opaque black square over'
        Write-Log '           every shortcut. The generated icon is the safe path.'
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
        Write-Log ('  icon ready: {0} bytes  format={1}  sizes={2}  ink={3}  maxInkAlpha={4}' -f $len, $test.Format, $sz, $test.TotalInk, $test.MaxInkAlpha)
        Write-Log ('  sha256    : ' + $hash)

        if (-not $test.Ok) {
            Write-Log '  ABORT: the generated icon did not pass verification, so the'
            Write-Log '         registry was left untouched. Nothing was changed.'
            exit 1
        }
        $iconValue = $IcoPath
    }

    # Order matters, and getting it wrong is worse than doing nothing:
    #   1. write the registry FIRST
    #   2. only then stop the shell, clear its cache and start it again
    # Windows restarts explorer.exe by itself (AutoRestartShell is on by
    # default). A shell that starts BEFORE the registry write reads the OLD
    # value and rebuilds its icon cache from it, so the desktop keeps showing
    # the previous overlay. Observed on the affected machine: shortcuts stayed
    # red after the red probe was removed, while every fresh process (including
    # the end-to-end check) read the new registry value and reported "normal".
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

    if (-not $NoRestart) { Stop-Explorer }
    [void](Clear-IconCache)
    if (-not $NoRestart) { Start-Explorer }

    # End-to-end verification. If the desktop came out worse than it went in,
    # undo the change instead of leaving a broken desktop behind.
    $result = Test-OverlayResult
    Write-Log ('  overlay check: ' + $result.Verdict)
    foreach ($d in $result.Details) {
        Write-Log ('    {0} = {1}% opaque black' -f $d.Name, $d.BlackPercent)
    }

    if (-not $result.Ok) {
        Write-Log '  FAIL: the overlay made shortcuts render as black squares.'
        Write-Log '        Rolling the change back ...'
        foreach ($slot in @($ArrowSlot, $ShieldSlot)) {
            if ($isAdmin) { Remove-OverlaySlot -Hive 'HKLM:' -Slot $slot }
            Remove-OverlaySlot -Hive 'HKCU:' -Slot $slot
        }
        if (-not $NoRestart) {
            Stop-Explorer
            [void](Clear-IconCache)
            Start-Explorer
        }
        Write-Log '  rolled back: no overlay icon is registered any more.'
        Write-Log '  Please report this, including ShortcutArrow.log and your Windows build.'
        exit 1
    }

    Write-Log '=== done. ==='
    if (-not $isAdmin) {
        Write-Log 'NOTE: re-run as Administrator for a system-wide effect.'
    }
    if (-not $IncludeShield) {
        Write-Log 'NOTE: the UAC shield was left untouched. Add -IncludeShield to hide it too.'
    }
    Write-Log 'NOTE: every run now measures the desktop afterwards and rolls back by'
    Write-Log '      itself if shortcuts ever come out as black squares.'
}
else {
    # Registry first, shell restart second - see the note in the Remove branch.
    # Restore always clears BOTH slots, so a hidden shield can never linger
    # by accident after a partial run.
    foreach ($slot in @($ArrowSlot, $ShieldSlot)) {
        if ($isAdmin) { Remove-OverlaySlot -Hive 'HKLM:' -Slot $slot }
        else { Write-Log ('  not elevated - HKLM value ' + $slot + ' not checked') }
        Remove-OverlaySlot -Hive 'HKCU:' -Slot $slot
    }

    if (-not $NoRestart) { Stop-Explorer }
    [void](Clear-IconCache)
    if (-not $NoRestart) { Start-Explorer }

    $result = Test-OverlayResult
    Write-Log ('  overlay check: ' + $result.Verdict)

    Write-Log '=== done. Shortcut arrow and UAC shield restored to Windows defaults. ==='
    if (Test-Path -LiteralPath $IcoDir) {
        Write-Log ('NOTE: generated icon folder left in place: ' + $IcoDir)
        Write-Log '      Re-running -Action Remove regenerates the icon in the current format.'
    }
}

}   # if (-not $Script:DotSourced)
