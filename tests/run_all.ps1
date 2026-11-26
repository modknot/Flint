# 一键回归：阶段零验收 + 阶段一示例自检 + 自举闸门（闸门当前预期未全过，仅作能力度量，不计入失败）
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$bad = 0
& pwsh -NoProfile -File (Join-Path $root 'tests\run_p0.ps1'); if ($LASTEXITCODE -ne 0) { $bad++ }
& pwsh -NoProfile -File (Join-Path $root 'tests\spec\check_examples.ps1'); if ($LASTEXITCODE -ne 0) { $bad++ }
& pwsh -NoProfile -File (Join-Path $root 'bootstrap\gate.ps1') | Out-Null
"bootstrap gate 退出码 $LASTEXITCODE（1=尚有级别未通过，属当前预期，明细见 build\bootstrap-gate.txt）"
"run_all: $bad 项硬失败"
exit $(if ($bad -gt 0) { 1 } else { 0 })
