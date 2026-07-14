# Claude Auto Allow

Windows helpers for automatically accepting routine Claude Code / Claude and
GitHub Copilot permission prompts.

## Ownership And License

Copyright (c) 2026 positivef. All rights reserved.

`positivef` is the public rights-holder and creator-account identifier for this
release. Authorship and provenance should be verified against the original
GitHub account, repository history, commit timestamps, pushed commit hashes, and
release artifacts for `positivef/claude-auto-allow`.

This repository is public for inspection, but it is not open source. No
permission is granted to copy, modify, redistribute, repackage, sell, publish,
train AI systems on, or present this work as someone else's original work.

See [LICENSE.md](LICENSE.md), [NOTICE.md](NOTICE.md), and [SECURITY.md](SECURITY.md).

## Files

- `tools/claude-auto-allow-gui.exe`: GUI launcher with Start/Stop buttons and a log panel.
- `tools/claude-auto-allow.exe`: CLI launcher.
- `tools/claude-auto-allow.ps1`: UI Automation engine.
- `tools/claude-auto-allow.README.md`: usage, security model, and ownership details.
- `tools/copilot-auto-allow.exe`: Copilot CLI launcher.
- `tools/copilot-auto-allow.ps1`: Copilot UI Automation engine.
- `tools/copilot-auto-allow.README.md`: Copilot usage, security model, and ownership details.
- `SECURITY.md`: hardening notes and vulnerability reporting guidance.

## Security Model

This tool does not make automated approvals risk-free, and no software can be
made unhackable. The current build reduces common abuse and hijacking risks by:

- targeting Claude by process name and executable path by default
- targeting VS Code / Cursor by process name and executable path for Copilot
- rejecting custom target regex unless `-AllowCustomTarget` is explicit
- rejecting custom approval labels unless `-AllowCustomButtonText` is explicit
- blocking automatic clicks when prompt text contains sensitive terms such as
  secrets, production, deployment, destructive git/file/database actions, or
  payments
- resolving the PowerShell engine script only from the executable directory
- rejecting symbolic link / reparse point script substitution
- using `RemoteSigned` PowerShell execution policy instead of `Bypass`

## Run

Double-click:

```bat
tools\claude-auto-allow-gui.exe
```

The GUI starts monitoring automatically. Use `Stop` to pause it and `Start` to
resume. Click events and diagnostics are shown in the log area. Use the `Prefer`
dropdown to choose whether `Always allow` or `Allow once` should win when both
buttons are present.

For console mode:

```bat
tools\claude-auto-allow.exe
```

Dry-run:

```bat
tools\claude-auto-allow.exe -DryRun -Diagnostic
```

To prefer one-time approval in console mode:

```bat
tools\claude-auto-allow.exe -Prefer Once
```

The Claude tool targets trusted Claude windows and clicks matching approval
buttons exposed through Windows UI Automation.

Copilot console mode:

```bat
tools\copilot-auto-allow.exe
```

Copilot dry-run:

```bat
tools\copilot-auto-allow.exe -DryRun
```
