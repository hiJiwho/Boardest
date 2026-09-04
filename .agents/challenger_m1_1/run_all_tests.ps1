$packages = @(
    'packages/common/bst_core',
    'packages/common/bst_auth',
    'packages/common/bst_cloud',
    'packages/common/bst_cast',
    'packages/common/bst_timetable',
    'packages/common/bst_messaging',
    'packages/common/bst_ui',
    'packages/common/bst_control',
    'packages/common/bst_ad',
    'packages/plugins/bst_pen',
    'packages/plugins/bst_tbp',
    'packages/plugins/bst_native',
    'packages/plugins/bst_canva',
    'packages/plugins/bst_pdf',
    'packages/plugins/bst_video'
)

$allPassed = $true
$results = @()

foreach ($p in $packages) {
    Write-Host "`n========================================"
    Write-Host "Running tests in: $p"
    Write-Host "========================================"
    Push-Location $p
    $output = flutter test 2>&1
    $exitCode = $LASTEXITCODE
    Pop-Location
    
    if ($exitCode -eq 0) {
        Write-Host "[PASS] $p" -ForegroundColor Green
        $results += [PSCustomObject]@{ Package = $p; Status = "PASS"; Output = ($output | Out-String) }
    } else {
        Write-Host "[FAIL] $p (Exit Code: $exitCode)" -ForegroundColor Red
        $allPassed = $false
        $results += [PSCustomObject]@{ Package = $p; Status = "FAIL"; Output = ($output | Out-String) }
    }
}

Write-Host "`n========================================"
Write-Host "SUMMARY RESULTS:"
Write-Host "========================================"
foreach ($r in $results) {
    Write-Host "$($r.Status): $($r.Package)"
}

if (-not $allPassed) {
    exit 1
}
