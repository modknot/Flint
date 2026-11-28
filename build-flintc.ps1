# Build flintc with the current fixed-point compiler.
# This script never invokes the assembly seed. On a machine without
# build/flintc.exe, run bootstrap/cold-start.ps1 once first.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$src = Join-Path $root 'src\flintc\flintc.fl'
$outDir = Join-Path $root 'build'
$compiler = Join-Path $outDir 'flintc.exe'

if (-not (Test-Path -LiteralPath $compiler)) {
    throw "build/flintc.exe is missing; run bootstrap/cold-start.ps1 once"
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$next1 = Join-Path $outDir 'flintc-next1.exe'
$next2 = Join-Path $outDir 'flintc-next2.exe'
Remove-Item $next1, $next2 -Force -ErrorAction SilentlyContinue

& $compiler $src $next1 | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $next1)) {
    throw "current compiler -> next compiler failed ($LASTEXITCODE)"
}

& $next1 $src $next2 | Out-Null
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $next2)) {
    throw "next compiler self-compile failed ($LASTEXITCODE)"
}

$h1 = (Get-FileHash -LiteralPath $next1 -Algorithm SHA256).Hash
$h2 = (Get-FileHash -LiteralPath $next2 -Algorithm SHA256).Hash
if ($h1 -ne $h2) { throw "next-generation fixed point not reached: $h1 != $h2" }

Copy-Item $next1 $compiler -Force
Write-Host "[flintc] next-generation fixed point: $h1"
Write-Host ("[flintc] {0} ({1} bytes)" -f $compiler, (Get-Item -LiteralPath $compiler).Length)
