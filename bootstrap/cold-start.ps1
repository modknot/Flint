# Cold start for a machine with no build/flintc.exe.
# This is the only path that assembles the seed and uses the PowerShell include
# expander. Normal builds and the bootstrap check use the current fixed-point
# compiler and never call the seed.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts\flint-source.ps1')

$build = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $build | Out-Null
$unit = Join-Path $build 'flintc.unit.fl'
$flint0 = Join-Path $build 'flint0.exe'
$stage1 = Join-Path $build 'flintc-cold-stage1.exe'

& pwsh -NoProfile -File (Join-Path $root 'bootstrap\build-flint0.ps1')
if ($LASTEXITCODE -ne 0) { throw "flint0 build failed ($LASTEXITCODE)" }

$expanded = Expand-FlintSource -Path (Join-Path $root 'src\flintc\flintc.fl')
[IO.File]::WriteAllLines($unit, $expanded, (New-Object System.Text.UTF8Encoding($false)))

Push-Location $root
try {
    & $flint0 $unit $stage1
    if ($LASTEXITCODE -ne 0) { throw "flint0 -> cold stage1 failed ($LASTEXITCODE)" }

    $cold2 = Join-Path $build 'flintc-cold-stage2.exe'
    Remove-Item $cold2 -Force -ErrorAction SilentlyContinue
    & $stage1
    if ($LASTEXITCODE -ne 0) { throw "cold stage1 self-compile failed ($LASTEXITCODE)" }
    Copy-Item (Join-Path $build 'flintc-out.exe') $cold2 -Force

    $src = Join-Path $root 'src\flintc\flintc.fl'
    $cold3 = Join-Path $build 'flintc-cold-stage3.exe'
    $cold4 = Join-Path $build 'flintc-cold-stage4.exe'
    Remove-Item $cold3, $cold4 -Force -ErrorAction SilentlyContinue
    & $cold2 $src $cold3
    if ($LASTEXITCODE -ne 0) { throw "cold stage2 built-in include compile failed ($LASTEXITCODE)" }
    & $cold3 $src $cold4
    if ($LASTEXITCODE -ne 0) { throw "cold stage3 built-in include compile failed ($LASTEXITCODE)" }

    $h2 = (Get-FileHash -LiteralPath $cold2 -Algorithm SHA256).Hash
    $h3 = (Get-FileHash -LiteralPath $cold3 -Algorithm SHA256).Hash
    $h4 = (Get-FileHash -LiteralPath $cold4 -Algorithm SHA256).Hash
    if ($h2 -ne $h3 -or $h3 -ne $h4) {
        throw "cold-start fixed point not reached: $h2 != $h3 != $h4"
    }
    Copy-Item $cold3 (Join-Path $build 'flintc.exe') -Force
    Write-Host "[cold-start] installed build/flintc.exe: $h3"
}
finally { Pop-Location }
