@echo off
chcp 65001 >nul
title Boardest Certificate Installer
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_certificate.ps1"
