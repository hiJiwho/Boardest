# ==============================================================================
# Boardest 영구 인증서(2999년 만료) 자동 설치기
# ==============================================================================

# 1. 관리자 권한 확인 및 자동 승격
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[안내] 관리자 권한이 필요합니다. 관리자 권한으로 다시 실행합니다..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit 0
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Boardest 영구 인증서 (만료일: 2999-12-31) 설치 시작" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# 2. 인증서 파일 찾기 또는 내장 Base64 복원
$CertPath = Join-Path $PSScriptRoot "BoardestCert.cer"

if (-not (Test-Path $CertPath)) {
    Write-Host "[정보] 폴더 내 BoardestCert.cer 파일이 없어 내장 인증서 데이터를 사용합니다..." -ForegroundColor Yellow
    $CertBase64 = "MIIC8jCCAdqgAwIBAgIQRxUMwz00P7ZGR1hIM7A28TANBgkqhkiG9w0BAQsFADAQMQ4wDAYDVQQDDAVqaXdobzAgFw0yNjA5MDQxMTI5NDhaGA8yOTk5MTIzMTE0NTk1OVowEDEOMAwGA1UEAwwFaml3aG8wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCzxVnksBunAyUZ/K24xIM1XMWwXi6TvS2Kc3IRuZqJm5HMnZZnBl3X7UF22oeOTIs7Z/bWphD685HRSL0qOBAA3sV9tWjrh6CRUl3ChjlnNXSNBTiFrRboZlwZkOqcxmQVNvmKXqlfvI1OGH0Q6bXg2CmX5Za+mD6HfCtp85voa2c3AIEllQTU3IFX7OnrfQ1djDI0CFcX+Gs9yan7RBc+FA2CVNi6/UKZP1FPnu3lUmba9R8IyGE9g7MtkgvUa2zVSZ5+8s1cW05gZJ2w6iPQfYAeAZnmXEqdngnjRmWGGohs9OgO2a4XEEMgcEElNY1LtHRO7MSnGBgnqO+Px1htAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQUVApFzZbru8xFagw5cKZbZxzrbCIwDQYJKoZIhvcNAQELBQADggEBAFq2UqnO223ngalT8VEs0r+L5Omko73xA9TipS61LGLuH0xKTsluTQ44vgJNGHvZg9Qi+BBgoRYGCiC+Nzm8R3fvBA3t7dBaZiaRBbzPe83KaqbF7BJffW+8XYf4AmT+X608y9TSwxfyZsXzpaR7pzSAf4DzWyUnLeODFch4wTEdldoOPbm/lmRmlhoR10t4J+cHMG8Fo5qSSCe+5pkYo1QrJ7LZFYjfwihINeNNMM721YSC08UKXM2Xo+Cm4Ra7K5JnJCeWogewyLY23UMBiDQ4mPxEmwfcxGSmZU8mVv+w4d5pnT2px4xQ2ngTmZwsjkRovzjozrTJ3hsKavlk4KA="
    $certBytes = [Convert]::FromBase64String($CertBase64)
    [IO.File]::WriteAllBytes($CertPath, $certBytes)
}

try {
    # 3. LocalMachine\Root (로컬 컴퓨터 -> 신뢰할 수 있는 루트 인증 기관)에 등록 - AppX 패키지 0x800B0109 해결 필수
    Import-Certificate -FilePath $CertPath -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
    Write-Host " [V] 로컬 머신 루트 인증 저장소 (LocalMachine\Root) 등록 완료" -ForegroundColor Green

    # 4. LocalMachine\TrustedPeople (로컬 컴퓨터 -> 신뢰할 수 있는 사용자)에 등록
    Import-Certificate -FilePath $CertPath -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" | Out-Null
    Write-Host " [V] 신뢰할 수 있는 사용자 (LocalMachine\TrustedPeople) 등록 완료" -ForegroundColor Green

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " [성공] Boardest 인증서 등록이 성공적으로 완료되었습니다!" -ForegroundColor Green
    Write-Host " 이제 boardest.appinstaller 또는 .appx 를 실행하여 설치하세요." -ForegroundColor White
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
} catch {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " [오류] 인증서 등록 실패: $_" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host ""
}

Write-Host "계속하려면 아무 키나 누르세요..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
