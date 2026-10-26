@echo off
chcp 65001 >nul
title Boardest 영구 인증서 원클릭 자동 설치

:: 1. 관리자 권한 확인 및 자동 승격 (UAC)
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [Boardest Installer] 관리자 권한이 필요합니다. UAC 승격 창에서 '예'를 눌러주세요...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

echo ========================================================
echo   Boardest 영구 인증서 (만료일: 2999-12-31) 설치 중...
echo ========================================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$b64 = 'MIIC8jCCAdqgAwIBAgIQRxUMwz00P7ZGR1hIM7A28TANBgkqhkiG9w0BAQsFADAQMQ4wDAYDVQQDDAVqaXdobzAgFw0yNjA5MDQxMTI5NDhaGA8yOTk5MTIzMTE0NTk1OVowEDEOMAwGA1UEAwwFaml3aG8wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCzxVnksBunAyUZ/K24xIM1XMWwXi6TvS2Kc3IRuZqJm5HMnZZnBl3X7UF22oeOTIs7Z/bWphD685HRSL0qOBAA3sV9tWjrh6CRUl3ChjlnNXSNBTiFrRboZlwZkOqcxmQVNvmKXqlfvI1OGH0Q6bXg2CmX5Za+mD6HfCtp85voa2c3AIEllQTU3IFX7OnrfQ1djDI0CFcX+Gs9yan7RBc+FA2CVNi6/UKZP1FPnu3lUmba9R8IyGE9g7MtkgvUa2zVSZ5+8s1cW05gZJ2w6iPQfYAeAZnmXEqdngnjRmWGGohs9OgO2a4XEEMgcEElNY1LtHRO7MSnGBgnqO+Px1htAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQUVApFzZbru8xFagw5cKZbZxzrbCIwDQYJKoZIhvcNAQELBQADggEBAFq2UqnO223ngalT8VEs0r+L5Omko73xA9TipS61LGLuH0xKTsluTQ44vgJNGHvZg9Qi+BBgoRYGCiC+Nzm8R3fvBA3t7dBaZiaRBbzPe83KaqbF7BJffW+8XYf4AmT+X608y9TSwxfyZsXzpaR7pzSAf4DzWyUnLeODFch4wTEdldoOPbm/lmRmlhoR10t4J+cHMG8Fo5qSSCe+5pkYo1QrJ7LZFYjfwihINeNNMM721YSC08UKXM2Xo+Cm4Ra7K5JnJCeWogewyLY23UMBiDQ4mPxEmwfcxGSmZU8mVv+w4d5pnT2px4xQ2ngTmZwsjkRovzjozrTJ3hsKavlk4KA=';" ^
    "$cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new([Convert]::FromBase64String($b64));" ^
    "$store1 = [System.Security.Cryptography.X509Certificates.X509Store]::new('Root', 'LocalMachine'); $store1.Open('ReadWrite'); $store1.Add($cert); $store1.Close();" ^
    "$store2 = [System.Security.Cryptography.X509Certificates.X509Store]::new('TrustedPeople', 'LocalMachine'); $store2.Open('ReadWrite'); $store2.Add($cert); $store2.Close();" ^
    "$store3 = [System.Security.Cryptography.X509Certificates.X509Store]::new('TrustedPeople', 'CurrentUser'); $store3.Open('ReadWrite'); $store3.Add($cert); $store3.Close();" ^
    "Write-Host '  [성공] 로컬 컴퓨터 Root 및 TrustedPeople 저장소에 등록 완료!' -ForegroundColor Green;"

echo.
echo ========================================================
echo   Boardest 영구 인증서가 성공적으로 등록되었습니다!
echo   이제 boardest.appx 를 실행하여 설치/업데이트하세요.
echo ========================================================
echo.
pause
