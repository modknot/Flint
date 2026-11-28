# Self-host check with the current fixed-point compiler.
# The compiler compiles its own split source, then the next compiler compiles
# the same source again. The two outputs must be byte-identical.
# The assembly seed is not used here; it exists only for bootstrap/cold-start.ps1.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root 'build'
$src = Join-Path $root 'src\flintc\flintc.fl'
$compiler = Join-Path $build 'flintc.exe'

if (-not (Test-Path -LiteralPath $compiler)) {
    throw "build/flintc.exe is missing; run bootstrap/cold-start.ps1 once"
}

$stage1 = Join-Path $build 'flintc-bootstrap1.exe'
$stage2 = Join-Path $build 'flintc-bootstrap2.exe'
Remove-Item $stage1, $stage2 -Force -ErrorAction SilentlyContinue

Push-Location $root
try {
    & $compiler $src $stage1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "current compiler -> bootstrap stage1 failed ($LASTEXITCODE)" }
    if (-not (Test-Path -LiteralPath $stage1)) { throw "bootstrap stage1 produced no output" }

    & $stage1 $src $stage2 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "bootstrap stage1 -> stage2 failed ($LASTEXITCODE)" }
    if (-not (Test-Path -LiteralPath $stage2)) { throw "bootstrap stage2 produced no output" }
}
finally { Pop-Location }

$h1 = (Get-FileHash -LiteralPath $stage1 -Algorithm SHA256).Hash
$h2 = (Get-FileHash -LiteralPath $stage2 -Algorithm SHA256).Hash
if ($h1 -ne $h2) { throw "fixed point not reached: $h1 != $h2" }
Write-Host "[bootstrap] next-generation fixed point OK: $h1"
