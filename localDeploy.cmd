@echo off
rem Runs localDeploy.ps1 (copies the addon into ..\AddOns\Circlet). Double-click it or run it
rem from a command prompt; any arguments go to the PowerShell script (e.g. -WhatIf).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0localDeploy.ps1" %*
if errorlevel 1 pause
