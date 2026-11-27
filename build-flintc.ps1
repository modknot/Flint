# Build flintc without a checked-in compiler binary or external assembler.
# 1. Assemble src/seed/*.asm into build/flint0.exe with bootstrap/asm.ps1.
# 2. Expand // include: directives into build/flintc.unit.fl.
# 3. Compile that translation unit with flint0.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'scripts\flint-source.ps1')

$srcRoot = Join-Path $root 'src\flintc\flintc.fl'
$outDir = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$unit = Join-Path $outDir 'flintc.unit.fl'
$exe = Join-Path $outDir 'flintc.exe'
$stage0 = Join-Path $outDir 'flint0.exe'

& pwsh -NoProfile -File (Join-Path $root 'bootstrap\build-flint0.ps1')
if ($LASTEXITCODE -ne 0) { throw "flint0 build failed ($LASTEXITCODE)" }

$expanded = Expand-FlintSource -Path $srcRoot
[IO.File]::WriteAllLines($unit, $expanded, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[flintc] source unit: $unit"

& $stage0 $unit $exe
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe)) {
    throw "flintc compile failed ($LASTEXITCODE)"
}

Write-Host ("[flintc] {0} ({1} bytes)" -f $exe, (Get-Item -LiteralPath $exe).Length)
