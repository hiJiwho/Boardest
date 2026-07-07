$content = Get-Content -Path lib/views/setup_wizard_view.dart -Encoding utf8
$braces = 0
for ($i = 0; $i -lt $content.Length; $i++) {
    $line = $content[$i]
    if ($i -ge 22) { # line 23 is index 22
        $opens = [regex]::Matches($line, '\{').Count
        $closes = [regex]::Matches($line, '\}').Count
        $braces += $opens - $closes
        if ($braces -eq 1 -and ($opens -ne 0 -or $closes -ne 0)) {
            Write-Host "Line $($i+1): $line (braces=$braces)"
        }
        if ($braces -eq 0) {
            Write-Host "Line $($i+1): $line (CLASS CLOSED!)"
            break
        }
    }
}
