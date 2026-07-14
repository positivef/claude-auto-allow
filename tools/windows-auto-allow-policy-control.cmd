@echo off
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File "%~dp0windows-auto-allow-policy-control.ps1" %*
