$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " 1. Boardest Web Build (--no-tree-shake-icons) " -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

Set-Location "$PSScriptRoot\..\apps\boardest"
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Boardest web build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " 2. Boardest Teacher Web Build " -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

Set-Location "$PSScriptRoot\..\apps\boardest_teacher"
flutter build web --release --no-tree-shake-icons --no-wasm-dry-run
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Teacher web build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " 3. Firebase Hosting Deploy " -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan

Set-Location "$PSScriptRoot\.."
cmd.exe /c "firebase deploy --only hosting:boardest-main,hosting:boardest-teacher,hosting:download-boardest,hosting:welcome-to-boardest"

Write-Host "========================================" -ForegroundColor Green
Write-Host " Web Build & Firebase Deploy Completed! " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
