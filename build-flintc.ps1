# Build flintc from its multi-file Flint source.
# 1. Expand // include: directives into build/flintc.unit.fl
# 2. Compile that translation unit with the NASM seed into build/flintc.exe

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'scripts\flint-source.ps1')

$srcRoot = Join-Path $root 'src\flintc\flintc.fl'
$outDir = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$unit = Join-Path $outDir 'flintc.unit.fl'
$exe = Join-Path $outDir 'flintc.exe'
$seed = Join-Path $outDir 'flint-seed.exe'

if (-not (Test-Path -LiteralPath $seed)) {
    & pwsh -NoProfile -File (Join-Path $root 'build.ps1')
    if ($LASTEXITCODE -ne 0) { throw "seed build failed ($LASTEXITCODE)" }
}

$expanded = Expand-FlintSource -Path $srcRoot
[IO.File]::WriteAllLines($unit, $expanded, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[flintc] source unit: $unit"

& $seed $unit $exe
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe)) {
    throw "flintc compile failed ($LASTEXITCODE)"
}

Write-Host ("[flintc] {0} ({1} bytes)" -f $exe, (Get-Item -LiteralPath $exe).Length)
