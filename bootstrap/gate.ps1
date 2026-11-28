# ===========================================================================
# Bootstrap gate: from arithmetic to a source-driven compiler skeleton.
# Each level is a capability needed to write a compiler in Flint.
# The highest passing level shows how far the current compiler has come.
# Usage: pwsh -NoProfile -File bootstrap\gate.ps1
# ===========================================================================
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$compiler = Join-Path $root 'build\flintc.exe'
$ladder = Join-Path $PSScriptRoot 'ladder'
$outDir = Join-Path $root 'build\bootstrap'
New-Item -ItemType Directory -Force $outDir | Out-Null

if (-not (Test-Path -LiteralPath $compiler)) {
    Write-Host '[gate] build/flintc.exe is missing; run bootstrap/cold-start.ps1 once'
    exit 1
}

$report = @()
$fail = 0
foreach ($f in (Get-ChildItem -LiteralPath $ladder -Filter *.fl | Sort-Object Name)) {
    $text = Get-Content -LiteralPath $f.FullName -Raw
    $wantOut = if ($text -match '// EXPECT stdout:(.*)') { $Matches[1].Trim() } else { '' }
    $wantExit = if ($text -match '// EXPECT exit:(\d+)') { [int]$Matches[1] } else { 0 }
    $exe = Join-Path $outDir ([IO.Path]::GetFileNameWithoutExtension($f.Name) + '.exe')
    if (Test-Path -LiteralPath $exe) { Remove-Item -LiteralPath $exe -Force }

    $compileSrc = $f.FullName
    if ($text -match '// BUILD (.+)') {
        $compileSrc = Join-Path $PSScriptRoot $Matches[1].Trim()
    }
    if (-not (Test-Path -LiteralPath $compileSrc)) {
        $report += [pscustomobject]@{ Level = $f.Name; Result = 'FAIL(compile)'; Detail = "missing source: $compileSrc" }
        $fail++
        continue
    }

    $compile = (& $compiler $compileSrc $exe 2>&1 | Out-String).Trim()
    if (-not (Test-Path -LiteralPath $exe)) {
        $reason = ($compile -split "`n" | Where-Object { $_ -match 'error|失败|不是' } | Select-Object -First 1)
        if (-not $reason) { $reason = $compile }
        $report += [pscustomobject]@{ Level = $f.Name; Result = 'FAIL(compile)'; Detail = $reason.Trim() }
        $fail++
        continue
    }

    $runOut = ((& $exe 2>&1 | Out-String).Trim())
    $code = $LASTEXITCODE
    if ($runOut -eq $wantOut -and $code -eq $wantExit) {
        $report += [pscustomobject]@{ Level = $f.Name; Result = 'PASS'; Detail = "stdout=$runOut exit=$code" }
    } else {
        $report += [pscustomobject]@{ Level = $f.Name; Result = 'FAIL(run)'; Detail = "stdout=$runOut exit=$code expected stdout=$wantOut exit=$wantExit" }
        $fail++
    }
}

$report | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
$text = ($report | ForEach-Object { "$($_.Level)`t$($_.Result)`t$($_.Detail)" }) -join "`n"
[IO.File]::WriteAllText((Join-Path $root 'build\bootstrap-gate.txt'), "Bootstrap gate $(Get-Date -Format s)`n$text`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Passed $($report.Count - $fail) / $($report.Count); details in build\bootstrap-gate.txt"
if ($fail -gt 0) { exit 1 }
exit 0
