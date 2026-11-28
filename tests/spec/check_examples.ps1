# ===========================================================================
# Phase 1 example self-check: count, naming, header comment, manifest coverage,
# and expected-value format.
# Usage: pwsh -NoProfile -File tests\spec\check_examples.ps1
# Examples are not executable yet (most features arrive in later phases); this
# script performs structural checks only.
# ===========================================================================
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exDir = Join-Path $root 'tests\spec\examples'
$manifest = Join-Path $root 'tests\spec\manifest.csv'

$files = Get-ChildItem -LiteralPath $exDir -Filter *.fl | Sort-Object Name
$fail = 0

if ($files.Count -lt 40) { Write-Host "[FAIL] example count $($files.Count) < 40"; $fail++ }
else { Write-Host "[OK]   example count $($files.Count) >= 40" }

$rows = @{}
foreach ($line in (Get-Content -LiteralPath $manifest)) {
    if (-not $line.Trim()) { continue }
    $parts = $line.Split(',')
    if ($parts.Count -lt 2) { Write-Host "[FAIL] manifest line format error: $line"; $fail++; continue }
    $rows[$parts[0]] = @{ kind = $parts[1]; expect = ($parts[2..($parts.Count - 1)] -join ',') }
}

foreach ($f in $files) {
    $text = Get-Content -LiteralPath $f.FullName -Raw
    $name = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    if ($text -notmatch ('^// SPEC-EXAMPLE ' + [regex]::Escape($name))) {
        Write-Host "[FAIL] $($f.Name) is missing the matching header comment"; $fail++
    }
    if (-not $rows.ContainsKey($f.Name)) {
        Write-Host "[FAIL] $($f.Name) is not registered in manifest.csv"; $fail++
        continue
    }
    $kind = $rows[$f.Name].kind
    if ($kind -notin @('ok', 'cerr', 'rerr')) {
        Write-Host "[FAIL] $($f.Name) has invalid kind=$kind"; $fail++
    }
    if ($kind -eq 'cerr' -and $rows[$f.Name].expect -notmatch '^E\d{4}$') {
        Write-Host "[FAIL] $($f.Name) cerr expectation must be E<four digits>"; $fail++
    }
}

foreach ($k in $rows.Keys) {
    if (-not (Test-Path -LiteralPath (Join-Path $exDir $k))) {
        Write-Host "[FAIL] manifest entry $k does not exist"; $fail++
    }
}

if ($fail -gt 0) { Write-Host "self-check failed: $fail item(s)"; exit 1 }
Write-Host 'self-check passed'
exit 0
