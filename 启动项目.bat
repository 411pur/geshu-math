@echo off
cd /d "%~dp0"
node tool/start.mjs
if errorlevel 1 pause
