@echo off
cd /d "%~dp0.."
echo UNIQ release AAB - surum pubspec.yaml icinden okunur
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-release.ps1"
if errorlevel 1 pause
