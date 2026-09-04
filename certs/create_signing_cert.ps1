param(
    [string]$CertDir = "c:\Users\jiwho\Documents\boardest\certs",
    [string]$Subject = "CN=jiwho",
    [string]$Password = "Boardest2026!",
    [string]$PfxName = "BoardestCert.pfx",
    [string]$CerName = "BoardestCert.cer"
)

# Ensure certs directory exists
if (-not (Test-Path $CertDir)) {
    New-Item -ItemType Directory -Path $CertDir -Force | Out-Null
}

$PfxPath = Join-Path $CertDir $PfxName
$CerPath = Join-Path $CertDir $CerName

Write-Host "Creating Self-Signed Code Signing Certificate with Subject: $Subject..." -ForegroundColor Cyan

# Create self-signed code signing certificate in CurrentUser\My
$cert = New-SelfSignedCertificate `
    -Type CodeSigningCert `
    -Subject $Subject `
    -KeyUsage DigitalSignature `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -FriendlyName "Boardest MSIX Signing Certificate" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -NotAfter ([DateTime]::Parse("2999-12-31 23:59:59"))

$securePassword = ConvertTo-SecureString -String $Password -Force -AsPlainText

# Export PFX with private key
Export-PfxCertificate -Cert $cert -FilePath $PfxPath -Password $securePassword -Force | Out-Null
Write-Host "Exported PFX to: $PfxPath" -ForegroundColor Green

# Export CER public certificate
Export-Certificate -Cert $cert -FilePath $CerPath -Force | Out-Null
Write-Host "Exported CER to: $CerPath" -ForegroundColor Green

# Install to CurrentUser\TrustedPeople for local packaging/signing trust
Import-Certificate -FilePath $CerPath -CertStoreLocation "Cert:\CurrentUser\TrustedPeople" | Out-Null
Write-Host "Certificate installed to CurrentUser\TrustedPeople" -ForegroundColor Green

Write-Host "Certificate generation and installation complete!" -ForegroundColor Cyan
