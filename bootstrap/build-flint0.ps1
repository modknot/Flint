# Build flint0 from the checked-in assembly seed.
# The seed is assembled twice by bootstrap/asm.ps1: the first pass measures the
# image so the second pass can lay out the section table at the right offset.
# No NASM, C compiler, or prebuilt executable is involved.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$seed = Join-Path $root 'src\seed\seed.asm'
$asm = Join-Path $PSScriptRoot 'asm.ps1'
$outDir = Join-Path $root 'build'
$measure = Join-Path $outDir 'flint0.measure.bin'
$exe = Join-Path $outDir 'flint0.exe'

if (-not (Test-Path -LiteralPath $seed)) { throw "missing assembly seed: $seed" }
if (-not (Test-Path -LiteralPath $asm)) { throw "missing assembler: $asm" }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

& pwsh -NoProfile -File $asm -Source $seed -Output $measure -Define MEASURE_PASS=1
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $measure)) {
    throw "measure pass failed ($LASTEXITCODE)"
}
$size = (Get-Item -LiteralPath $measure).Length

& pwsh -NoProfile -File $asm -Source $seed -Output $exe -Define "SEC_RAW=$size"
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $exe)) {
    throw "seed assembly failed ($LASTEXITCODE)"
}

Remove-Item -LiteralPath $measure -Force -ErrorAction SilentlyContinue
Write-Host ("[flint0] {0} ({1} bytes)" -f $exe, (Get-Item -LiteralPath $exe).Length)
