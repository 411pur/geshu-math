@echo off
chcp 936 >nul
title 格数至理 - 缓存清理
cd /d "%~dp0"

if not exist "%~dp0tool\clear_cache.ps1" (
    echo [!] 未找到 tool\clear_cache.ps1，请确认脚本完整。
    pause
    exit /b 1
)

where powershell >nul 2>nul
if errorlevel 1 (
    echo [!] 未找到 PowerShell，无法清理缓存。
    pause
    exit /b 1
)

echo.
echo   将清理：项目构建缓存 build/ .dart_tool/、Chrome 与 Edge 的 Service Worker 与 HTTP 缓存。
echo   不会清理：错题本、成绩、学生画像（存在浏览器 localStorage）。
echo   参数可透传，例如：清理缓存.bat -DryRun / -NoRestart
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\clear_cache.ps1" %*

echo.
pause
