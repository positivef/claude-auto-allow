@echo off
if exist "%~dp0windows-claude-desktop-click-auto-allow-console.exe" (
  "%~dp0windows-claude-desktop-click-auto-allow-console.exe" %*
) else (
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "%~dp0windows-claude-desktop-click-auto-allow.ps1" %*
)
