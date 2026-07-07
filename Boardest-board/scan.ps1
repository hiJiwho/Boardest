$content = Get-Content -Path lib/views/setup_wizard_view.dart -Encoding utf8
$braces = 0
$found = $false
for ($i = 0; $i -lt $content.Length; $i++) {
    $line = $content[$i]
    if ($i -ge 22) { # line 23 is index 22
        # count { and } in this line
        $opens = [regex]::Matches($line, '\{').Count
        $closes = [regex]::Matches($line, '\}').Count
        $braces += $opens - $closes
        if ($braces -eq 0 -and !$found) {
            Write-Host "Brace count reached 0 at line $($i+1): $line"
            $found = $true
        }
    }
}
Write-Host "Total lines scanned: $($content.Length)"
