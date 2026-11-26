# ===========================================================================
# 自举闸门：从算术到最小源码驱动编译器骨架。
# 每一级都是"用 Flint 写编译器"真正需要的底层能力。
# 上一级编译器能过到哪一级，就说明自举条件具备到哪一步；第一处失败即下一阶段任务。
# 用法：pwsh -NoProfile -File bootstrap\gate.ps1
# ===========================================================================
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts\flint-source.ps1')
$stage0 = Join-Path $root 'bootstrap\flintc0.exe'
$ladder = Join-Path $PSScriptRoot 'ladder'
$outDir = Join-Path $root 'build\bootstrap'
New-Item -ItemType Directory -Force $outDir | Out-Null

if (-not (Test-Path -LiteralPath $stage0)) {
    Write-Host '[gate] bootstrap/flintc0.exe 不存在'
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
        $report += [pscustomobject]@{ 级别 = $f.Name; 结果 = 'FAIL(编译)'; 实际 = "源文件不存在: $compileSrc" }
        $fail++
        continue
    }

    $compileText = Get-Content -LiteralPath $compileSrc -Raw
    if ($compileText -match '//\s*include:') {
        $unit = Join-Path $outDir ([IO.Path]::GetFileNameWithoutExtension($f.Name) + '.unit.fl')
        [IO.File]::WriteAllLines($unit, (Expand-FlintSource -Path $compileSrc), (New-Object System.Text.UTF8Encoding($false)))
        $compileSrc = $unit
    }

    $compile = (& $stage0 $compileSrc $exe 2>&1 | Out-String).Trim()
    if (-not (Test-Path -LiteralPath $exe)) {
        $reason = ($compile -split "`n" | Where-Object { $_ -match 'error|失败|不是' } | Select-Object -First 1)
        if (-not $reason) { $reason = $compile }
        $report += [pscustomobject]@{ 级别 = $f.Name; 结果 = 'FAIL(编译)'; 实际 = $reason.Trim() }
        $fail++
        continue
    }

    $runOut = ((& $exe 2>&1 | Out-String).Trim())
    $code = $LASTEXITCODE
    if ($runOut -eq $wantOut -and $code -eq $wantExit) {
        $report += [pscustomobject]@{ 级别 = $f.Name; 结果 = 'PASS'; 实际 = "stdout=$runOut exit=$code" }
    } else {
        $report += [pscustomobject]@{ 级别 = $f.Name; 结果 = 'FAIL(运行)'; 实际 = "stdout=$runOut exit=$code 期望 stdout=$wantOut exit=$wantExit" }
        $fail++
    }
}

$report | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
$text = ($report | ForEach-Object { "$($_.级别)`t$($_.结果)`t$($_.实际)" }) -join "`n"
[IO.File]::WriteAllText((Join-Path $root 'build\bootstrap-gate.txt'), "自举闸门 $(Get-Date -Format s)`n$text`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "通过 $($report.Count - $fail) / $($report.Count)，明细写入 build\bootstrap-gate.txt"
if ($fail -gt 0) { exit 1 }
exit 0
