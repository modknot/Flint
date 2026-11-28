# End-to-end bootstrap check:
#   src/seed/*.asm + bootstrap/asm.ps1 -> flint0.exe
#   flint0.exe + expanded src/flintc -> flintc-stage1.exe
#   flintc-stage1.exe compiles the unit -> flintc-stage2.exe
#   flintc-stage2.exe compiles split src/flintc (built-in include) -> stage3
#   flintc-stage3.exe compiles split src/flintc -> stage4
#   stage2, stage3 and stage4 must be byte-identical (fixed point)
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

    $src = Join-Path $root 'src\flintc\flintc.fl'
    $stage3 = Join-Path $build 'flintc-stage3.exe'
    Remove-Item $stage3 -Force -ErrorAction SilentlyContinue
    & (Join-Path $build 'flintc-stage2.exe') $src $stage3
    if ($LASTEXITCODE -ne 0) { throw "stage2 built-in include compile failed ($LASTEXITCODE)" }
    if (-not (Test-Path -LiteralPath $stage3)) { throw "stage2 produced no output" }

    $stage4 = Join-Path $build 'flintc-stage4.exe'
    Remove-Item $stage4 -Force -ErrorAction SilentlyContinue
    & $stage3 $src $stage4
    if ($LASTEXITCODE -ne 0) { throw "stage3 built-in include compile failed ($LASTEXITCODE)" }
    if (-not (Test-Path -LiteralPath $stage4)) { throw "stage3 produced no output" }
}
finally { Pop-Location }

$a = (Get-FileHash (Join-Path $build 'flintc-stage2.exe') -Algorithm SHA256).Hash
$b = (Get-FileHash (Join-Path $build 'flintc-stage3.exe') -Algorithm SHA256).Hash
$c = (Get-FileHash (Join-Path $build 'flintc-stage4.exe') -Algorithm SHA256).Hash
if ($a -ne $b -or $b -ne $c) { throw "fixed point not reached: $a != $b != $c" }
Write-Host "[bootstrap] next-generation fixed point OK: $a"
