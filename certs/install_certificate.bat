@echo off
title Boardest Certificate Installer
setlocal enabledelayedexpansion

:: 1. 관리자 권한 확인 및 자동 승격
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] 관리자 권한을 요청합니다...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b 0
)

cls
echo ========================================================
echo   Boardest 영구 인증서 원클릭 자동 설치기
echo ========================================================
echo.

set "TEMP_CER=%TEMP%\BoardestCert_%RANDOM%.cer"

:: 2. 인증서 Base64 디코딩 (PowerShell 내장)
echo [1/2] 내장된 인증서 데이터 추출 중...
powershell -NoProfile -Command ^
  "$b64 = 'MIIC8jCCAdqgAwIBAgIQRxUMwz00P7ZGR1hIM7A28TANBgkqhkiG9w0BAQsFADAQMQ4wDAYDVQQDDAVqaXdobzAgFw0yNjA5MDQxMTI5NDhaGA8yOTk5MTIzMTE0NTk1OVowEDEOMAwGA1UEAwwFaml3aG8wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCzxVnksBunAyUZ/K24xIM1XMWwXi6TvS2Kc3IRuZqJm5HMnZZnBl3X7UF22oeOTIs7Z/bWphD685HRSL0qOBAA3sV9tWjrh6CRUl3ChjlnNXSNBTiFrRboZlwZkOqcxmQVNvmKXqlfvI1OGH0Q6bXg2CmX5Za+mD6HfCtp85voa2c3AIEllQTU3IFX7OnrfQ1djDI0CFcX+Gs9yan7RBc+FA2CVNi6/UKZP1FPnu3lUmba9R8IyGE9g7MtkgvUa2zVSZ5+8s1cW05gZJ2w6iPQfYAeAZnmXEqdngnjRmWGGohs9OgO2a4XEEMgcEElNY1LtHRO7MSnGBgnqO+Px1htAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQUVApFzZbru8xFagw5cKZbZxzrbCIwDQYJKoZIhvcNAQELBQADggEBAFq2UqnO223ngalT8VEs0r+L5Omko73xA9TipS61LGLuH0xKTsluTQ44vgJNGHvZg9Qi+BBgoRYGCiC+Nzm8R3fvBA3t7dBaZiaRBbzPe83KaqbF7BJffW+8XYf4AmT+X608y9TSwxfyZsXzpaR7pzSAf4DzWyUnLeODFch4wTEdldoOPbm/lmRmlhoR10t4J+cHMG8Fo5qSSCe+5pkYo1QrJ7LZFYjfwihINeNNMM721YSC08UKXM2Xo+Cm4Ra7K5JnJCeWogewyLY23UMBiDQ4mPxEmwfcxGSmZU8mVv+w4d5pnT2px4xQ2ngTmZwsjkRovzjozrTJ3hsKavlk4KA=';" ^
  "[IO.File]::WriteAllBytes('%TEMP_CER%', [Convert]::FromBase64String($b64))"

if not exist "%TEMP_CER%" (
    echo [오류] 인증서 파일 생성에 실패했습니다.
    pause
    exit /b 1
)

:: 3. Root 및 TrustedPeople 에 완벽 무인 등록
echo [2/2] 윈도우 신뢰할 수 있는 루트 및 배포자 저장소에 등록 중...
powershell -NoProfile -Command ^
  "Import-Certificate -FilePath '%TEMP_CER%' -CertStoreLocation 'Cert:\LocalMachine\Root' | Out-Null;" ^
  "Import-Certificate -FilePath '%TEMP_CER%' -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople' | Out-Null;" ^
  "Import-Certificate -FilePath '%TEMP_CER%' -CertStoreLocation 'Cert:\CurrentUser\TrustedPeople' | Out-Null;"

if exist "%TEMP_CER%" del /f /q "%TEMP_CER%" >nul 2>&1

:: 4. 등록 검증
powershell -NoProfile -Command ^
  "$c = Get-ChildItem Cert:\LocalMachine\Root | Where-Object { $_.Thumbprint -eq '69AF4CC96F4A48F88CEE359F0BA0555A0B06E361' };" ^
  "if ($c) { exit 0 } else { exit 1 }"

if %errorlevel% equ 0 (
    echo.
    echo ========================================================
    echo  [성공] Boardest 영구 인증서가 완벽히 등록되었습니다!
    echo.
    echo  - 유효기간: 2999년 12월 31일까지 평생 유효
    echo  - 저장소: 로컬 컴퓨터 Root 및 TrustedPeople 등록 완료
    echo.
    echo  이제 .appinstaller 또는 .appx 파일을 실행하시면
    echo  0x800B0109 오류 없이 바로 설치창이 뜹니다.
    echo ========================================================
) else (
    echo.
    echo ========================================================
    echo  [경고] 자동 등록 확인 중 오류가 발생했습니다.
    echo ========================================================
)

echo.
pause
