# Build flintc from its multi-file Flint source without an assembler.
# 1. Expand // include: directives into build/flintc.unit.fl
# 2. Compile that translation unit with the previous compiler, bootstrap/flintc0.exe
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'scripts\flint-source.ps1')

$srcRoot = Join-Path $root 'src\flintc\flintc.fl'
$outDir = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$unit = Join-Path $outDir 'flintc.unit.fl'
$exe = Join-Path $outDir 'flintc.exe'
$stage0 = Join-Path $root 'bootstrap\flintc0.exe'

if (-not (Test-Path -LiteralPath $stage0)) {
    throw 'bootstrap/flintc0.exe is missing; it is the previous compiler used to build this one.'
}

$expanded = Expand-FlintSource -Path $srcRoot
[IO.File]::WriteAllLines($unit, $expanded, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[flintc] source unit: $unit"

& $stage0 $unit $exe
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe)) {
    throw "flintc compile failed ($LASTEXITCODE)"
}

Write-Host ("[flintc] {0} ({1} bytes)" -f $exe, (Get-Item -LiteralPath $exe).Length)
