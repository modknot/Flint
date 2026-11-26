# ===========================================================================
# 阶段一示例自检：数量、命名、头注释、manifest 覆盖率与期望格式
# 用法：pwsh -NoProfile -File tests\spec\check_examples.ps1
# 样例尚未可执行（多数特性在后续阶段实现），本脚本只做结构校验。
# ===========================================================================
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exDir = Join-Path $root 'tests\spec\examples'
$manifest = Join-Path $root 'tests\spec\manifest.csv'

$files = Get-ChildItem -LiteralPath $exDir -Filter *.fl | Sort-Object Name
$fail = 0

if ($files.Count -lt 40) { Write-Host "[FAIL] 示例数量 $($files.Count) < 40"; $fail++ }
else { Write-Host "[OK]   示例数量 $($files.Count) >= 40" }

$rows = @{}
foreach ($line in (Get-Content -LiteralPath $manifest)) {
    if (-not $line.Trim()) { continue }
    $parts = $line.Split(',')
    if ($parts.Count -lt 2) { Write-Host "[FAIL] manifest 行格式错误: $line"; $fail++; continue }
    $rows[$parts[0]] = @{ kind = $parts[1]; expect = ($parts[2..($parts.Count - 1)] -join ',') }
}

foreach ($f in $files) {
    $text = Get-Content -LiteralPath $f.FullName -Raw
    $name = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    if ($text -notmatch ('^// SPEC-EXAMPLE ' + [regex]::Escape($name))) {
        Write-Host "[FAIL] $($f.Name) 缺少匹配的头注释"; $fail++
    }
    if (-not $rows.ContainsKey($f.Name)) {
        Write-Host "[FAIL] $($f.Name) 未登记到 manifest.csv"; $fail++
        continue
    }
    $kind = $rows[$f.Name].kind
    if ($kind -notin @('ok', 'cerr', 'rerr')) {
        Write-Host "[FAIL] $($f.Name) kind=$kind 非法"; $fail++
    }
    if ($kind -eq 'cerr' -and $rows[$f.Name].expect -notmatch '^E\d{4}$') {
        Write-Host "[FAIL] $($f.Name) cerr 期望必须是 E<四位>"; $fail++
    }
}

foreach ($k in $rows.Keys) {
    if (-not (Test-Path -LiteralPath (Join-Path $exDir $k))) {
        Write-Host "[FAIL] manifest 中的 $k 不存在"; $fail++
    }
}

if ($fail -gt 0) { Write-Host "自检失败：$fail 项"; exit 1 }
Write-Host '自检通过'
exit 0
