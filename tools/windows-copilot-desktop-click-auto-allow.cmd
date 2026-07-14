@echo off
if exist "%~dp0windows-copilot-desktop-click-auto-allow-console.exe" (
  "%~dp0windows-copilot-desktop-click-auto-allow-console.exe" %*
) else (
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "%~dp0windows-copilot-desktop-click-auto-allow.ps1" %*
)
