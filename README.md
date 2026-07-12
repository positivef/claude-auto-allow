# Claude Auto Allow

Windows helper for automatically accepting Claude Desktop permission prompts.

## Files

- `tools/claude-auto-allow-gui.exe`: GUI launcher with Start/Stop buttons and a log panel.
- `tools/claude-auto-allow.exe`: CLI launcher.
- `tools/claude-auto-allow.ps1`: UI Automation engine.

## Run

Double-click:

```bat
tools\claude-auto-allow-gui.exe
```

The GUI starts monitoring automatically. Use `Stop` to pause it and `Start` to resume. Click events and diagnostics are shown in the log area.

For console mode:

```bat
tools\claude-auto-allow.exe
```

The tool targets `claude.exe` and clicks matching `Always allow`, `항상 허용`, `Allow once`, or `한 번만 허용` buttons exposed through Windows UI Automation.
