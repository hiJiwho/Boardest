# Boardest Certificate Installer PowerShell Script
# Requires Administrator privileges to register into LocalMachine store

$CertPath = Join-Path $PSScriptRoot "BoardestCert.cer"

if (-not (Test-Path $CertPath)) {
    Write-Error "BoardestCert.cer not found at $CertPath"
    exit 1
}

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Elevating to Administrator..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit 0
}

try {
    Import-Certificate -FilePath $CertPath -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" | Out-Null
    Write-Host "[SUCCESS] Boardest certificate installed into LocalMachine\TrustedPeople!" -ForegroundColor Green
} catch {
    Write-Error "Failed to install certificate: $_"
    exit 1
}
