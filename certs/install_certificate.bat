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
echo MIIC8DCCAdigAwIBAgIQFH4BkaCci41LdIKoHhk2dTANBgkqhkiG9w0BAQsFADAQMQ4wDAYDVQQD
echo DAVqaXdobzAeFw0yNjA5MDExMDQwMTJaFw0zMTA5MDExMDUwMTJaMBAxDjAMBgNVBAMMBWppd2hv
echo MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuMmxZrFIL4OcdQhCTFV1vvW8e1E1ELpt
echo 2/nbur4SvzFCN573CD0jNGNKv+VhUTCpDKc0RWJ/SH4htkhSG1m8+UX8YpxF/p5QI9QQ//l9t7NM
echo CDE0Vm2eK/iuNqq0n22zbHBaw3Uhieb5a/DC9djaM1pJCbXLuUk/sIitXTqjta65ruhR3WDL6RJr
echo BYqbJUQa99TYcY3k0LvUtUQsuLnIU1Kp+s++iedyzsauDyRFmTyZAeatgayWgQ380qlzu64oYzw8
echo B+DEBFvbEe/9tz5TKWXPChTpEsBnkVRit8g0iGlNObtjvfvWHiFr+Z4xy31Dwrg2ZjL+IWbw49VM
echo A4uFeQIDAQABo0YwRDAOBgNVHQ8BAf8EBAMCB4AwEwYDVR0lBAwwCgYIKwYBBQUHAwMwHQYDVR0O
echo BBYEFL6JxDzht+qVP9f3MwiCWhaqy9/tMA0GCSqGSIb3DQEBCwUAA4IBAQCKL4ys4bGtMlPbdCHx
echo 2BKHnj8KspEjM66BkW8NtDNC8a1Y9a3ieIhwYuS7p9ZLtc1q/snUUt2hjd20hBvWHwVA7kFzPsgg
echo GvQScgrPvBLLOX2Mxp6x1KtiRksM2fkd6/eQ8E6doEYneLLr4QhOMja++S9z4zfG+nfDTif4J0wF
echo Z8Cp1cSi8wrPulGc6Wxq8oMiq/q8TbseqK1p4WrXirOT8FSVAizR69pEKUPb8zKaOB6scFWnT78D
echo DAQJl0PenfbbVuY1CXRpU4/NfFBxj6w6or2nbpT0Ncrx/G73GKTn0I3BN+zvcNTrIvTjGiQds3io
echo xMSwqVwK2IrbtXbZX5MD
echo -----END CERTIFICATE-----
) > "%TEMP_B64%"

echo [2/3] Decoding certificate...
certutil -decode "%TEMP_B64%" "%TEMP_CER%" >nul 2>&1
if not exist "%TEMP_CER%" (
    copy "%TEMP_B64%" "%TEMP_CER%" >nul 2>&1
)

echo [3/3] Registering certificate into TrustedPeople store...
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
