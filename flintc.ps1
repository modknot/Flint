# Command-line front end for the self-hosted compiler.
# Expands // include: directives, then invokes flintc with the input and output
# paths. flintc itself parses argc/argv at runtime; this script only performs
# the include expansion that the compiler does not do yet.
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
$elfOut = Join-Path $build 'flintc-elf'
$machoOut = Join-Path $build 'flintc-macho'

if (-not (Test-Path -LiteralPath $compiler)) {
    & pwsh -NoProfile -File (Join-Path $root 'build-flintc.ps1')
    if ($LASTEXITCODE -ne 0) { throw "flintc build failed ($LASTEXITCODE)" }
}

$expanded = Expand-FlintSource -Path $inputPath
[IO.File]::WriteAllLines($unit, $expanded, (New-Object System.Text.UTF8Encoding($false)))

Remove-Item $outputPath, $elfOut, $machoOut -Force -ErrorAction SilentlyContinue
& $compiler $unit $outputPath
if ($LASTEXITCODE -ne 0) { throw "flintc compile failed ($LASTEXITCODE)" }
if (-not (Test-Path -LiteralPath $outputPath)) { throw "flintc produced no PE output" }

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
