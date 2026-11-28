# Command-line front end for the self-hosted compiler.
# The bootstrap compiler currently reads build\flintc.unit.fl and writes
# build\flintc-out.exe; this script maps a normal input/output command line
# onto that bootstrap interface. Native argc/argv inside flintc is still TODO.
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Position = 1)]
    [string]$OutputFile,

    [switch]$AllTargets
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
. (Join-Path $root 'scripts\flint-source.ps1')

$inputPath = (Resolve-Path -LiteralPath $InputFile).Path
if (-not $OutputFile) {
    $OutputFile = [IO.Path]::ChangeExtension($inputPath, '.exe')
}
$outputPath = [IO.Path]::GetFullPath($OutputFile)
$outputDir = [IO.Path]::GetDirectoryName($outputPath)
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

$build = Join-Path $root 'build'
$unit = Join-Path $build 'flintc.unit.fl'
$compiler = Join-Path $build 'flintc.exe'
$peOut = Join-Path $build 'flintc-out.exe'
$elfOut = Join-Path $build 'flintc-elf'
$machoOut = Join-Path $build 'flintc-macho'

if (-not (Test-Path -LiteralPath $compiler)) {
    & pwsh -NoProfile -File (Join-Path $root 'build-flintc.ps1')
    if ($LASTEXITCODE -ne 0) { throw "flintc build failed ($LASTEXITCODE)" }
}

$expanded = Expand-FlintSource -Path $inputPath
[IO.File]::WriteAllLines($unit, $expanded, (New-Object System.Text.UTF8Encoding($false)))

Remove-Item $peOut, $elfOut, $machoOut -Force -ErrorAction SilentlyContinue
& $compiler
if ($LASTEXITCODE -ne 0) { throw "flintc compile failed ($LASTEXITCODE)" }
if (-not (Test-Path -LiteralPath $peOut)) { throw "flintc produced no PE output" }

Copy-Item -LiteralPath $peOut -Destination $outputPath -Force
Write-Host ("[flintc] {0} -> {1}" -f $inputPath, $outputPath)

if ($AllTargets) {
    $base = [IO.Path]::GetFileNameWithoutExtension($outputPath)
    $dir = [IO.Path]::GetDirectoryName($outputPath)
    if (Test-Path -LiteralPath $elfOut) {
        Copy-Item -LiteralPath $elfOut -Destination (Join-Path $dir ($base + '.elf')) -Force
    }
    if (Test-Path -LiteralPath $machoOut) {
        Copy-Item -LiteralPath $machoOut -Destination (Join-Path $dir ($base + '.macho')) -Force
    }
}
