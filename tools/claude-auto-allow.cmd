@echo off
if exist "%~dp0claude-auto-allow.exe" (
  "%~dp0claude-auto-allow.exe" %*
) else (
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "%~dp0claude-auto-allow.ps1" %*
)
