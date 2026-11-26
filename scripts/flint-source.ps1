# Expand Flint source include directives.
# Directive form: // include: relative/path.fl
# Includes are expanded recursively, relative to the file that contains them.

function Expand-FlintSource {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $dir = Split-Path -Parent $Path
    $lines = Get-Content -LiteralPath $Path
    $out = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        if ($line -match '^\s*//\s*include:\s*(.+?)\s*$') {
            $inc = Join-Path $dir $Matches[1]
            if (-not (Test-Path -LiteralPath $inc)) {
                throw "include not found: $inc (from $Path)"
            }
            $out.Add("// begin include: $($Matches[1])")
            foreach ($incLine in (Expand-FlintSource -Path $inc)) {
                $out.Add($incLine)
            }
            $out.Add("// end include: $($Matches[1])")
        } else {
            $out.Add($line)
        }
    }

    return $out.ToArray()
}
