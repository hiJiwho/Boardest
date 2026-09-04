@echo off
:: ========================================================
::  Boardest Self-Contained Certificate Installer
::  (인증서가 내장되어 있어 별도의 .cer 다운로드가 필요 없습니다)
:: ========================================================
title Boardest Certificate Installer
setlocal enabledelayedexpansion

echo ========================================================
echo   Boardest One-Click Certificate Installer for Windows
echo ========================================================
echo.

:: 1. 관리자 권한 확인 및 자동 승격
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] Requesting Administrator privileges...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b 0
)

echo [1/3] Extracting embedded Boardest certificate...
set "TEMP_B64=%TEMP%\BoardestCert_%RANDOM%.b64"
set "TEMP_CER=%TEMP%\BoardestCert_%RANDOM%.cer"

(
echo -----BEGIN CERTIFICATE-----
echo MIIC8jCCAdqgAwIBAgIQRxUMwz00P7ZGR1hIM7A28TANBgkqhkiG9w0BAQsFADAQMQ4wDAYDVQQD
echo DAVqaXdobzAgFw0yNjA5MDQxMTI5NDhaGA8yOTk5MTIzMTE0NTk1OVowEDEOMAwGA1UEAwwFaml3
echo aG8wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCzxVnksBunAyUZ/K24xIM1XMWwXi6T
echo vS2Kc3IRuZqJm5HMnZZnBl3X7UF22oeOTIs7Z/bWphD685HRSL0qOBAA3sV9tWjrh6CRUl3Chjln
echo NXSNBTiFrRboZlwZkOqcxmQVNvmKXqlfvI1OGH0Q6bXg2CmX5Za+mD6HfCtp85voa2c3AIEllQTU
echo 3IFX7OnrfQ1djDI0CFcX+Gs9yan7RBc+FA2CVNi6/UKZP1FPnu3lUmba9R8IyGE9g7MtkgvUa2zV
echo SZ5+8s1cW05gZJ2w6iPQfYAeAZnmXEqdngnjRmWGGohs9OgO2a4XEEMgcEElNY1LtHRO7MSnGBgn
echo qO+Px1htAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzAdBgNV
echo HQ4EFgQUVApFzZbru8xFagw5cKZbZxzrbCIwDQYJKoZIhvcNAQELBQADggEBAFq2UqnO223ngalT
echo 8VEs0r+L5Omko73xA9TipS61LGLuH0xKTsluTQ44vgJNGHvZg9Qi+BBgoRYGCiC+Nzm8R3fvBA3t
echo 7dBaZiaRBbzPe83KaqbF7BJffW+8XYf4AmT+X608y9TSwxfyZsXzpaR7pzSAf4DzWyUnLeODFch4
echo wTEdldoOPbm/lmRmlhoR10t4J+cHMG8Fo5qSSCe+5pkYo1QrJ7LZFYjfwihINeNNMM721YSC08UK
echo XM2Xo+Cm4Ra7K5JnJCeWogewyLY23UMBiDQ4mPxEmwfcxGSmZU8mVv+w4d5pnT2px4xQ2ngTmZws
echo jkRovzjozrTJ3hsKavlk4KA=
echo -----END CERTIFICATE-----
) > "%TEMP_B64%"

echo [2/3] Decoding certificate...
certutil -decode "%TEMP_B64%" "%TEMP_CER%" >nul 2>&1
if not exist "%TEMP_CER%" (
    copy "%TEMP_B64%" "%TEMP_CER%" >nul 2>&1
)

echo [3/3] Registering certificate into Root and TrustedPeople stores...
certutil -addstore -f "Root" "%TEMP_CER%"
certutil -addstore -f "TrustedPeople" "%TEMP_CER%"

if %errorLevel% equ 0 (
    echo.
    echo ========================================================
    echo  [SUCCESS] Boardest certificate successfully installed!
    echo  Now you can install and run .appinstaller and .appx apps!
    echo ========================================================
) else (
    echo.
    echo [ERROR] Failed to register certificate. Error code: %errorLevel%
)

:: 정리
if exist "%TEMP_B64%" del /f /q "%TEMP_B64%" >nul 2>&1
if exist "%TEMP_CER%" del /f /q "%TEMP_CER%" >nul 2>&1

echo.
pause
