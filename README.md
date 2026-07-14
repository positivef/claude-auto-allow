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

- `windows-claude-cli-auto-wrapper.exe`: Windows CLI wrapper. Starts a new Claude Code session in the current terminal folder.
- `windows-claude-cli-auto-folder-picker.exe`: Windows click launcher. Asks for a project folder, then starts the CLI wrapper there.
- `macos-claude-cli-auto-wrapper`: macOS CLI wrapper. Starts a new Claude Code session with `--permission-mode auto`.
- `windows-claude-desktop-click-auto-allow-*`: Windows desktop-click tool for visible Claude approval prompts.
- `windows-copilot-desktop-click-auto-allow-*`: Windows desktop-click tool for visible Copilot approval prompts.

If the file name says `cli-auto-wrapper`, it launches Claude Code in the current
working folder.
If the file name says `cli-auto-folder-picker`, it opens a folder picker first,
then launches the CLI wrapper in the selected project folder.
If the file name says `desktop-click-auto-allow`, it watches and clicks visible
approval buttons.

## Live Approval Policy

`tools/auto-allow-policy.json` stores two separate settings:

- desktop-click auto-allow behavior for visible Windows approval prompts
- CLI wrapper behavior for new Claude Code sessions

Desktop-click modes are mutually exclusive. In the GUI they are shown as radio
buttons:

- `PolicyAsk`: auto-click routine approval prompts, but ask before approving
  prompts that contain sensitive terms such as secrets, production, deployment,
  destructive actions, payments, or billing. This is the default.
- `PolicyBlock`: auto-click routine approval prompts, but block sensitive
  prompts without asking.
- `AlwaysAllow`: click known approval buttons in trusted target windows even
  when sensitive terms are detected. This still keeps process, path, and button
  label checks.
- `Disabled`: do not click anything.

Windows desktop-click tools read this policy while they are running. Changing it
through the GUI or policy control command is applied on the next scan loop
without restarting the watcher.

CLI wrapper mode is binary:

- `Auto`: inject `--permission-mode auto` when launching a new Claude Code
  session, unless the user supplied a permission option manually.
- `Manual`: do not inject a permission option; Claude Code asks according to its
  own defaults.

CLI wrapper mode is used only when starting a new wrapper session. A running
Claude Code CLI process cannot have its internal `--permission-mode` changed by
this tool after launch.

Live policy commands:

```bat
tools\windows-auto-allow-policy-control.cmd -Mode PolicyAsk
tools\windows-auto-allow-policy-control.cmd -Mode AlwaysAllow
tools\windows-auto-allow-policy-control.cmd -Mode PolicyBlock
tools\windows-auto-allow-policy-control.cmd -Mode Disabled
tools\windows-auto-allow-policy-control.cmd -Prefer Once
tools\windows-auto-allow-policy-control.cmd -CliPermissionMode Auto
tools\windows-auto-allow-policy-control.cmd -CliPermissionMode Manual
tools\windows-auto-allow-policy-control.cmd -CliAuto On
tools\windows-auto-allow-policy-control.cmd -CliAuto Off
tools\windows-auto-allow-policy-control.cmd -DryRun On
tools\windows-auto-allow-policy-control.cmd -DryRun Off
```

## Files

CLI wrappers:

- `tools/windows-claude-cli-auto-wrapper.exe`: Windows Claude Code CLI wrapper.
- `tools/windows-claude-cli-auto-wrapper.cmd`: Windows cmd convenience launcher.
- `tools/windows-claude-cli-auto-wrapper-app/Program.cs`: Windows CLI wrapper source.
- `tools/windows-claude-cli-auto-folder-picker.exe`: Windows folder picker launcher for the CLI wrapper.
- `tools/windows-claude-cli-auto-folder-picker.cmd`: Windows cmd convenience launcher for the folder picker.
- `tools/windows-claude-cli-auto-folder-picker-app/Program.cs`: Windows folder picker source.
- `tools/macos/macos-claude-cli-auto-wrapper`: macOS Claude Code CLI wrapper.
- `tools/macos/macos-claude-cli-auto-folder-picker.command`: macOS folder picker launcher for the CLI wrapper.
- `tools/macos/install-macos-claude-cli-auto-wrapper.sh`: macOS installer for the CLI wrapper.
- `tools/macos/README.md`: macOS CLI wrapper usage.

Windows desktop-click tools:

- `tools/auto-allow-policy.json`: live policy shared by Windows desktop-click tools and CLI wrappers.
- `tools/windows-auto-allow-policy-control.cmd`: Windows cmd policy changer.
- `tools/windows-auto-allow-policy-control.ps1`: Windows PowerShell policy changer.
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
Claude CLI | Project=Playground | Mode=AUTO | Topic=fix build error
```

macOS title example:

```text
Claude CLI | Project=my-project | Mode=MANUAL | Topic=interactive session
```

The banner includes:

- project folder name
- full project path
- status, currently `launching Claude Code under wrapper`
- topic, from command arguments or `interactive session`
- topic source, either `command arguments`, `CLAUDE_AUTO_ALLOW_TOPIC`, or `default`
- whether the CLI policy is `Auto` or `Manual`
- whether `--permission-mode auto` was injected
- policy file path, if found
- provenance marker

For interactive sessions where there is no initial prompt argument, set a custom
window topic before launching:

```bat
set CLAUDE_AUTO_ALLOW_TOPIC=payment API refactor
tools\windows-claude-cli-auto-wrapper.exe
```

```sh
CLAUDE_AUTO_ALLOW_TOPIC="payment API refactor" tools/macos/macos-claude-cli-auto-wrapper
```

The wrapper can show the launch topic and wrapper mode, but it cannot read
Claude Code's live internal progress after Claude has started.

## Security Model

This tool does not make automated approvals risk-free, and no software can be
made unhackable. The current build reduces common abuse and hijacking risks by:

- using Claude Code's built-in `--permission-mode auto` for CLI wrappers when
  CLI policy is `Auto`
- targeting Claude by process name and executable path for Windows desktop-click mode
- targeting VS Code / Cursor by process name and executable path for Copilot desktop-click mode
- rejecting custom target regex unless `-AllowCustomTarget` is explicit
- rejecting custom approval labels unless `-AllowCustomButtonText` is explicit
- applying the live policy when prompt text contains sensitive terms such as
  secrets, production, deployment, destructive git/file/database actions, or
  payments; default `PolicyAsk` requires user confirmation for those prompts
- resolving the PowerShell engine script only from the executable directory
- rejecting symbolic link / reparse point script substitution
- using `RemoteSigned` PowerShell execution policy instead of `Bypass`

## Run

Windows CLI wrapper:

```bat
cd /d C:\path\to\project
tools\windows-claude-cli-auto-wrapper.exe "fix build error"
```

Windows CLI folder picker:

```bat
tools\windows-claude-cli-auto-folder-picker.exe
```

Double-click `tools\windows-claude-cli-auto-folder-picker.exe` when you want a
Windows folder picker with an address bar. After you choose a project folder, it
opens `cmd.exe` in that folder and runs `windows-claude-cli-auto-wrapper.exe`.

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
