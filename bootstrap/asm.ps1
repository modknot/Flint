# ===========================================================================
# Flint 自带汇编器：把 src/seed 的汇编源码变成平铺 PE 镜像
# 只实现种子用到的 NASM 子集；不调用 NASM，不依赖任何 C 编译器。
# 用法：pwsh -NoProfile -File bootstrap\asm.ps1 -Source src\seed\seed.asm -Output build\flint0.bin [-Define SEC_RAW=...] [-Define MEASURE_PASS=1]
# ===========================================================================
$ErrorActionPreference = 'Stop'

$script:Reg64 = @{ rax=0; rcx=1; rdx=2; rbx=3; rsp=4; rbp=5; rsi=6; rdi=7; r8=8; r9=9; r10=10; r11=11; r12=12; r13=13; r14=14; r15=15 }
$script:Reg32 = @{ eax=0; ecx=1; edx=2; ebx=3; esp=4; ebp=5; esi=6; edi=7; r8d=8; r9d=9; r10d=10; r11d=11; r12d=12; r13d=13; r14d=14; r15d=15 }
$script:Reg16 = @{ ax=0; cx=1; dx=2; bx=3; sp=4; bp=5; si=6; di=7; r8w=8; r9w=9; r10w=10; r11w=11; r12w=12; r13w=13; r14w=14; r15w=15 }
$script:Reg8  = @{ al=0; cl=1; dl=2; bl=3; ah=4; ch=5; dh=6; bh=7; spl=4; bpl=5; sil=6; dil=7; r8b=8; r9b=9; r10b=10; r11b=11; r12b=12; r13b=13; r14b=14; r15b=15 }
$script:Low8 = @('spl','bpl','sil','dil')

function Get-RegInfo([string]$name) {
    $n = $name.ToLowerInvariant()
    foreach ($pair in @(@('64',$script:Reg64), @('32',$script:Reg32), @('16',$script:Reg16), @('8',$script:Reg8))) {
        $size = [int]$pair[0]; $table = $pair[1]
        if ($table.ContainsKey($n)) {
            return [pscustomobject]@{ Size=$size; Code=[int]$table[$n]; Name=$n }
        }
    }
    return $null
}

function Split-Args([string]$s) {
    $args = [System.Collections.Generic.List[string]]::new()
    $start = 0; $quote = [char]0; $depth = 0
    for ($i = 0; $i -lt $s.Length; $i++) {
        $ch = $s[$i]
        if ($quote -ne [char]0) {
            if ($ch -eq '\') { $i++; continue }
            if ($ch -eq $quote) { $quote = [char]0 }
            continue
        }
        if ($ch -eq '"' -or $ch -eq "'") { $quote = $ch; continue }
        if ($ch -eq '(' -or $ch -eq '[' -or $ch -eq '{') { $depth++; continue }
        if ($ch -eq ')' -or $ch -eq ']' -or $ch -eq '}') { $depth--; continue }
        if ($ch -eq ',' -and $depth -eq 0) {
            $args.Add($s.Substring($start, $i - $start).Trim())
            $start = $i + 1
        }
    }
    $args.Add($s.Substring($start).Trim())
    return $args
}

# ---------------------------------------------------------------------------
# 预处理：%include、%define、%ifndef/%ifdef/%else/%endif、MSG 宏
# ---------------------------------------------------------------------------
function Expand-Source([string]$path, [hashtable]$defines) {
    $base = Split-Path -Parent (Resolve-Path -LiteralPath $path)
    $raw = Get-Content -LiteralPath $path -Encoding UTF8
    $out = [System.Collections.Generic.List[string]]::new()
    $skipping = [System.Collections.Generic.List[bool]]::new()
    $inMacro = $false
    $i = 0
    while ($i -lt $raw.Count) {
        $line = $raw[$i]
        $stripped = $line.Trim()

        if ($inMacro) {
            if ($stripped -match '^%endmacro$') { $inMacro = $false }
            $i++; continue
        }

        if ($stripped -match '^%ifndef\s+(\w+)$') {
            $skipping.Add($defines.ContainsKey($Matches[1].ToLowerInvariant())); $i++; continue
        }
        if ($stripped -match '^%ifdef\s+(\w+)$') {
            $skipping.Add(-not $defines.ContainsKey($Matches[1].ToLowerInvariant())); $i++; continue
        }
        if ($stripped -match '^%else$') {
            if ($skipping.Count -eq 0) { throw '%else without %if' }
            $skipping[$skipping.Count-1] = -not $skipping[$skipping.Count-1]; $i++; continue
        }
        if ($stripped -match '^%endif$') {
            if ($skipping.Count -eq 0) { throw '%endif without %if' }
            $skipping.RemoveAt($skipping.Count-1); $i++; continue
        }
        $skip = $false
        foreach ($s in $skipping) { if ($s) { $skip = $true; break } }
        if ($skip) { $i++; continue }

        if ($stripped -match '^%include\s+"([^"]+)"$') {
            foreach ($x in (Expand-Source (Join-Path $base $Matches[1]) $defines)) { $out.Add($x) }
            $i++; continue
        }
        if ($stripped -match '^%define\s+(\w+)\s+(.+)$') {
            $defines[$Matches[1].ToLowerInvariant()] = $Matches[2].Split(';')[0].Trim()
            $i++; continue
        }
        if ($stripped -match '^%macro\s+(\w+)\s+(\d+)$') {
            $inMacro = $true; $i++; continue
        }
        if ($stripped -match '^(BITS|DEFAULT)\b') { $i++; continue }
        if ($stripped -match '^%(bits|default)\b') { $i++; continue }
        if ($stripped.StartsWith('%')) { throw "unsupported directive: $line" }

        # MSG label, "text" -> label / db text,0 / label_len equ ...
        if ($stripped -match '^MSG\s+([A-Za-z_][A-Za-z0-9_]*)\s*,\s*(".*")$') {
            $label = $Matches[1]; $text = $Matches[2]
            $out.Add("${label}:")
            $out.Add("    db $text, 0")
            $out.Add("${label}_len equ `$ - ${label} - 1")
            $i++; continue
        }

        $out.Add($line)
        $i++
    }
    return $out
}

# ---------------------------------------------------------------------------
# 表达式
# ---------------------------------------------------------------------------
$script:ExprToken = [regex]'\G\s*(0x[0-9A-Fa-f]+|\d+|\$\$|\$|[A-Za-z_.][A-Za-z0-9_.]*|[()+\-*/&|~^]|<<|>>)'

function Tokenize-Expr([string]$s) {
    $tokens = [System.Collections.Generic.List[string]]::new()
    $pos = 0
    while ($pos -lt $s.Length) {
        $m = $script:ExprToken.Match($s, $pos)
        if (-not $m.Success -or $m.Length -eq 0) { throw "bad expression [$s] near: $($s.Substring($pos))" }
        $tokens.Add($m.Groups[1].Value)
        $pos = $m.Index + $m.Length
    }
    return $tokens
}

function Eval-Expr([string]$s, [hashtable]$symbols, [int64]$current, [hashtable]$defines, [bool]$allowUnknown) {
    $tokens = @(Tokenize-Expr $s)
    $script:etPos = 0
    $script:etTokens = $tokens
    $script:etSymbols = $symbols
    $script:etDefines = $defines
    $script:etCurrent = $current
    $script:etUnknown = $allowUnknown

    function Take-Tok {
        if ($script:etPos -ge $script:etTokens.Count) { throw 'unexpected end of expression' }
        $t = $script:etTokens[$script:etPos]; $script:etPos++
        return $t
    }
    function Peek-Tok {
        if ($script:etPos -ge $script:etTokens.Count) { return $null }
        return $script:etTokens[$script:etPos]
    }
    function Parse-Primary {
        $t = Take-Tok
        if ($t -eq '(') { $v = Parse-Expr 0; if ((Take-Tok) -ne ')') { throw 'missing )' }; return $v }
        if ($t -eq '$') { return $script:etCurrent }
        if ($t -eq '$$') { return [int64]0 }
        if ($t -match '^0x') { return [Convert]::ToInt64($t.Substring(2),16) }
        if ($t -match '^\d+$') { return [int64]$t }
        $key = $t.ToLowerInvariant()
        if ($key.StartsWith('.') -and $script:asmScope) {
            $full = "$script:asmScope$key"
            if ($script:etSymbols.ContainsKey($full)) { return [int64]$script:etSymbols[$full] }
        }
        if ($script:etSymbols.ContainsKey($key)) { return [int64]$script:etSymbols[$key] }
        if ($script:etDefines.ContainsKey($key)) {
            $dv = $script:etDefines[$key]
            if ($dv -is [int64] -or $dv -is [int]) { return [int64]$dv }
            $sp=$script:etPos; $st=$script:etTokens; $ss=$script:etSymbols; $sd=$script:etDefines; $sc=$script:etCurrent; $su=$script:etUnknown
            $val = Eval-Expr ([string]$dv) $ss $sc $sd $su
            $script:etPos=$sp; $script:etTokens=$st; $script:etSymbols=$ss; $script:etDefines=$sd; $script:etCurrent=$sc; $script:etUnknown=$su
            return $val
        }
        if ($script:etUnknown) { return [int64]0 }
        throw "unknown symbol: $t"
    }
    function Parse-Unary {
        $t = Peek-Tok
        if ($t -eq '-') { Take-Tok | Out-Null; return - (Parse-Unary) }
        if ($t -eq '+') { Take-Tok | Out-Null; return Parse-Unary }
        if ($t -eq '~') { Take-Tok | Out-Null; return -bnot (Parse-Unary) }
        return Parse-Primary
    }
    function Parse-Expr([int]$minPrec) {
        $left = Parse-Unary
        $prec = @{ '|'=1; '^'=2; '&'=3; '<<'=4; '>>'=4; '+'=5; '-'=5; '*'=6; '/'=6 }
        while ($true) {
            $op = Peek-Tok
            if ($null -eq $op -or -not $prec.ContainsKey($op) -or $prec[$op] -lt $minPrec) { break }
            Take-Tok | Out-Null
            $right = Parse-Expr ($prec[$op] + 1)
            switch ($op) {
                '|' { $left = $left -bor $right }
                '^' { $left = $left -bxor $right }
                '&' { $left = $left -band $right }
                '<<' { $left = $left -shl $right }
                '>>' { $left = $left -shr $right }
                '+' { $left = $left + $right }
                '-' { $left = $left - $right }
                '*' { $left = $left * $right }
                '/' { if ($right -eq 0) { throw 'division by zero' }; $left = [int64]($left / $right) }
            }
        }
        return $left
    }

    $v = Parse-Expr 0
    if ($script:etPos -ne $tokens.Count) { throw "trailing tokens: [$($tokens[$script:etPos])] in [$s]" }
    return $v
}

# ---------------------------------------------------------------------------
# 操作数
# ---------------------------------------------------------------------------
function Parse-Mem([string]$s, $size) {
    $rip = $false
    if ($s -match '^rel\s+') { $rip = $true; $s = $s -replace '^rel\s+','' }
    $s = $s.Trim()
    $terms = [System.Collections.Generic.List[object]]::new()
    $sign = 1; $start = 0; $depth = 0
    for ($i = 0; $i -lt $s.Length; $i++) {
        $ch = $s[$i]
        if ($ch -eq '(' -or $ch -eq '[' -or $ch -eq '{') { $depth++ }
        elseif ($ch -eq ')' -or $ch -eq ']' -or $ch -eq '}') { $depth-- }
        elseif ($depth -eq 0 -and ($ch -eq '+' -or $ch -eq '-')) {
            $signNext = 1
            if ($ch -eq '-') { $signNext = -1 }
            $terms.Add(@{ Sign=$sign; Text=$s.Substring($start,$i-$start).Trim() })
            $sign = $signNext
            $start = $i + 1
        }
    }
    $terms.Add(@{ Sign=$sign; Text=$s.Substring($start).Trim() })
    $base = $null; $index = $null; $scale = 1; $dispParts = [System.Collections.Generic.List[string]]::new()
    foreach ($t in $terms) {
        $text = $t.Text; if (-not $text) { continue }
        if ($text -match '^([A-Za-z][A-Za-z0-9]*)\s*\*\s*(\d+)$' -and (Get-RegInfo $Matches[1])) {
            $index = $Matches[1]; $scale = [int]$Matches[2]; continue
        }
        if (Get-RegInfo $text) {
            if ($null -eq $base) { $base = $text }
            elseif ($null -eq $index) { $index = $text }
            else { throw "too many registers in memory operand: $s" }
            continue
        }
        $signed = "+$text"
        if ($t.Sign -lt 0) { $signed = "-$text" }
        $dispParts.Add($signed)
    }
    $disp = '0'
    if ($dispParts.Count -gt 0) { $disp = ($dispParts -join '') }
    return [pscustomobject]@{ Base=$base; Index=$index; Scale=$scale; Disp=$disp; Rip=$rip; Size=$size }
}

function Parse-Operand([string]$s) {
    $s = $s.Trim()
    $size = $null
    if ($s -match '^(byte|word|dword|qword)\s+(.*)$') {
        $unit = $Matches[1].ToLowerInvariant()
        $size = 0
        if ($unit -eq 'byte') { $size = 8 }
        elseif ($unit -eq 'word') { $size = 16 }
        elseif ($unit -eq 'dword') { $size = 32 }
        else { $size = 64 }
        $s = $Matches[2].Trim()
    }
    if ($s -match '^strict\s+(.*)$') { $s = $Matches[1].Trim() }
    if ($s.StartsWith('[') -and $s.EndsWith(']')) {
        return [pscustomobject]@{ Kind='mem'; Mem=(Parse-Mem $s.Substring(1,$s.Length-2) $size); Size=$size }
    }
    $ri = Get-RegInfo $s
    if ($ri) { return [pscustomobject]@{ Kind='reg'; Reg=$ri; Size=$size } }
    if ($s -match "^'([^']*)'$") {
        $body = $Matches[1]
        if ($body.StartsWith('\')) {
            $esc = @{ 'n'=10; 'r'=13; 't'=9; '0'=0; '\'=92; "'"=39; '"'=34 }
            $ch = $body.Substring(1,1)
            $v = [int][char]$ch
            if ($esc.ContainsKey($ch)) { $v = $esc[$ch] }
            return [pscustomobject]@{ Kind='imm'; Value=[int64]$v; Size=$size }
        }
        if ($body.Length -ne 1) { throw "bad character literal: $s" }
        return [pscustomobject]@{ Kind='imm'; Value=[int64][int][char]$body; Size=$size }
    }
    return [pscustomobject]@{ Kind='imm'; Value=$s; Size=$size }
}

# ---------------------------------------------------------------------------
# 编码辅助
# ---------------------------------------------------------------------------
function New-Buf { return ,([System.Collections.Generic.List[byte]]::new()) }
function Add-B([System.Collections.Generic.List[byte]]$b, [int]$v) { $b.Add([byte]($v -band 0xFF)) }
function Add-Dword([System.Collections.Generic.List[byte]]$b, [int64]$v) {
    for ($i=0; $i -lt 4; $i++) { $b.Add([byte](($v -shr (8*$i)) -band 0xFF)) }
}
function Add-Qword([System.Collections.Generic.List[byte]]$b, [int64]$v) {
    for ($i=0; $i -lt 8; $i++) { $b.Add([byte](($v -shr (8*$i)) -band 0xFF)) }
}
function Add-ImmSized([System.Collections.Generic.List[byte]]$b, [int64]$v, [int]$sz) {
    if ($sz -eq 8) { Add-B $b $v }
    elseif ($sz -eq 16) { Add-B $b $v; Add-B $b ($v -shr 8) }
    else { Add-Dword $b $v }
}
function Strip-Comment([string]$line) {
    $quote = [char]0
    for ($i=0; $i -lt $line.Length; $i++) {
        $ch = $line[$i]
        if ($quote -ne [char]0) {
            if ($ch -eq '\') { $i++; continue }
            if ($ch -eq $quote) { $quote = [char]0 }
            continue
        }
        if ($ch -eq '"' -or $ch -eq "'") { $quote = $ch; continue }
        if ($ch -eq ';') { return $line.Substring(0,$i) }
    }
    return $line
}

function Get-AsmStringBytes([string]$txt) {
    $b = New-Buf
    $i = 0
    while ($i -lt $txt.Length) {
        $ch = $txt[$i]
        if ($ch -eq '\' -and $i + 1 -lt $txt.Length) {
            $e = $txt[$i+1]
            $v = [int][char]$e
            if ($e -eq 'n') { $v = 10 }
            elseif ($e -eq 'r') { $v = 13 }
            elseif ($e -eq 't') { $v = 9 }
            elseif ($e -eq '0') { $v = 0 }
            elseif ($e -eq '\') { $v = 92 }
            elseif ($e -eq "'") { $v = 39 }
            elseif ($e -eq '"') { $v = 34 }
            $b.Add([byte]$v); $i += 2
        } else {
            foreach ($bt in [Text.Encoding]::UTF8.GetBytes([string]$ch)) { $b.Add($bt) }
            $i++
        }
    }
    return $b
}

function Get-Rex([int]$w, [int]$reg, [int]$index=0, [int]$base=0, [bool]$force=$false) {
    return 0x40 -bor (($w -band 1) -shl 3) -bor ((($reg -shr 3) -band 1) -shl 2) -bor ((($index -shr 3) -band 1) -shl 1) -bor (($base -shr 3) -band 1)
}
function Get-ModRM([int]$mod, [int]$reg, [int]$rm) { return (($mod -band 3) -shl 6) -bor (($reg -band 7) -shl 3) -bor ($rm -band 7) }
function Get-SIB([int]$scale, [int]$index, [int]$base) {
    $sb = 0
    if ($scale -eq 2) { $sb = 1 }
    elseif ($scale -eq 4) { $sb = 2 }
    elseif ($scale -eq 8) { $sb = 3 }
    elseif ($scale -ne 1) { throw "bad scale $scale" }
    return ($sb -shl 6) -bor (($index -band 7) -shl 3) -bor ($base -band 7)
}

function Get-MemRexBits($mem) {
    $indexCode = 0; $baseCode = 0
    if ($mem.Index) { $indexCode = (Get-RegInfo $mem.Index).Code }
    if ($mem.Base) { $baseCode = (Get-RegInfo $mem.Base).Code }
    return @{ Index=$indexCode; Base=$baseCode }
}

function Encode-Mem($mem, [int]$regField, [int]$w) {
    $b = New-Buf; $fx = [System.Collections.Generic.List[object]]::new()
    if ($mem.Rip) {
        Add-B $b (Get-ModRM 0 $regField 5)
        $fx.Add(@{ Offset=$b.Count; Expr=$mem.Disp; Kind='rip32'; Scope=$script:asmScope })
        Add-Dword $b 0
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }
    $baseCode = $null; $indexCode = $null
    if ($mem.Base) { $baseCode = (Get-RegInfo $mem.Base).Code }
    if ($mem.Index) { $indexCode = (Get-RegInfo $mem.Index).Code }
    if ($null -eq $baseCode -and $null -eq $indexCode) {
        Add-B $b (Get-ModRM 0 $regField 4); Add-B $b (Get-SIB 1 4 5)
        $fx.Add(@{ Offset=$b.Count; Expr=$mem.Disp; Kind='abs32'; Scope=$script:asmScope }); Add-Dword $b 0
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }
    if ($null -ne $indexCode) {
        Add-B $b (Get-ModRM 2 $regField 4)
        Add-B $b (Get-SIB $mem.Scale $indexCode $(if ($null -ne $baseCode) {$baseCode} else {5}))
        $fx.Add(@{ Offset=$b.Count; Expr=$mem.Disp; Kind='abs32'; Scope=$script:asmScope }); Add-Dword $b 0
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }
    if ($baseCode -eq 4 -or $baseCode -eq 12) {
        Add-B $b (Get-ModRM 2 $regField 4); Add-B $b (Get-SIB 1 4 $baseCode)
    } else {
        Add-B $b (Get-ModRM 2 $regField $baseCode)
    }
    $fx.Add(@{ Offset=$b.Count; Expr=$mem.Disp; Kind='abs32'; Scope=$script:asmScope }); Add-Dword $b 0
    return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
}

function Get-ImmValue($op, [hashtable]$symbols, [int64]$pc, [hashtable]$defines, [bool]$resolve) {
    if ($op.Kind -ne 'imm') { throw 'expected immediate' }
    if ($op.Value -is [int64] -or $op.Value -is [int]) { return [int64]$op.Value }
    return Eval-Expr ([string]$op.Value) $symbols $pc $defines (-not $resolve)
}

$script:ALU = @{ add=@(0x01,0x03,0x00,0x81); or=@(0x09,0x0B,0x01,0x81); and=@(0x21,0x23,0x04,0x81); sub=@(0x29,0x2B,0x05,0x81); xor=@(0x31,0x33,0x06,0x81); cmp=@(0x39,0x3B,0x07,0x81) }
$script:JCC = @{ ja=0x87; jae=0x83; jb=0x82; jbe=0x86; je=0x84; jne=0x85; jg=0x8F; jge=0x8D; jl=0x8C; jle=0x8E; jns=0x89; jz=0x84; jnz=0x85; js=0x88 }

function Encode-Instruction([string]$mn, $ops, [int64]$addr, [hashtable]$symbols, [hashtable]$defines, [bool]$resolve) {
    $mn = $mn.ToLowerInvariant()
    $b = New-Buf; $fx = [System.Collections.Generic.List[object]]::new()
    function AddFx([int]$off, [string]$expr, [string]$kind) { $fx.Add(@{ Offset=$off; Expr=$expr; Kind=$kind; Scope=$script:asmScope }) }

    if ($mn -eq 'mov') {
        $dst = $ops[0]; $src = $ops[1]
        if ($dst.Kind -eq 'reg' -and $src.Kind -eq 'imm') {
            $sz=$dst.Reg.Size; $code=$dst.Reg.Code; $name=$dst.Reg.Name; $val=(Get-ImmValue $src $symbols $addr $defines $resolve)
            if ($sz -eq 64) { Add-B $b (Get-Rex 1 0 0 $code); Add-B $b (0xB8 + ($code -band 7)); if($resolve){Add-Qword $b $val}else{Add-Qword $b 0} }
            elseif ($sz -eq 32) { if ($code -ge 8) { Add-B $b (Get-Rex 0 0 0 $code) }; Add-B $b (0xB8 + ($code -band 7)); if($resolve){Add-Dword $b $val}else{Add-Dword $b 0} }
            elseif ($sz -eq 16) { if ($code -ge 8) { Add-B $b (Get-Rex 0 0 0 $code) }; Add-B $b 0x66; Add-B $b (0xB8 + ($code -band 7)); Add-B $b ($val -band 0xFF); Add-B $b (($val -shr 8) -band 0xFF) }
            elseif ($sz -eq 8) { if($script:Low8.Contains($name) -or $code -ge 8){Add-B $b (Get-Rex 0 0 0 $code $true)}; Add-B $b (0xB0 + ($code -band 7)); Add-B $b $val }
            else { throw 'bad mov size' }
        }
        elseif ($dst.Kind -eq 'reg' -and $src.Kind -eq 'reg') {
            $ds=$dst.Reg.Size; $dc=$dst.Reg.Code; $dn=$dst.Reg.Name; $ss=$src.Reg.Size; $sc=$src.Reg.Code; $sn=$src.Reg.Name
            if ($ds -ne $ss) { throw "mov size mismatch: $dn <- $sn" }
            $w = 0; if ($ds -eq 64) { $w = 1 }; $force = $script:Low8.Contains($dn) -or $script:Low8.Contains($sn)
            if ($w -or $force -or $sc -ge 8 -or $dc -ge 8) { Add-B $b (Get-Rex $w $sc 0 $dc $force) }
            Add-B $b 0x89; Add-B $b (Get-ModRM 3 $sc $dc)
        }
        elseif ($dst.Kind -eq 'mem' -and $src.Kind -eq 'reg') {
            $ss=$src.Reg.Size; $sc=$src.Reg.Code; $sn=$src.Reg.Name
            $w = 0; if ($ss -eq 64) { $w = 1 }; $force=$script:Low8.Contains($sn)
            $mr = Get-MemRexBits $dst.Mem
            if ($ss -eq 16) { Add-B $b 0x66 }
            if ($w -or $force -or $sc -ge 8 -or $mr.Index -ge 8 -or $mr.Base -ge 8) { Add-B $b (Get-Rex $w $sc $mr.Index $mr.Base $force) }
            $opc = 0x89
            if ($ss -eq 8) { $opc = 0x88 }
            Add-B $b $opc
            $m = Encode-Mem $dst.Mem $sc $w; $off=$b.Count
            foreach($x in $m.Bytes){$b.Add($x)}
            foreach($f in $m.Fixups){ AddFx ($off+$f.Offset) $f.Expr $f.Kind }
        }
        elseif ($dst.Kind -eq 'reg' -and $src.Kind -eq 'mem') {
            $ds=$dst.Reg.Size; $dc=$dst.Reg.Code; $dn=$dst.Reg.Name
            $w = 0; if ($ds -eq 64) { $w = 1 }; $force=$script:Low8.Contains($dn)
            $mr = Get-MemRexBits $src.Mem
            if ($ds -eq 16) { Add-B $b 0x66 }
            if ($w -or $force -or $dc -ge 8 -or $mr.Index -ge 8 -or $mr.Base -ge 8) { Add-B $b (Get-Rex $w $dc $mr.Index $mr.Base $force) }
            $opc = 0x8B
            if ($ds -eq 8) { $opc = 0x8A }
            Add-B $b $opc
            $m = Encode-Mem $src.Mem $dc $w; $off=$b.Count
            foreach($x in $m.Bytes){$b.Add($x)}
            foreach($f in $m.Fixups){ AddFx ($off+$f.Offset) $f.Expr $f.Kind }
        }
        elseif ($dst.Kind -eq 'mem' -and $src.Kind -eq 'imm') {
            $sz = 32
            if ($null -ne $dst.Size) { $sz = $dst.Size }
            elseif ($null -ne $src.Size) { $sz = $src.Size }
            $val=(Get-ImmValue $src $symbols $addr $defines $resolve)
            $mr = Get-MemRexBits $dst.Mem
            $w = 0; if ($sz -eq 64) { $w = 1 }
            if ($sz -eq 16) { Add-B $b 0x66 }
            if ($w -or $mr.Index -ge 8 -or $mr.Base -ge 8) { Add-B $b (Get-Rex $w 0 $mr.Index $mr.Base) }
            if ($sz -eq 64) { Add-B $b 0xC7; $m=Encode-Mem $dst.Mem 0 1; $off=$b.Count; foreach($x in $m.Bytes){$b.Add($x)}; foreach($f in $m.Fixups){AddFx ($off+$f.Offset) $f.Expr $f.Kind}; Add-Dword $b $val }
            elseif ($sz -eq 32) { Add-B $b 0xC7; $m=Encode-Mem $dst.Mem 0 0; $off=$b.Count; foreach($x in $m.Bytes){$b.Add($x)}; foreach($f in $m.Fixups){AddFx ($off+$f.Offset) $f.Expr $f.Kind}; Add-Dword $b $val }
            elseif ($sz -eq 16) { Add-B $b 0xC7; $m=Encode-Mem $dst.Mem 0 0; $off=$b.Count; foreach($x in $m.Bytes){$b.Add($x)}; foreach($f in $m.Fixups){AddFx ($off+$f.Offset) $f.Expr $f.Kind}; Add-B $b $val; Add-B $b ($val -shr 8) }
            elseif ($sz -eq 8) { Add-B $b 0xC6; $m=Encode-Mem $dst.Mem 0 0; $off=$b.Count; foreach($x in $m.Bytes){$b.Add($x)}; foreach($f in $m.Fixups){AddFx ($off+$f.Offset) $f.Expr $f.Kind}; Add-B $b $val }
            else { throw 'bad mov mem size' }
        }
        else { throw "unsupported mov operands: $($dst.Kind), $($src.Kind)" }
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }

    if ($mn -eq 'lea') {
        $dst=$ops[0]; $src=$ops[1]; $ds=$dst.Reg.Size; $dc=$dst.Reg.Code
        if ($src.Kind -ne 'mem') { throw 'lea needs memory' }
        $w = 0; if ($ds -eq 64) { $w = 1 }
        $mr = Get-MemRexBits $src.Mem
        if ($w -or $dc -ge 8 -or $mr.Index -ge 8 -or $mr.Base -ge 8) { Add-B $b (Get-Rex $w $dc $mr.Index $mr.Base) }
        Add-B $b 0x8D
        $m=Encode-Mem $src.Mem $dc $w; $off=$b.Count; foreach($x in $m.Bytes){$b.Add($x)}; foreach($f in $m.Fixups){AddFx ($off+$f.Offset) $f.Expr $f.Kind}
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }

    if ($mn -eq 'movzx' -or $mn -eq 'movsxd') {
        $dst=$ops[0]; $src=$ops[1]; $ds=$dst.Reg.Size; $dc=$dst.Reg.Code
        $ss = $src.Size
        if ($src.Kind -eq 'reg') { $ss = $src.Reg.Size }
        if ($mn -eq 'movzx') {
            if ($ss -eq 8) { $op=0xB6 } elseif ($ss -eq 16) { $op=0xB7 } else { throw 'movzx source size' }
            $w = 0; if ($ds -eq 64) { $w = 1 }
            $srcCode = 0; $idxCode = 0; $baseCode = 0
            if ($src.Kind -eq 'reg') { $srcCode = $src.Reg.Code }
            elseif ($src.Kind -eq 'mem') { $mr = Get-MemRexBits $src.Mem; $idxCode=$mr.Index; $baseCode=$mr.Base }
            if ($w -or $dc -ge 8 -or $srcCode -ge 8 -or $idxCode -ge 8 -or $baseCode -ge 8) { Add-B $b (Get-Rex $w $dc $idxCode $baseCode) }
            Add-B $b 0x0F; Add-B $b $op
        } else {
            if ($ss -ne 32 -and $null -ne $ss) { throw 'movsxd source size' }
            Add-B $b (Get-Rex 1 $dc); Add-B $b 0x63
        }
        if ($src.Kind -eq 'reg') { Add-B $b (Get-ModRM 3 $dc $src.Reg.Code) }
        else { $m=Encode-Mem $src.Mem $dc 1; $off=$b.Count; foreach($x in $m.Bytes){$b.Add($x)}; foreach($f in $m.Fixups){AddFx ($off+$f.Offset) $f.Expr $f.Kind} }
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }

    if ($script:ALU.ContainsKey($mn)) {
        $a=$script:ALU[$mn]; $dst=$ops[0]; $src=$ops[1]
        if ($dst.Kind -eq 'reg' -and $src.Kind -eq 'reg') {
            $ds=$dst.Reg.Size; $dc=$dst.Reg.Code; $dn=$dst.Reg.Name; $sc=$src.Reg.Code; $sn=$src.Reg.Name
            $w = 0; if ($ds -eq 64) { $w = 1 }; $force=$script:Low8.Contains($dn) -or $script:Low8.Contains($sn)
            if ($w -or $force -or $sc -ge 8 -or $dc -ge 8) { Add-B $b (Get-Rex $w $sc 0 $dc $force) }
            Add-B $b $a[0]; Add-B $b (Get-ModRM 3 $sc $dc)
        }
        elseif ($dst.Kind -eq 'mem' -and $src.Kind -eq 'reg') {
            $ss=$src.Reg.Size; $sc=$src.Reg.Code; $sn=$src.Reg.Name
            $w = 0; if ($ss -eq 64) { $w = 1 }; $force=$script:Low8.Contains($sn)
            $mr = Get-MemRexBits $dst.Mem
            if ($ss -eq 16) { Add-B $b 0x66 }
            if ($w -or $force -or $sc -ge 8 -or $mr.Index -ge 8 -or $mr.Base -ge 8) { Add-B $b (Get-Rex $w $sc $mr.Index $mr.Base $force) }
            $opc = $a[0]
            if ($ss -eq 8) { $opc = $a[0] - 1 }
            Add-B $b $opc
            $m=Encode-Mem $dst.Mem $sc $w; $off=$b.Count; foreach($x in $m.Bytes){$b.Add($x)}; foreach($f in $m.Fixups){AddFx ($off+$f.Offset) $f.Expr $f.Kind}
        }
        elseif ($dst.Kind -eq 'reg' -and $src.Kind -eq 'mem') {
            $ds=$dst.Reg.Size; $dc=$dst.Reg.Code; $dn=$dst.Reg.Name
            $w = 0; if ($ds -eq 64) { $w = 1 }; $force=$script:Low8.Contains($dn)
            $mr = Get-MemRexBits $src.Mem
            if ($ds -eq 16) { Add-B $b 0x66 }
            if ($w -or $force -or $dc -ge 8 -or $mr.Index -ge 8 -or $mr.Base -ge 8) { Add-B $b (Get-Rex $w $dc $mr.Index $mr.Base $force) }
            $opc = $a[1]
            if ($ds -eq 8) { $opc = $a[1] - 1 }
            Add-B $b $opc
            $m=Encode-Mem $src.Mem $dc $w; $off=$b.Count; foreach($x in $m.Bytes){$b.Add($x)}; foreach($f in $m.Fixups){AddFx ($off+$f.Offset) $f.Expr $f.Kind}
        }
        elseif (($dst.Kind -eq 'reg' -or $dst.Kind -eq 'mem') -and $src.Kind -eq 'imm') {
            $sz = 32
            if ($dst.Kind -eq 'reg') { $sz = $dst.Reg.Size } elseif ($null -ne $dst.Size) { $sz = $dst.Size }
            if ($sz -eq 16) { Add-B $b 0x66 }
            if ($dst.Kind -eq 'reg') {
                $dc=$dst.Reg.Code; $dn=$dst.Reg.Name
                $w = 0; if ($sz -eq 64) { $w = 1 }; $force=$script:Low8.Contains($dn)
                if ($w -or $force -or $dc -ge 8) { Add-B $b (Get-Rex $w 0 0 $dc $force) }
                $opc = $a[3]
                if ($sz -eq 8) { $opc = 0x80 }
                Add-B $b $opc; Add-B $b (Get-ModRM 3 $a[2] $dc)
            } else {
                $w = 0; if ($sz -eq 64) { $w = 1 }
                $mr = Get-MemRexBits $dst.Mem
                if ($w -or $mr.Index -ge 8 -or $mr.Base -ge 8) { Add-B $b (Get-Rex $w 0 $mr.Index $mr.Base) }
                $opc = 0x81
                if ($sz -eq 8) { $opc = 0x80 }
                Add-B $b $opc
                $m=Encode-Mem $dst.Mem $a[2] $w; $off=$b.Count; foreach($x in $m.Bytes){$b.Add($x)}; foreach($f in $m.Fixups){AddFx ($off+$f.Offset) $f.Expr $f.Kind}
            }
            Add-ImmSized $b (Get-ImmValue $src $symbols $addr $defines $resolve) $sz
        } else { throw "unsupported $mn operands" }
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }

    if ($mn -eq 'test') {
        $dst=$ops[0]; $src=$ops[1]
        if ($dst.Kind -eq 'reg' -and $src.Kind -eq 'reg') {
            $ds=$dst.Reg.Size; $dc=$dst.Reg.Code; $dn=$dst.Reg.Name; $sc=$src.Reg.Code; $sn=$src.Reg.Name
            $w = 0; if ($ds -eq 64) { $w = 1 }; $force=$script:Low8.Contains($dn) -or $script:Low8.Contains($sn)
            if ($w -or $force -or $sc -ge 8 -or $dc -ge 8) { Add-B $b (Get-Rex $w $sc 0 $dc $force) }
            Add-B $b 0x85; Add-B $b (Get-ModRM 3 $sc $dc)
        } elseif (($dst.Kind -eq 'reg' -or $dst.Kind -eq 'mem') -and $src.Kind -eq 'imm') {
            $sz = 32
            if ($dst.Kind -eq 'reg') { $sz = $dst.Reg.Size } elseif ($null -ne $dst.Size) { $sz = $dst.Size }
            if ($sz -eq 16) { Add-B $b 0x66 }
            if ($dst.Kind -eq 'reg') {
                $dc=$dst.Reg.Code
                if ($sz -eq 64) { Add-B $b (Get-Rex 1 0) }
                $opc = 0xF7
                if ($sz -eq 8) { $opc = 0xF6 }
                Add-B $b $opc; Add-B $b (Get-ModRM 3 0 $dc)
            } else {
                $w = 0; if ($sz -eq 64) { $w = 1 }
                if ($w) { Add-B $b (Get-Rex 1 0) }
                $opc = 0xF7
                if ($sz -eq 8) { $opc = 0xF6 }
                Add-B $b $opc
                $m=Encode-Mem $dst.Mem 0 $w; $off=$b.Count; foreach($x in $m.Bytes){$b.Add($x)}; foreach($f in $m.Fixups){AddFx ($off+$f.Offset) $f.Expr $f.Kind}
            }
            Add-ImmSized $b (Get-ImmValue $src $symbols $addr $defines $resolve) $sz
        } else { throw 'unsupported test operands' }
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }

    if ($mn -eq 'inc' -or $mn -eq 'dec') {
        $dst=$ops[0]; $digit = 1; if ($mn -eq 'inc') { $digit = 0 }
        if ($dst.Kind -eq 'reg') {
            $ds=$dst.Reg.Size; $dc=$dst.Reg.Code; $dn=$dst.Reg.Name
            $w = 0; if ($ds -eq 64) { $w = 1 }; $force=$script:Low8.Contains($dn)
            if ($w -or $force -or $dc -ge 8) { Add-B $b (Get-Rex $w 0 0 $dc $force) }
            $opc = 0xFF
            if ($ds -eq 8) { $opc = 0xFE }
            Add-B $b $opc; Add-B $b (Get-ModRM 3 $digit $dc)
        } elseif ($dst.Kind -eq 'mem') {
            $sz = 32; if ($null -ne $dst.Size) { $sz = $dst.Size }
            if ($sz -eq 16) { Add-B $b 0x66 }
            $w = 0; if ($sz -eq 64) { $w = 1 }
            if ($w) { Add-B $b (Get-Rex 1 0) }
            $opc = 0xFF
            if ($sz -eq 8) { $opc = 0xFE }
            Add-B $b $opc
            $m=Encode-Mem $dst.Mem $digit $w; $off=$b.Count; foreach($x in $m.Bytes){$b.Add($x)}; foreach($f in $m.Fixups){AddFx ($off+$f.Offset) $f.Expr $f.Kind}
        } else { throw "$mn needs reg/mem" }
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }

    if ($mn -eq 'neg' -or $mn -eq 'div') {
        $dst=$ops[0]; $digit = 6; if ($mn -eq 'neg') { $digit = 3 }
        if ($dst.Kind -eq 'reg') {
            $ds=$dst.Reg.Size; $dc=$dst.Reg.Code; $dn=$dst.Reg.Name
            $w = 0; if ($ds -eq 64) { $w = 1 }; $force=$script:Low8.Contains($dn)
            if ($w -or $force -or $dc -ge 8) { Add-B $b (Get-Rex $w 0 0 $dc $force) }
            $opc = 0xF7
            if ($ds -eq 8) { $opc = 0xF6 }
            Add-B $b $opc; Add-B $b (Get-ModRM 3 $digit $dc)
        } elseif ($dst.Kind -eq 'mem') {
            $sz = 32; if ($null -ne $dst.Size) { $sz = $dst.Size }
            if ($sz -eq 16) { Add-B $b 0x66 }
            $w = 0; if ($sz -eq 64) { $w = 1 }
            if ($w) { Add-B $b (Get-Rex 1 0) }
            $opc = 0xF7
            if ($sz -eq 8) { $opc = 0xF6 }
            Add-B $b $opc
            $m=Encode-Mem $dst.Mem $digit $w; $off=$b.Count; foreach($x in $m.Bytes){$b.Add($x)}; foreach($f in $m.Fixups){AddFx ($off+$f.Offset) $f.Expr $f.Kind}
        } else { throw "$mn needs reg/mem" }
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }

    if ($mn -eq 'imul') {
        if ($ops.Count -eq 2) {
            $dst=$ops[0]; $src=$ops[1]; $ds=$dst.Reg.Size; $dc=$dst.Reg.Code
            $w = 0; if ($ds -eq 64) { $w = 1 }
            if ($w) { Add-B $b (Get-Rex 1 $dc) }
            Add-B $b 0x0F; Add-B $b 0xAF
            if ($src.Kind -eq 'reg') { Add-B $b (Get-ModRM 3 $dc $src.Reg.Code) }
            else { $m=Encode-Mem $src.Mem $dc $w; $off=$b.Count; foreach($x in $m.Bytes){$b.Add($x)}; foreach($f in $m.Fixups){AddFx ($off+$f.Offset) $f.Expr $f.Kind} }
        } else {
            $dst=$ops[0]; $src=$ops[1]; $imm=$ops[2]; $ds=$dst.Reg.Size; $dc=$dst.Reg.Code
            $w = 0; if ($ds -eq 64) { $w = 1 }
            if ($w) { Add-B $b (Get-Rex 1 $dc) }
            Add-B $b 0x69
            if ($src.Kind -eq 'reg') { Add-B $b (Get-ModRM 3 $dc $src.Reg.Code) }
            else { $m=Encode-Mem $src.Mem $dc $w; $off=$b.Count; foreach($x in $m.Bytes){$b.Add($x)}; foreach($f in $m.Fixups){AddFx ($off+$f.Offset) $f.Expr $f.Kind} }
            Add-Dword $b (Get-ImmValue $imm $symbols $addr $defines $resolve)
        }
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }

    if ($mn -eq 'shl' -or $mn -eq 'shr') {
        $dst=$ops[0]; $src=$ops[1]; $digit = 5; if ($mn -eq 'shl') { $digit = 4 }
        if ($dst.Kind -ne 'reg') { throw 'shl/shr needs reg' }
        $ds=$dst.Reg.Size; $dc=$dst.Reg.Code
        $w = 0; if ($ds -eq 64) { $w = 1 }
        if ($src.Kind -eq 'reg' -and $src.Reg.Name -eq 'cl') {
            if ($w) { Add-B $b (Get-Rex 1 0) }
            Add-B $b 0xD3; Add-B $b (Get-ModRM 3 $digit $dc)
        } else {
            if ($w) { Add-B $b (Get-Rex 1 0) }
            Add-B $b 0xC1; Add-B $b (Get-ModRM 3 $digit $dc); Add-B $b (Get-ImmValue $src $symbols $addr $defines $resolve)
        }
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }

    if ($mn -eq 'push') {
        $src=$ops[0]
        if ($src.Kind -eq 'reg') { if ($src.Reg.Size -ne 64) { throw 'push needs r64' }; if ($src.Reg.Code -ge 8) { Add-B $b 0x41 }; Add-B $b (0x50 + ($src.Reg.Code -band 7)) }
        elseif ($src.Kind -eq 'imm') { Add-B $b 0x68; Add-Dword $b (Get-ImmValue $src $symbols $addr $defines $resolve) }
        else { throw 'unsupported push' }
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }

    if ($mn -eq 'pop') {
        $dst=$ops[0]
        if ($dst.Kind -eq 'reg') { if ($dst.Reg.Size -ne 64) { throw 'pop needs r64' }; if ($dst.Reg.Code -ge 8) { Add-B $b 0x41 }; Add-B $b (0x58 + ($dst.Reg.Code -band 7)) }
        else { throw 'unsupported pop' }
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }

    if ($mn -eq 'call') {
        $src=$ops[0]
        if ($src.Kind -eq 'imm') { Add-B $b 0xE8; AddFx 1 ([string]$src.Value) 'rel32'; Add-Dword $b 0 }
        elseif ($src.Kind -eq 'mem') { Add-B $b 0xFF; $m=Encode-Mem $src.Mem 2 0; $off=$b.Count; foreach($x in $m.Bytes){$b.Add($x)}; foreach($f in $m.Fixups){AddFx ($off+$f.Offset) $f.Expr $f.Kind} }
        elseif ($src.Kind -eq 'reg') { if ($src.Reg.Code -ge 8) { Add-B $b 0x41 }; Add-B $b 0xFF; Add-B $b (Get-ModRM 3 2 $src.Reg.Code) }
        else { throw 'unsupported call' }
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }

    if ($mn -eq 'jmp') {
        $src=$ops[0]
        if ($src.Kind -eq 'imm') { Add-B $b 0xE9; AddFx 1 ([string]$src.Value) 'rel32'; Add-Dword $b 0 }
        elseif ($src.Kind -eq 'reg') { if ($src.Reg.Code -ge 8) { Add-B $b 0x41 }; Add-B $b 0xFF; Add-B $b (Get-ModRM 3 4 $src.Reg.Code) }
        else { throw 'unsupported jmp' }
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }

    if ($script:JCC.ContainsKey($mn)) {
        Add-B $b 0x0F; Add-B $b $script:JCC[$mn]; AddFx 2 ([string]$ops[0].Value) 'rel32'; Add-Dword $b 0
        return [pscustomobject]@{ Bytes=$b; Fixups=$fx }
    }

    if ($mn -eq 'rep') {
        if ($ops.Count -ge 1) {
            $sub = ([string]$ops[0].Value).ToLowerInvariant()
            if ($sub -eq 'movsb') { Add-B $b 0xF3; Add-B $b 0xA4; return [pscustomobject]@{ Bytes=$b; Fixups=$fx } }
            if ($sub -eq 'stosb') { Add-B $b 0xF3; Add-B $b 0xAA; return [pscustomobject]@{ Bytes=$b; Fixups=$fx } }
            if ($sub -eq 'stosd') { Add-B $b 0xF3; Add-B $b 0xAB; return [pscustomobject]@{ Bytes=$b; Fixups=$fx } }
        }
        throw 'unsupported rep'
    }

    if ($mn -eq 'ret') { Add-B $b 0xC3; return [pscustomobject]@{ Bytes=$b; Fixups=$fx } }

    throw "unsupported instruction: $mn"
}

# ---------------------------------------------------------------------------
# 汇编器
# ---------------------------------------------------------------------------
function Invoke-Assembler([string]$source, [hashtable]$defines, [string]$output) {
    $lines = Expand-Source $source $defines

    # 先把纯常量 define 求值
    $resolved = @{}
    foreach ($k in $defines.Keys) {
        try { $resolved[$k] = Eval-Expr ([string]$defines[$k]) @{} 0 $resolved $false }
        catch { $resolved[$k] = $defines[$k] }
    }

    $symbols = @{}
    $scope = ''
    $pc = [int64]0
    $pass1Fix = [System.Collections.Generic.List[object]]::new()

    # Pass 1: addresses
    for ($idx=0; $idx -lt $lines.Count; $idx++) { $script:curLine = $lines[$idx]
        $line = (Strip-Comment $lines[$idx]).Trim()
        if (-not $line) { continue }
        while ($line -match '^([A-Za-z_.][A-Za-z0-9_.]*):\s*(.*)$') {
            $label=$Matches[1]; $line=$Matches[2].Trim()
            if ($label.StartsWith('.')) { $full = "$scope$label".ToLowerInvariant() }
            else { $scope=$label; $full=$label.ToLowerInvariant() }
            if ($symbols.ContainsKey($full)) { throw "duplicate label: $label" }
            $symbols[$full]=$pc
        }
        $script:asmScope = $scope
        if (-not $line) { continue }
        if ($line -match '^([A-Za-z_.][A-Za-z0-9_.]*)\s+equ\s+(.+)$') {
            $name = $Matches[1].ToLowerInvariant()
            if ($Matches[1].StartsWith('.')) { $name = "$scope$($Matches[1])".ToLowerInvariant() }
            try { $symbols[$name] = Eval-Expr $Matches[2] $symbols $pc $resolved $true } catch { $symbols[$name]=0 }
            continue
        }
        if ($line -match '^(db|dw|dd|dq)\s+(.+)$') {
            $unit = @{db=1;dw=2;dd=4;dq=8}[$Matches[1].ToLowerInvariant()]
            $items = Split-Args $Matches[2]
            foreach ($it in $items) {
                if ($it -match '^"(.*)"$') {
                    $pc += (Get-AsmStringBytes $Matches[1]).Count
                } else { $pc += $unit }
            }
            continue
        }
        if ($line -match '^times\s+(.+?)\s+(db|dw|dd|dq)\s+(.+)$') {
            $count = Eval-Expr $Matches[1] $symbols $pc $resolved $true
            $unit = @{db=1;dw=2;dd=4;dq=8}[$Matches[2].ToLowerInvariant()]
            $items = Split-Args $Matches[3]
            $itemBytes = 0
            foreach ($it in $items) {
                if ($it -match '^"(.*)"$') {
                    $itemBytes += (Get-AsmStringBytes $Matches[1]).Count
                } else { $itemBytes += $unit }
            }
            $pc += [int64]$count * $itemBytes
            continue
        }
        if ($line -match '^align\s+(.+)$') { $alignArg = $Matches[1]; $bound=[int64](Eval-Expr $alignArg $symbols $pc $resolved $false); $pad = ($bound - ($pc % $bound)) % $bound; $pc += $pad; continue }
        if ($line -match '^([A-Za-z][A-Za-z0-9]*)\s*(.*)$') {
            $mn=$Matches[1]; $rest=$Matches[2].Trim()
            $ops = @(); if ($rest) { $ops = @(Split-Args $rest | ForEach-Object { Parse-Operand $_ }) }
            $enc = Encode-Instruction $mn $ops $pc $symbols $resolved $false
            $pc += $enc.Bytes.Count
            continue
        }
    }

    # Pass 2: emit
    $data = [System.Collections.Generic.List[byte]]::new()
    $fixups = [System.Collections.Generic.List[object]]::new()
    $scope=''; $pc=[int64]0
    for ($idx=0; $idx -lt $lines.Count; $idx++) { $script:curLine = $lines[$idx]
        $line = (Strip-Comment $lines[$idx]).Trim()
        if (-not $line) { continue }
        while ($line -match '^([A-Za-z_.][A-Za-z0-9_.]*):\s*(.*)$') {
            $label=$Matches[1]; $line=$Matches[2].Trim()
            if (-not $label.StartsWith('.')) { $scope=$label }
            continue
        }
        $script:asmScope = $scope
        if (-not $line) { continue }
        if ($line -match '^([A-Za-z_.][A-Za-z0-9_.]*)\s+equ\s+(.+)$') { continue }
        if ($line -match '^(db|dw|dd|dq)\s+(.+)$') {
            $unit = @{db=1;dw=2;dd=4;dq=8}[$Matches[1].ToLowerInvariant()]
            $items = Split-Args $Matches[2]
            foreach ($it in $items) {
                $it=$it.Trim()
                if ($it -match '^"(.*)"$') {
                    $bytes = Get-AsmStringBytes $Matches[1]
                    foreach($bt in $bytes){$data.Add($bt)}
                } elseif ($it -match "^'([^']*)'$") {
                    $chv = [int][char]$Matches[1]
                    for($j=0;$j -lt $unit;$j++){ $data.Add([byte](($chv -shr (8*$j)) -band 0xFF)) }
                } else {
                    $v = [int64](Eval-Expr $it $symbols $pc $resolved $false)
                    for($j=0;$j -lt $unit;$j++){ $data.Add([byte](($v -shr (8*$j)) -band 0xFF)) }
                }
            }
            $pc=$data.Count
            continue
        }
        if ($line -match '^times\s+(.+?)\s+(db|dw|dd|dq)\s+(.+)$') {
            $count=[int64](Eval-Expr $Matches[1] $symbols $pc $resolved $false)
            $unit = @{db=1;dw=2;dd=4;dq=8}[$Matches[2].ToLowerInvariant()]
            $items=Split-Args $Matches[3]
            for($n=0;$n -lt $count;$n++){
                foreach($it in $items){
                    $it=$it.Trim()
                    if ($it -match '^"(.*)"$') {
                        foreach($bt in (Get-AsmStringBytes $Matches[1])){$data.Add($bt)}
                    } elseif ($it -match "^'([^']*)'$") {
                        $chv = [int][char]$Matches[1]
                        for($j=0;$j -lt $unit;$j++){ $data.Add([byte](($chv -shr (8*$j)) -band 0xFF)) }
                    } else {
                        $v=[int64](Eval-Expr $it $symbols $pc $resolved $false)
                        for($j=0;$j -lt $unit;$j++){ $data.Add([byte](($v -shr (8*$j)) -band 0xFF)) }
                    }
                }
            }
            $pc=$data.Count
            continue
        }
        if ($line -match '^align\s+(.+)$') {
            $alignArg = $Matches[1]
            $bound=[int64](Eval-Expr $alignArg $symbols $pc $resolved $false)
            $pad = ($bound - ($pc % $bound)) % $bound
            for($j=0;$j -lt $pad;$j++){$data.Add([byte]0)}
            $pc=$data.Count
            continue
        }
        if ($line -match '^([A-Za-z][A-Za-z0-9]*)\s*(.*)$') {
            $mn=$Matches[1]; $rest=$Matches[2].Trim()
            $ops = @(); if ($rest) { $ops = @(Split-Args $rest | ForEach-Object { Parse-Operand $_ }) }
            $enc = Encode-Instruction $mn $ops $pc $symbols $resolved $true
            $start=$data.Count
            foreach($bt in $enc.Bytes){$data.Add($bt)}
            foreach($f in $enc.Fixups){ $fixups.Add(@{ At=[int64]($start+$f.Offset); End=[int64]($start+$enc.Bytes.Count); Expr=$f.Expr; Kind=$f.Kind; Scope=$f.Scope }) }
            $pc=$data.Count
            continue
        }
    }

    # Apply fixups
    foreach($f in $fixups){
        $prevScope = $script:asmScope
        $script:asmScope = [string]$f.Scope
        $target=[int64](Eval-Expr $f.Expr $symbols $f.End $resolved $false)
        $script:asmScope = $prevScope
        $val = switch($f.Kind){
            'rel32' { $target - $f.End }
            'rip32' { $target - $f.End }
            'abs32' { $target }
            'abs64' { $target }
        }
        $span = 4
        if ($f.Kind -eq 'abs64') { $span = 8 }
        for($j=0;$j -lt $span;$j++){ $data[$f.At+$j]=[byte](($val -shr (8*$j)) -band 0xFF) }
    }

    [IO.File]::WriteAllBytes((Resolve-Path -LiteralPath (Split-Path -Parent $output)).Path + '\' + (Split-Path -Leaf $output), [byte[]]$data)
    Write-Host ("asm: {0} ({1} bytes)" -f $output, $data.Count)
}

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
$args = $args
$source=$null; $output=$null; $defs=@{}
for($i=0;$i -lt $args.Count;$i++){
    switch($args[$i]){
        '-Source' { $i++; $source=$args[$i] }
        '-Output' { $i++; $output=$args[$i] }
        '-Define' { $i++; $kv=$args[$i]; $p=$kv.Split('=',2); $defs[$p[0].ToLowerInvariant()] = '1'; if($p.Count -gt 1){ $defs[$p[0].ToLowerInvariant()] = $p[1] } }
    }
}
if(-not $source -or -not $output){ throw 'usage: asm.ps1 -Source <file> -Output <file> [-Define NAME=VALUE]' }
try { Invoke-Assembler $source $defs $output } catch { Write-Host "asm failed at: $script:curLine"; throw }

















