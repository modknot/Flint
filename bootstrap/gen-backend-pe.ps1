# Generate src/flintc/backend_pe.fl from the fixed PE layout below.
# Keeping the byte table generated avoids hand-editing offsets when the runtime
# IAT moves.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$outFile = Join-Path $root 'src\flintc\backend_pe.fl'

$iatBase = 0x2F000       # section offset; file offset = +0x200
$iatCount = 9
$iltBase = $iatBase + 0x50
$descBase = $iatBase + 0xB0
$dllBase = $iatBase + 0x130
$hintBase = $iatBase + 0x170

$imports = @(
    @{ name='VirtualAlloc'; slot=0 },
    @{ name='VirtualFree';  slot=1 },
    @{ name='CreateFileA';  slot=2 },
    @{ name='ReadFile';     slot=3 },
    @{ name='WriteFile';    slot=4 },
    @{ name='CloseHandle';  slot=5 },
    @{ name='GetStdHandle'; slot=6 },
    @{ name='ExitProcess';  slot=7 },
    @{ name='GetCommandLineA'; slot=8 }
)

$hintOffsets = @()
$off = $hintBase
foreach ($im in $imports) {
    $hintOffsets += $off
    $size = 2 + $im.name.Length + 1
    if ($size % 2 -ne 0) { $size++ }
    $off += $size
}

$L = [System.Collections.Generic.List[string]]::new()
$L.Add('// ------------------------------ PE32+ 后端 ------------------------------')
$L.Add('// 输出节布局（括号内为文件偏移）：')
$L.Add('//   0x0000 运行库；0x02AD 生成代码入口；0x2F000（0x2F200）IAT')
$L.Add('//   0x2F050（0x2F250）ILT；0x2F0B0（0x2F2B0）导入描述符')
$L.Add('//   0x2F130（0x2F330）DLL 名；0x2F170（0x2F370）hint/name 表')
$L.Add('fn backend_pe(b: ^u8, code: ^u8, clen: i64, entry: i64) -> i64 {')
$L.Add('    zero_bytes(b, 0x30200);')
$L.Add('    put16(b, 0, 0x5A4D); put32(b, 0x3C, 0x40); put32(b, 0x40, 0x00004550);')
$L.Add('    put16(b, 0x44, 0x8664); put16(b, 0x46, 1); put16(b, 0x54, 0xF0); put16(b, 0x56, 0x0023);')
$L.Add('    put16(b, 0x58, 0x020B); put32(b, 0x5C, 0x30000); put32(b, 0x60, 0x30000); put32(b, 0x64, 0);')
$L.Add('    put32(b, 0x68, 0x1000 + entry); put32(b, 0x6C, 0x1000);')
$L.Add('    put64(b, 0x70, 0x140000000); put32(b, 0x78, 0x1000); put32(b, 0x7C, 0x200);')
$L.Add('    put16(b, 0x80, 6); put16(b, 0x88, 6); put32(b, 0x90, 0x31000); put32(b, 0x94, 0x200);')
$L.Add('    put16(b, 0x9C, 3); put64(b, 0xA0, 0x100000); put64(b, 0xA8, 0x1000);')
$L.Add('    put64(b, 0xB0, 0x100000); put64(b, 0xB8, 0x1000); put32(b, 0xC4, 16);')
$L.Add(('    put32(b, 0xD0, 0x{0:X}); put32(b, 0xD4, 40);' -f (0x1000 + $descBase)))
$L.Add('    put8(b, 0x148, 46); put8(b, 0x149, 116); put8(b, 0x14A, 101); put8(b, 0x14B, 120); put8(b, 0x14C, 116);')
$L.Add('    put32(b, 0x150, 0x30000); put32(b, 0x154, 0x1000); put32(b, 0x158, 0x30000); put32(b, 0x15C, 0x200);')
$L.Add('    put32(b, 0x16C, 0xE0000020);')
$L.Add('')
$L.Add('    copy_text(b, 0x200, code, clen);')
$L.Add('    let off: i64 = 0x200 + clen;')
$L.Add('    put8(b, off, 0x89); put8(b, off + 1, 0xC1);')
$L.Add('    put8(b, off + 2, 0xFF); put8(b, off + 3, 0x15); put32(b, off + 4, 0x2F030 - clen);')
$L.Add('    put8(b, off + 8, 0x31); put8(b, off + 9, 0xC0);')
$L.Add('')
$L.Add('    // IAT 与 ILT 各 8 项，末尾必须有一个 0 qword 终止。')
for ($i=0; $i -lt $iatCount; $i++) {
    $target = 0x1000 + $hintOffsets[$i]
    $L.Add(('    put64(b, 0x{0:X}, 0x{1:X});' -f (0x200 + $iatBase + $i*8), $target))
}
$L.Add(('    put64(b, 0x{0:X}, 0);' -f (0x200 + $iatBase + $iatCount*8)))
for ($i=0; $i -lt $iatCount; $i++) {
    $target = 0x1000 + $hintOffsets[$i]
    $L.Add(('    put64(b, 0x{0:X}, 0x{1:X});' -f (0x200 + $iltBase + $i*8), $target))
}
$L.Add(('    put64(b, 0x{0:X}, 0);' -f (0x200 + $iltBase + $iatCount*8)))
$L.Add('    // 导入描述符：OriginalFirstThunk、TimeDateStamp、ForwarderChain、Name、FirstThunk。')
$L.Add(('    put32(b, 0x{0:X}, 0x{1:X}); put32(b, 0x{2:X}, 0); put32(b, 0x{3:X}, 0);' -f (0x200+$descBase), (0x1000+$iltBase), (0x200+$descBase+4), (0x200+$descBase+8)))
$L.Add(('    put32(b, 0x{0:X}, 0x{1:X}); put32(b, 0x{2:X}, 0x{3:X});' -f (0x200+$descBase+0xC), (0x1000+$dllBase), (0x200+$descBase+0x10), (0x1000+$iatBase)))
$L.Add('    // 结束描述符为 20 字节零，已由 zero_bytes 保证。')
$L.Add('')
$L.Add('    // DLL 名。')
$dllPos = 0
foreach ($ch in [Text.Encoding]::ASCII.GetBytes('KERNEL32.dll')) {
    $L.Add(('    put8(b, 0x{0:X}, {1});' -f (0x200+$dllBase+$dllPos), $ch))
    $dllPos++
}
$L.Add(('    put8(b, 0x{0:X}, 0);' -f (0x200+$dllBase+$dllPos)))
$L.Add('')
$L.Add('    // hint/name：hint=0，随后是名字和 NUL。')
for ($i=0; $i -lt $imports.Count; $i++) {
    $im = $imports[$i]
    $base = 0x200 + $hintOffsets[$i]
    $L.Add(('    put8(b, 0x{0:X}, 0); put8(b, 0x{1:X}, 0);' -f $base, ($base+1)))
    $p = $base + 2
    foreach ($ch in [Text.Encoding]::ASCII.GetBytes($im.name)) {
        $L.Add(('    put8(b, 0x{0:X}, {1});' -f $p, $ch))
        $p++
    }
    $L.Add(('    put8(b, 0x{0:X}, 0);' -f $p))
}
$L.Add('')
$L.Add('    return 0x30200;')
$L.Add('}')

[IO.File]::WriteAllLines($outFile, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("generated {0} ({1} lines)" -f $outFile, $L.Count)
