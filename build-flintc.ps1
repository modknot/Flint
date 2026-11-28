# Build flintc without a checked-in compiler binary or external assembler.
# 1. Assemble src/seed/*.asm into build/flint0.exe with bootstrap/asm.ps1.
# 2. Expand // include: directives into build/flintc.unit.fl for the seed stages.
# 3. Compile that translation unit with flint0 into a stage-1 compiler.
# 4. Let stage 1 compile the same unit into stage 2.
# 5. Let stage 2 and stage 3 compile the split source with the built-in loader;
#    require stage 3 == stage 4, then install stage 3 as flintc.exe.
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
$stage2 = Join-Path $outDir 'flintc-stage2.exe'
$stage3 = Join-Path $outDir 'flintc-stage3.exe'
$stage4 = Join-Path $outDir 'flintc-stage4.exe'
Copy-Item $out $stage2 -Force

Remove-Item $stage3 -Force -ErrorAction SilentlyContinue
& $stage2 $srcRoot $stage3
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $stage3)) {
    throw "stage 2 -> stage 3 (built-in include loader) failed ($LASTEXITCODE)"
}

Remove-Item $stage4 -Force -ErrorAction SilentlyContinue
& $stage3 $srcRoot $stage4
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $stage4)) {
    throw "stage 3 -> stage 4 (built-in include loader) failed ($LASTEXITCODE)"
}
Copy-Item $stage3 $exe -Force
$h2 = (Get-FileHash -LiteralPath $stage2 -Algorithm SHA256).Hash
$h3 = (Get-FileHash -LiteralPath $stage3 -Algorithm SHA256).Hash
$h4 = (Get-FileHash -LiteralPath $stage4 -Algorithm SHA256).Hash
if ($h2 -ne $h3 -or $h3 -ne $h4) {
    throw "next-generation fixed point not reached: $h2 != $h3 != $h4"
}
Write-Host "[flintc] next-generation fixed point: $h3"

Write-Host ("[flintc] {0} ({1} bytes)" -f $exe, (Get-Item -LiteralPath $exe).Length)
