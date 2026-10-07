# ==============================================================================
# Boardest Virtual Demo (가상 체험 데모 앱) 원클릭 자동 설치 스크립트
# 실행: irm https://bst-installer.web.app/install-demo.ps1 | iex
# ==============================================================================

$ErrorActionPreference = "Continue"

# 1. 관리자 권한 확인 및 승격
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host ""
    Write-Host "[Boardest Demo Installer] 관리자 권한이 필요합니다." -ForegroundColor Yellow
    Write-Host "UAC 관리자 승격 창이 뜨면 '예'를 눌러주세요..." -ForegroundColor Cyan
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://bst-installer.web.app/install-demo.ps1 | iex`"" -Verb RunAs
    exit 0
}

Clear-Host
Write-Host ""
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host "   🎓 Boardest 가상 체험관 (Demo Mode - Windows 전용) 설치기" -ForegroundColor White
Write-Host "======================================================================" -ForegroundColor Cyan
Write-Host ""

# 2. 인증서 등록
Write-Host "[1/3] 보안 인증서 설치 중..." -ForegroundColor Yellow
$tempCer = Join-Path $env:TEMP "BoardestCert.cer"
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13
    Invoke-WebRequest -Uri "https://bst-installer.web.app/BoardestCert.cer" -OutFile $tempCer -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
} catch {
    $embeddedB64 = "MIIC8jCCAdqgAwIBAgIQRxUMwz00P7ZGR1hIM7A28TANBgkqhkiG9w0BAQsFADAQMQ4wDAYDVQQDDAVqaXdobzAgFw0yNjA5MDQxMTI5NDhaGA8yOTk5MTIzMTE0NTk1OVowEDEOMAwGA1UEAwwFaml3aG8wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCzxVnksBunAyUZ/K24xIM1XMWwXi6TvS2Kc3IRuZqJm5HMnZZnBl3X7UF22oeOTIs7Z/bWphD685HRSL0qOBAA3sV9tWjrh6CRUl3ChjlnNXSNBTiFrRboZlwZkOqcxmQVNvmKXqlfvI1OGH0Q6bXg2CmX5Za+mD6HfCtp85voa2c3AIEllQTU3IFX7OnrfQ1djDI0CFcX+Gs9yan7RBc+FA2CVNi6/UKZP1FPnu3lUmba9R8IyGE9g7MtkgvUa2zVSZ5+8s1cW05gZJ2w6iPQfYAeAZnmXEqdngnjRmWGGohs9OgO2a4XEEMgcEElNY1LtHRO7MSnGBgnqO+Px1htAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQUVApFzZbru8xFagw5cKZbZxzrbCIwDQYJKoZIhvcNAQELBQADggEBAFq2UqnO223ngalT8VEs0r+L5Omko73xA9TipS61LGLuH0xKTsluTQ44vgJNGHvZg9Qi+BBgoRYGCiC+Nzm8R3fvBA3t7dBaZiaRBbzPe83KaqbF7BJffW+8XYf4AmT+X608y9TSwxfyZsXzpaR7pzSAf4DzWyUnLeODFch4wTEdldoOPbm/lmRmlhoR10t4J+cHMG8Fo5qSSCe+5pkYo1QrJ7LZFYjfwihINeNNMM721YSC08UKXM2Xo+Cm4Ra7K5JnJCeWogewyLY23UMBiDQ4mPxEmwfcxGSmZU8mVv+w4d5pnT2px4xQ2ngTmZwsjkRovzjozrTJ3hsKavlk4KA="
    [IO.File]::WriteAllBytes($tempCer, [Convert]::FromBase64String($embeddedB64))
}

Import-Certificate -FilePath $tempCer -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
Import-Certificate -FilePath $tempCer -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" | Out-Null
Import-Certificate -FilePath $tempCer -CertStoreLocation "Cert:\CurrentUser\Root" | Out-Null
Import-Certificate -FilePath $tempCer -CertStoreLocation "Cert:\CurrentUser\TrustedPeople" | Out-Null
Write-Host "  -> 인증서 등록 완료" -ForegroundColor Green

# 3. 패키지 다운로드 및 설치
Write-Host "[2/3] Boardest 가상 데모 지원 패키지 다운로드 중..." -ForegroundColor Yellow
$tempAppx = Join-Path $env:TEMP "boardest.appx"
$downloadUrl = "https://bst-installer.web.app/boardest.appx"
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempAppx -UseBasicParsing -ErrorAction Stop
} catch {
    Invoke-WebRequest -Uri "https://github.com/hiJiwho/Boardest/releases/latest/download/boardest.appx" -OutFile $tempAppx -UseBasicParsing
}

Write-Host "[3/3] 패키지 등록 및 바탕화면 바로가기 생성 중..." -ForegroundColor Yellow
try {
    Add-AppxPackage -Path $tempAppx -ErrorAction Stop

    # 바탕화면 바로가기 생성 (Demo 플래그 지정)
    $wshShell = New-Object -ComObject WScript.Shell
    $desktopPath = [Environment]::GetFolderPath("Desktop")
    $shortcutPath = Join-Path $desktopPath "Boardest 데모 체험.lnk"
    $shortcut = $wshShell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = "powershell.exe"
    $shortcut.Arguments = "-WindowStyle Hidden -Command Start-Process 'explorer.exe' 'shell:AppsFolder\jiwho.boardest.bst_nmkn64tehfz7a!App?demo=yes'"
    $shortcut.Description = "Boardest 가상 체험 데모 모드로 바로 실행"
    $shortcut.Save()

    Write-Host ""
    Write-Host "======================================================================" -ForegroundColor Green
    Write-Host " 🎉 [성공] Boardest 가상 체험 데모 앱 설치가 완료되었습니다!" -ForegroundColor Green
    Write-Host "    바탕화면의 [Boardest 데모 체험] 아이콘을 누르면 즉시 데모가 실행됩니다." -ForegroundColor White
    Write-Host "======================================================================" -ForegroundColor Green
} catch {
    Write-Host "  [!] 설치 실패: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "아무 키나 누르면 창을 닫습니다..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
