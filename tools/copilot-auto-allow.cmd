@echo off
if exist "%~dp0copilot-auto-allow.exe" (
  "%~dp0copilot-auto-allow.exe" %*
) else (
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "%~dp0copilot-auto-allow.ps1" %*
)
