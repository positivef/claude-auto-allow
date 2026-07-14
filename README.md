# Claude Auto Allow

Helpers for reducing routine Claude Code / Claude and GitHub Copilot permission
prompts.

There are two different concepts in this repository:

- **CLI wrapper**: starts Claude Code with `--permission-mode auto`. It does not
  click buttons and only affects new sessions launched through the wrapper.
- **Desktop click auto-allow**: watches visible Windows approval dialogs and
  clicks known approval buttons after safety checks.

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

## File Name Guide

File names intentionally include the operating system and behavior:

- `windows-claude-cli-auto-wrapper.exe`: Windows CLI wrapper. Starts a new Claude Code session with `--permission-mode auto`.
- `macos-claude-cli-auto-wrapper`: macOS CLI wrapper. Starts a new Claude Code session with `--permission-mode auto`.
- `windows-claude-desktop-click-auto-allow-*`: Windows desktop-click tool for visible Claude approval prompts.
- `windows-copilot-desktop-click-auto-allow-*`: Windows desktop-click tool for visible Copilot approval prompts.

If the file name says `cli-auto-wrapper`, it launches Claude Code.
If the file name says `desktop-click-auto-allow`, it watches and clicks visible
approval buttons.

## Files

CLI wrappers:

- `tools/windows-claude-cli-auto-wrapper.exe`: Windows Claude Code CLI wrapper.
- `tools/windows-claude-cli-auto-wrapper.cmd`: Windows cmd convenience launcher.
- `tools/windows-claude-cli-auto-wrapper-app/Program.cs`: Windows CLI wrapper source.
- `tools/macos/macos-claude-cli-auto-wrapper`: macOS Claude Code CLI wrapper.
- `tools/macos/macos-claude-cli-auto-folder-picker.command`: macOS folder picker launcher for the CLI wrapper.
- `tools/macos/install-macos-claude-cli-auto-wrapper.sh`: macOS installer for the CLI wrapper.
- `tools/macos/README.md`: macOS CLI wrapper usage.

Windows desktop-click tools:

- `tools/windows-claude-desktop-click-auto-allow-gui.exe`: Windows Claude desktop-click GUI.
- `tools/windows-claude-desktop-click-auto-allow-console.exe`: Windows Claude desktop-click console launcher.
- `tools/windows-claude-desktop-click-auto-allow.ps1`: Windows Claude UI Automation engine.
- `tools/windows-claude-desktop-click-auto-allow.README.md`: Windows Claude desktop-click usage and security model.
- `tools/windows-copilot-desktop-click-auto-allow-console.exe`: Windows Copilot desktop-click console launcher.
- `tools/windows-copilot-desktop-click-auto-allow.ps1`: Windows Copilot UI Automation engine.
- `tools/windows-copilot-desktop-click-auto-allow.README.md`: Windows Copilot desktop-click usage and security model.
- `SECURITY.md`: hardening notes and vulnerability reporting guidance.

## CLI Wrapper Display

The CLI wrappers set the terminal title and print a startup banner so it is
clear that the wrapper is active.

Windows title example:

```text
[CLAUDE CLI WRAPPER][AUTO COMMAND ACCEPT] Playground | fix build error
```

macOS title example:

```text
[CLAUDE CLI WRAPPER][AUTO COMMAND ACCEPT] my-project | interactive session
```

The banner includes:

- project folder name
- full project path
- task summary, or `interactive session`
- whether `--permission-mode auto` was injected
- provenance marker

## Security Model

This tool does not make automated approvals risk-free, and no software can be
made unhackable. The current build reduces common abuse and hijacking risks by:

- using Claude Code's built-in `--permission-mode auto` for CLI wrappers
- targeting Claude by process name and executable path for Windows desktop-click mode
- targeting VS Code / Cursor by process name and executable path for Copilot desktop-click mode
- rejecting custom target regex unless `-AllowCustomTarget` is explicit
- rejecting custom approval labels unless `-AllowCustomButtonText` is explicit
- blocking automatic clicks when prompt text contains sensitive terms such as
  secrets, production, deployment, destructive git/file/database actions, or
  payments
- resolving the PowerShell engine script only from the executable directory
- rejecting symbolic link / reparse point script substitution
- using `RemoteSigned` PowerShell execution policy instead of `Bypass`

## Run

Windows CLI wrapper:

```bat
cd /d C:\path\to\project
tools\windows-claude-cli-auto-wrapper.exe "fix build error"
```

macOS CLI wrapper:

```sh
cd /path/to/project
tools/macos/macos-claude-cli-auto-wrapper "fix build error"
```

macOS folder picker installer:

```sh
cd tools/macos
chmod +x macos-claude-cli-auto-wrapper macos-claude-cli-auto-folder-picker.command install-macos-claude-cli-auto-wrapper.sh
./install-macos-claude-cli-auto-wrapper.sh
```

Windows Claude desktop-click GUI:

```bat
tools\windows-claude-desktop-click-auto-allow-gui.exe
```

Windows Claude desktop-click console:

```bat
tools\windows-claude-desktop-click-auto-allow-console.exe
```

Windows Claude desktop-click dry-run:

```bat
tools\windows-claude-desktop-click-auto-allow-console.exe -DryRun -Diagnostic
```

Windows Copilot desktop-click console:

```bat
tools\windows-copilot-desktop-click-auto-allow-console.exe
```

Windows Copilot desktop-click dry-run:

```bat
tools\windows-copilot-desktop-click-auto-allow-console.exe -DryRun
```
