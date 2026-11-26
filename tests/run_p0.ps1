# ===========================================================================
# 阶段 0 验收脚本：正例比较 stdout 与退出码，反例校验错误消息、行列与退出码
# 用法：pwsh -NoProfile -File tests\run_p0.ps1
# 全部通过返回 0，任一失败返回 1。
# ===========================================================================
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$stage0 = Join-Path $root 'bootstrap\flintc0.exe'
$work = Join-Path $root 'build\testrun'
if (-not (Test-Path -LiteralPath $stage0)) { throw "缺少上一级编译器: $stage0" }
if (-not (Test-Path -LiteralPath $work)) { New-Item -ItemType Directory -Path $work | Out-Null }

# 正例：期望 stdout 行数组 + 期望进程退出码
$pos = @(
    @{ file = 'ai_arith.fl';  out = @('14', '20', '-2', '1'); code = 33 },
    @{ file = 'ai_funcs.fl';  out = @('42');                  code = 42 },
    @{ file = 'ai_noret.fl';  out = @('0');                   code = 5  }
)

# 反例：期望消息片段 + 期望 "行:列" 前缀 + 退出码 1
$neg = @(
    @{ file = 'badchar.fl';     msg = '无效字符';                    loc = '2:20' },
    @{ file = 'blockcomment.fl';msg = '块注释未闭合';                loc = '2:5'  },
    @{ file = 'overflow.fl';    msg = '整数字面量超出 i64 范围';     loc = '2:18' },
    @{ file = 'string.fl';      msg = '阶段 0 不支持字符串字面量';   loc = '2:18' },
    @{ file = 'semi.fl';        msg = "期望 ';'";                    loc = '3:5'  },
    @{ file = 'undef.fl';       msg = '未定义的标识符';              loc = '2:18' },
    @{ file = 'undef_fn.fl';    msg = '未定义的函数';                loc = '2:12' },
    @{ file = 'arity.fl';       msg = '参数数量不匹配';              loc = '3:12' },
    @{ file = 'dupfn.fl';       msg = '重复的函数定义';              loc = '2:4'  },
    @{ file = 'duplocal.fl';    msg = '重复的局部变量';              loc = '3:9'  },
    @{ file = 'main_missing.fl';msg = '缺少 main 函数';              loc = '1:1'  },
    @{ file = 'fnvalue.fl';     msg = '函数名不能作为值使用';        loc = '3:18' },
    @{ file = 'printdef.fl';    msg = 'print 为内建函数名';          loc = '1:4'  },
    @{ file = 'toomanyargs.fl'; msg = '最多支持 4 个参数';           loc = '1:4'  }
)

$pass = 0
$fail = 0
$failList = @()

Write-Host '--- 正例 ---'
foreach ($t in $pos) {
    $src = Join-Path $root ('tests\p0\pos\' + $t.file)
    $exe = Join-Path $work ([IO.Path]::GetFileNameWithoutExtension($t.file) + '.exe')
    $compile = & $stage0 $src $exe 2>&1
    if ($LASTEXITCODE -ne 0) {
        $fail++; $failList += ($t.file + ' 编译失败: ' + ($compile -join ' / ')); continue
    }
    $run = & $exe 2>&1
    $code = $LASTEXITCODE
    $got = @($run | ForEach-Object { $_.ToString().TrimEnd() })
    $exp = @($t.out)
    if (($code -eq $t.code) -and (($got -join "`n") -eq ($exp -join "`n"))) {
        $pass++; Write-Host ('  [OK]   ' + $t.file + '  out=' + ($got -join ',') + ' exit=' + $code)
    } else {
        $fail++; $failList += ($t.file + ' 期望 out=' + ($exp -join ',') + ' exit=' + $t.code + ' 实际 out=' + ($got -join ',') + ' exit=' + $code)
        Write-Host ('  [FAIL] ' + $t.file)
    }
}

Write-Host '--- 反例 ---'
foreach ($t in $neg) {
    $src = Join-Path $root ('tests\p0\neg\' + $t.file)
    $out = & $stage0 $src (Join-Path $work 'neg.exe') 2>&1
    $code = $LASTEXITCODE
    $text = ($out | Out-String)
    $okMsg = $text.Contains($t.msg)
    $okLoc = $text -match ([regex]::Escape($t.file) + ':' + [regex]::Escape($t.loc) + ': error:')
    $okCode = ($code -eq 1)
    $hasSnippet = ($out | Where-Object { $_ -match '^\s*\d+ \|' }).Count -ge 1
    if ($okMsg -and $okLoc -and $okCode -and $hasSnippet) {
        $pass++; Write-Host ('  [OK]   ' + $t.file + '  ' + $t.loc + ' ' + $t.msg)
    } else {
        $fail++; $failList += ($t.file + ' 期望 ' + $t.loc + ' ' + $t.msg + ' exit=1；实际 exit=' + $code + '；输出=' + $text.Trim())
        Write-Host ('  [FAIL] ' + $t.file)
    }
}

Write-Host ''
Write-Host ('通过 ' + $pass + ' / ' + ($pass + $fail))
if ($fail -gt 0) {
    Write-Host '失败明细：'
    $failList | ForEach-Object { Write-Host ('  - ' + $_) }
    exit 1
}
exit 0
