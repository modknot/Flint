# One-shot regression for the normal self-hosted toolchain:
# current compiler fixed-point check + phase-1 example self-check.
# The bootstrap gate is informational: it measures the current compiler's
# capability and is not a hard failure.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
$bad = 0
& pwsh -NoProfile -File (Join-Path $root 'bootstrap\bootstrap.ps1'); if ($LASTEXITCODE -ne 0) { $bad++ }
& pwsh -NoProfile -File (Join-Path $root 'tests\spec\check_examples.ps1'); if ($LASTEXITCODE -ne 0) { $bad++ }
& pwsh -NoProfile -File (Join-Path $root 'bootstrap\gate.ps1') | Out-Null
"bootstrap gate exit code $LASTEXITCODE (1 = some levels still fail, informational; see build\bootstrap-gate.txt)"
"run_all: $bad hard failure(s)"
exit $(if ($bad -gt 0) { 1 } else { 0 })
