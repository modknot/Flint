# ===========================================================================
# Flint 阶段 0 构建脚本：两次汇编，NASM 直接产出 PE32+（不经过任何链接器）
#   Pass 1：跳过 PE 头，仅汇编节内容，量出节长度（末尾 align 0x200 已对齐）
#   Pass 2：以实测长度作为 SizeOfRawData / VirtualSize 写头，再产出 .exe
# ===========================================================================
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$src  = Join-Path $root 'src\seed'
$asm  = Join-Path $src  'seed.asm'
$out  = Join-Path $root 'build'
New-Item -ItemType Directory -Force -Path $out | Out-Null

$nasm = Join-Path $root 'tools\nasm-2.16.03\nasm.exe'
if (-not (Test-Path $nasm)) {
    $cmd = Get-Command nasm -ErrorAction SilentlyContinue
    if ($cmd) { $nasm = $cmd.Source } else { throw "nasm.exe 未找到（期望 tools\\nasm-2.16.03\\nasm.exe）" }
}

$measure = Join-Path $out 'measure.tmp'
$exe     = Join-Path $out 'flint-seed.exe'

Write-Host "[1/2] 量节长度 ..."
& $nasm -f bin -I "$src\" -DMEASURE_PASS -o $measure $asm
if ($LASTEXITCODE -ne 0) { throw "NASM pass1 失败 ($LASTEXITCODE)" }
$raw = (Get-Item $measure).Length
if ($raw % 0x200 -ne 0) { throw "节长度未按 0x200 对齐: $raw" }

Write-Host "[2/2] 汇编种子 PE (SizeOfRawData=0x$($raw.ToString('X'))) ..."
& $nasm -f bin -I "$src\" "-DSEC_RAW=$raw" -o $exe $asm
if ($LASTEXITCODE -ne 0) { throw "NASM pass2 失败 ($LASTEXITCODE)" }

$size = (Get-Item $exe).Length
Write-Host ("[ok] {0}  ({1} bytes)" -f $exe, $size)
