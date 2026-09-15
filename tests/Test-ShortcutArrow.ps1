# Tests for ShortcutArrow.ps1
#
#   pwsh -File tests/Test-ShortcutArrow.ps1        (PowerShell 7)
#   powershell -File tests\Test-ShortcutArrow.ps1  (Windows PowerShell 5.1)
#
# No Pester dependency: this is a plain script that exits non-zero on failure.
# The main script is dot-sourced, so its functions become available without
# running any of its actions.

$ErrorActionPreference = 'Stop'

$repoRoot  = Split-Path -Parent $PSScriptRoot
$mainScript = Join-Path $repoRoot 'ShortcutArrow.ps1'
if (-not (Test-Path -LiteralPath $mainScript)) { throw "main script not found: $mainScript" }

# Dot-source: functions only. The main block is guarded and must not execute.
. $mainScript

$script:Passed = 0
$script:Failed = 0
function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:Passed++
        Write-Host ("  PASS  {0}" -f $Name) -ForegroundColor Green
    } else {
        $script:Failed++
        Write-Host ("  FAIL  {0}{1}" -f $Name, $(if ($Detail) { "  ($Detail)" } else { '' })) -ForegroundColor Red
    }
}

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ('sa-tests-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
Write-Host "work dir: $tmpDir"

try {
    # ---------------------------------------------------------------- generator --
    Write-Host ''
    Write-Host 'DEFAULT FORMAT (Faint32bpp)'
    $faint = Join-Path $tmpDir 'faint.ico'
    New-TransparentIco -Path $faint -Format 'Faint32bpp'
    Assert-True 'icon file is created' (Test-Path -LiteralPath $faint)

    $content = Get-IcoContent -Path $faint
    Assert-True 'icon is NOT empty (has ink)' ($content.TotalInk -gt 0) ("TotalInk=" + $content.TotalInk)
    Assert-True 'ink is faint, never opaque black' (($content.MaxInkAlpha -le 8) -and ($content.OpaqueBlack -eq 0)) `
                ("MaxInkAlpha=" + $content.MaxInkAlpha + " OpaqueBlack=" + $content.OpaqueBlack)
    Assert-True 'all ten sizes are present' ($content.Sizes.Count -eq 10) ("count=" + $content.Sizes.Count)
    Assert-True 'AND mask agrees with the ink pixels' ($content.MaskMismatch -eq 0) ("mismatch=" + $content.MaskMismatch)
    Assert-True 'validator accepts the default icon' ((Test-TransparentIco -Path $faint -ExpectFormat 'Faint32bpp').Ok)

    # ------------------------------------------------------- legacy empty formats --
    Write-Host ''
    Write-Host 'LEGACY EMPTY FORMATS (the v1.2.0 / v1.3.0 behaviour)'
    $empty1 = Join-Path $tmpDir 'empty1bpp.ico'
    New-TransparentIco -Path $empty1 -Format 'Empty1bpp'
    $c1 = Get-IcoContent -Path $empty1
    Assert-True 'Empty1bpp is detected as empty' ($c1.TotalInk -eq 0) ("TotalInk=" + $c1.TotalInk)
    Assert-True 'validator REJECTS Empty1bpp' (-not (Test-TransparentIco -Path $empty1 -ExpectFormat 'Empty1bpp').Ok)

    $empty32 = Join-Path $tmpDir 'empty32bpp.ico'
    New-TransparentIco -Path $empty32 -Format 'Empty32bpp'
    $c2 = Get-IcoContent -Path $empty32
    Assert-True 'Empty32bpp is detected as empty' ($c2.TotalInk -eq 0) ("TotalInk=" + $c2.TotalInk)
    Assert-True 'validator REJECTS Empty32bpp' (-not (Test-TransparentIco -Path $empty32 -ExpectFormat 'Empty32bpp').Ok)

    # ------------------------------------------------------------- legacy aliases --
    Write-Host ''
    Write-Host 'LEGACY ALIASES (old command lines must keep working)'
    Assert-True 'Mask1bpp is accepted as an alias' ((Test-IconFormatAlias -Name 'Mask1bpp') -eq 'Empty1bpp')
    Assert-True 'Legacy32bpp is accepted as an alias' ((Test-IconFormatAlias -Name 'Legacy32bpp') -eq 'Empty32bpp')
    Assert-True 'Faint32bpp maps to itself' ((Test-IconFormatAlias -Name 'Faint32bpp') -eq 'Faint32bpp')

    # ------------------------------------------------------------- live end-to-end --
    Write-Host ''
    Write-Host 'END-TO-END CHECK (read-only, uses the desktop shortcuts on this machine)'
    $res = Test-OverlayResult -Attempts 2 -AttemptDelaySeconds 1
    Assert-True 'returns a verdict object' ($null -ne $res -and $null -ne $res.Ok)
    Write-Host ("        Sampled={0}  MaxBlackPercent={1}  Verdict={2}" -f $res.Sampled, $res.MaxBlackPercent, $res.Verdict)
    if ($res.Sampled -ge 2) {
        Assert-True 'no shortcut is rendered as a black square right now' ([bool]$res.Ok) `
                    ("MaxBlackPercent=" + $res.MaxBlackPercent)
    } else {
        Write-Host '        (skipped: fewer than two desktop shortcuts to sample)'
    }
}
finally {
    Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("=== {0} passed, {1} failed ===" -f $script:Passed, $script:Failed)
if ($script:Failed -gt 0) { exit 1 }
exit 0
