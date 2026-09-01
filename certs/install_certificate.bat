@echo off
:: Boardest Certificate Installer
:: Run as Administrator to install Boardest certificate into TrustedPeople store
title Boardest Certificate Installer
echo ==============================================
echo   Boardest Certificate Installer for Windows
echo ==============================================
echo.

set "SCRIPT_DIR=%~dp0"
set "CERT_FILE=%SCRIPT_DIR%BoardestCert.cer"

if not exist "%CERT_FILE%" (
    echo [ERROR] BoardestCert.cer not found in %SCRIPT_DIR%!
    pause
    exit /b 1
)

echo Requesting Administrator privileges if needed...
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Elevating to Administrator...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b 0
)

echo Installing BoardestCert.cer to TrustedPeople store...
certutil -addstore -f "TrustedPeople" "%CERT_FILE%"

if %errorLevel% equ 0 (
    echo.
    echo [SUCCESS] Boardest certificate installed successfully!
    echo You can now install .appx and .appinstaller packages.
) else (
    echo.
    echo [FAIL] Failed to install certificate. Error: %errorLevel%
)

echo.
pause
