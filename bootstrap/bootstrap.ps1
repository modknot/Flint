# End-to-end bootstrap check:
#   src/seed/*.asm + bootstrap/asm.ps1 -> flint0.exe
#   flint0.exe + src/flintc -> flintc-stage1.exe
#   flintc-stage1.exe compiles src/flintc -> flintc-stage2.exe
#   flintc-stage2.exe compiles src/flintc -> flintc-stage3.exe
#   stage2 and stage3 must be byte-identical (fixed point)
# No external compiler, assembler, Python, or checked-in executable is used.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts\flint-source.ps1')

$build = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $build | Out-Null
$unit = Join-Path $build 'flintc.unit.fl'
$flint0 = Join-Path $build 'flint0.exe'

if (-not (Test-Path -LiteralPath $flint0)) {
    & pwsh -NoProfile -File (Join-Path $root 'bootstrap\build-flint0.ps1')
    if ($LASTEXITCODE -ne 0) { throw "flint0 build failed" }
}

$expanded = Expand-FlintSource -Path (Join-Path $root 'src\flintc\flintc.fl')
[IO.File]::WriteAllLines($unit, $expanded, (New-Object System.Text.UTF8Encoding($false)))

Push-Location $root
try {
    & $flint0 $unit (Join-Path $build 'flintc-stage1.exe')
    if ($LASTEXITCODE -ne 0) { throw "flint0 -> stage1 failed ($LASTEXITCODE)" }

    $out = Join-Path $build 'flintc-out.exe'
    Remove-Item $out -Force -ErrorAction SilentlyContinue
    & (Join-Path $build 'flintc-stage1.exe')
    if ($LASTEXITCODE -ne 0) { throw "stage1 self-compile failed ($LASTEXITCODE)" }
    if (-not (Test-Path -LiteralPath $out)) { throw "stage1 produced no output" }
    Copy-Item $out (Join-Path $build 'flintc-stage2.exe') -Force

    Remove-Item $out -Force -ErrorAction SilentlyContinue
    & (Join-Path $build 'flintc-stage2.exe')
    if ($LASTEXITCODE -ne 0) { throw "stage2 self-compile failed ($LASTEXITCODE)" }
    if (-not (Test-Path -LiteralPath $out)) { throw "stage2 produced no output" }
    Copy-Item $out (Join-Path $build 'flintc-stage3.exe') -Force
}
finally { Pop-Location }

$a = (Get-FileHash (Join-Path $build 'flintc-stage2.exe') -Algorithm SHA256).Hash
$b = (Get-FileHash (Join-Path $build 'flintc-stage3.exe') -Algorithm SHA256).Hash
if ($a -ne $b) { throw "fixed point not reached: $a != $b" }
Write-Host "[bootstrap] fixed point OK: $a"
