# Claude Auto Allow

Windows helper for automatically accepting Claude Desktop permission prompts.

## Ownership And License

Copyright (c) 2026 positivef. All rights reserved.

This repository is public for inspection, but it is not open source. No
permission is granted to copy, modify, redistribute, repackage, sell, publish,
train AI systems on, or present this work as someone else's original work.

See [LICENSE.md](LICENSE.md) and [NOTICE.md](NOTICE.md).

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
Use the `Prefer` dropdown to choose whether `Always allow` or `Allow once` should win when both buttons are present.

For console mode:

```bat
tools\claude-auto-allow.exe
```

To prefer one-time approval in console mode:

```bat
tools\claude-auto-allow.exe -Prefer Once
```

The tool targets `claude.exe` and clicks matching `Always allow`, `항상 허용`, `Allow once`, or `한 번만 허용` buttons exposed through Windows UI Automation.
