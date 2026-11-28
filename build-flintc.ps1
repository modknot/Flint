# Build flintc without a checked-in compiler binary or external assembler.
# 1. Assemble src/seed/*.asm into build/flint0.exe with bootstrap/asm.ps1.
# 2. Expand // include: directives into build/flintc.unit.fl.
# 3. Compile that translation unit with flint0 into a stage-1 compiler.
# 4. Let stage 1 compile the same unit again; install stage 2 as flintc.exe.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'scripts\flint-source.ps1')

$srcRoot = Join-Path $root 'src\flintc\flintc.fl'
$outDir = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$unit = Join-Path $outDir 'flintc.unit.fl'
$stage1 = Join-Path $outDir 'flintc-stage1.exe'
$exe = Join-Path $outDir 'flintc.exe'
$stage0 = Join-Path $outDir 'flint0.exe'

& pwsh -NoProfile -File (Join-Path $root 'bootstrap\build-flint0.ps1')
if ($LASTEXITCODE -ne 0) { throw "flint0 build failed ($LASTEXITCODE)" }

$expanded = Expand-FlintSource -Path $srcRoot
[IO.File]::WriteAllLines($unit, $expanded, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "[flintc] source unit: $unit"

& $stage0 $unit $stage1
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $stage1)) {
    throw "stage 1 compile failed ($LASTEXITCODE)"
}

$out = Join-Path $outDir 'flintc-out.exe'
Remove-Item $out -Force -ErrorAction SilentlyContinue
& $stage1
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $out)) {
    throw "stage 2 compile failed ($LASTEXITCODE)"
}
Copy-Item $out $exe -Force

Write-Host ("[flintc] {0} ({1} bytes)" -f $exe, (Get-Item -LiteralPath $exe).Length)
