# ==============================================================================
# Boardest 영구 인증서(2999년 만료) 원클릭 자동 설치 스크립트
# 실행: irm https://download-boardest.web.app/win-cer.ps1 | iex
# ==============================================================================

$ErrorActionPreference = "Continue"

# 1. 관리자 권한 확인 및 자동 승격 (UAC)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "[Boardest Installer] 관리자 권한이 필요합니다." -ForegroundColor Yellow
    Write-Host "UAC 관리자 승격 창이 뜨면 '예'를 눌러주세요..." -ForegroundColor Cyan
    Write-Host ""
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://download-boardest.web.app/win-cer.ps1 | iex`"" -Verb RunAs
    exit 0
}

Clear-Host
Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "   🎓 Boardest 차세대 스마트 교육 플랫폼 - 영구 인증서 설치기" -ForegroundColor White
Write-Host "   인증서 만료일: 2999-12-31 (무제한 영구 서명)" -ForegroundColor DarkGray
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

# 2. 최신 cer 다운로드
$tempCerPath = Join-Path $env:TEMP "BoardestCert.cer"
$downloadSuccess = $false

Write-Host "[1/3] 최신 Boardest 영구 인증서 다운로드 중..." -ForegroundColor Yellow

$sources = @(
    "https://download-boardest.web.app/BoardestCert.cer",
    "https://welcome-to-boardest.web.app/BoardestCert.cer",
    "https://github.com/hiJiwho/Boardest/releases/latest/download/BoardestCert.cer"
)

foreach ($url in $sources) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
        Invoke-WebRequest -Uri $url -OutFile $tempCerPath -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ((Test-Path $tempCerPath) -and ((Get-Item $tempCerPath).Length -gt 100)) {
            Write-Host "  -> 다운로드 완료 ($url)" -ForegroundColor Green
            $downloadSuccess = $true
            break
        }
    } catch {
        # 다음 소스로 시도
    }
}

if (-not $downloadSuccess) {
    Write-Host "  -> 온라인 다운로드 실패, 내장 비상 인증서 데이터를 복원합니다..." -ForegroundColor DarkYellow
    $embeddedB64 = "MIIC8jCCAdqgAwIBAgIQRxUMwz00P7ZGR1hIM7A28TANBgkqhkiG9w0BAQsFADAQMQ4wDAYDVQQDDAVqaXdobzAgFw0yNjA5MDQxMTI5NDhaGA8yOTk5MTIzMTE0NTk1OVowEDEOMAwGA1UEAwwFaml3aG8wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCzxVnksBunAyUZ/K24xIM1XMWwXi6TvS2Kc3IRuZqJm5HMnZZnBl3X7UF22oeOTIs7Z/bWphD685HRSL0qOBAA3sV9tWjrh6CRUl3ChjlnNXSNBTiFrRboZlwZkOqcxmQVNvmKXqlfvI1OGH0Q6bXg2CmX5Za+mD6HfCtp85voa2c3AIEllQTU3IFX7OnrfQ1djDI0CFcX+Gs9yan7RBc+FA2CVNi6/UKZP1FPnu3lUmba9R8IyGE9g7MtkgvUa2zVSZ5+8s1cW05gZJ2w6iPQfYAeAZnmXEqdngnjRmWGGohs9OgO2a4XEEMgcEElNY1LtHRO7MSnGBgnqO+Px1htAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQUVApFzZbru8xFagw5cKZbZxzrbCIwDQYJKoZIhvcNAQELBQADggEBAFq2UqnO223ngalT8VEs0r+L5Omko73xA9TipS61LGLuH0xKTsluTQ44vgJNGHvZg9Qi+BBgoRYGCiC+Nzm8R3fvBA3t7dBaZiaRBbzPe83KaqbF7BJffW+8XYf4AmT+X608y9TSwxfyZsXzpaR7pzSAf4DzWyUnLeODFch4wTEdldoOPbm/lmRmlhoR10t4J+cHMG8Fo5qSSCe+5pkYo1QrJ7LZFYjfwihINeNNMM721YSC08UKXM2Xo+Cm4Ra7K5JnJCeWogewyLY23UMBiDQ4mPxEmwfcxGSmZU8mVv+w4d5pnT2px4xQ2ngTmZwsjkRovzjozrTJ3hsKavlk4KA="
    [IO.File]::WriteAllBytes($tempCerPath, [Convert]::FromBase64String($embeddedB64))
}

# 3. 로컬 머신 루트 및 신뢰할 수 있는 사용자 저장소에 등록
Write-Host ""
Write-Host "[2/2] Windows 보안 인증소에 등록 중..." -ForegroundColor Yellow

try {
    # 0x800B0109 에러 원천 방지: LocalMachine\Root
    Import-Certificate -FilePath $tempCerPath -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
    Write-Host "  [V] 로컬 컴퓨터 -> 신뢰할 수 있는 루트 인증 기관 (LocalMachine\Root) 등록 완료" -ForegroundColor Green

    # LocalMachine\TrustedPeople
    Import-Certificate -FilePath $tempCerPath -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" | Out-Null
    Write-Host "  [V] 로컬 컴퓨터 -> 신뢰할 수 있는 사용자 (LocalMachine\TrustedPeople) 등록 완료" -ForegroundColor Green

    # CurrentUser 에도 보조 등록
    Import-Certificate -FilePath $tempCerPath -CertStoreLocation "Cert:\CurrentUser\Root" | Out-Null
    Import-Certificate -FilePath $tempCerPath -CertStoreLocation "Cert:\CurrentUser\TrustedPeople" | Out-Null

    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host " 🎉 [성공] Boardest 영구 보안 인증서 등록이 완료되었습니다!" -ForegroundColor Green
    Write-Host "    - 로컬 컴퓨터 -> 신뢰할 수 있는 루트 인증 기관 등록 완료" -ForegroundColor White
    Write-Host "    - 0x800B0109 보안 경고 없이 안전하게 모든 Boardest 앱을 설치하실 수 있습니다." -ForegroundColor White
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Host "  [!] 인증서 등록 오류: $_" -ForegroundColor Red
}

# 임시 파일 정리
if (Test-Path $tempCerPath) {
    Remove-Item -Path $tempCerPath -Force -ErrorAction SilentlyContinue
}

Write-Host "인증서 설치가 완료되었습니다! 이제 웹사이트에서 원하는 앱을 설치하세요." -ForegroundColor Cyan
Write-Host "창을 닫으려면 엔터 키를 누르세요..." -ForegroundColor DarkGray
Read-Host
