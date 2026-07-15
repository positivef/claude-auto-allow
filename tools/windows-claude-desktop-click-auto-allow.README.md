# Windows Claude Desktop Click Auto Allow

Windows desktop-click helper for visible Claude Code / Claude permission
prompts.

This is not a CLI wrapper. It watches trusted Claude windows and clicks known
approval buttons such as `Always allow`, `Allow once`, or `Allow` after safety
checks.

## Files

- `windows-claude-desktop-click-auto-allow-gui.exe`: desktop-click GUI launcher.
- `windows-claude-desktop-click-auto-allow-console.exe`: desktop-click console launcher.
- `windows-claude-desktop-click-auto-allow.ps1`: Windows UI Automation engine.
- `windows-claude-desktop-click-auto-allow.cmd`: cmd convenience launcher.
- `auto-allow-policy.json`: live policy read by the watcher while it runs. It
  also stores the CLI wrapper `cliPermissionMode`.
- `windows-auto-allow-policy-control.cmd`: cmd policy changer.

## Ownership

Copyright (c) 2026 positivef. All rights reserved.

`positivef` is the public rights-holder and creator-account identifier for this
release. Provenance should be verified against:

- GitHub account: `positivef`
- Repository: `https://github.com/positivef/claude-auto-allow`
- Commit timestamps and pushed commit hashes
- Release artifacts and file hashes
- Provenance marker: `CAA-POSITIVEF-2026-07`

This repository is public for inspection, but it is not open source. No
permission is granted to copy, modify, redistribute, repackage, sell, publish,
train AI systems on, or present this work as someone else's original work.

## Security Model

This tool cannot make automated approval risk-free, and no tool can be made
"unhackable." The current build reduces common attack and mis-click risks with:

- strict default target process name: `claude`
- strict default executable path check for Claude installations, including npm
  Claude Code, Claude Desktop / Windows Store, and Claude Desktop-bundled
  Claude Code paths
- known approval button labels only
- custom target regex blocked unless `-AllowCustomTarget` is provided
- custom button labels blocked unless `-AllowCustomButtonText` is provided
- live policy for sensitive prompt text such as secrets, production, deletion,
  publishing, payments, and similar high-impact actions
- sibling script resolution from the executable directory only
- symbolic link / reparse point rejection for the PowerShell engine script
- `RemoteSigned` PowerShell execution policy instead of `Bypass`
- dry-run and diagnostic modes for verification before use

The default desktop-click live policy is `PolicyAsk`: routine approval prompts
are clicked, but prompts containing sensitive terms require a Windows
confirmation dialog. The four desktop modes are mutually exclusive and are shown
as radio buttons in the GUI, not checkboxes. Selecting more than one would create
conflicting behavior. Use `PolicyBlock` to block those prompts without asking,
`AlwaysAllow` to click known approval buttons even when sensitive terms are
detected, or `Disabled` to stop all automatic clicks.

The live policy is read from `auto-allow-policy.json` on each scan loop. Change
it while the watcher is running:

```bat
tools\windows-auto-allow-policy-control.cmd -Mode PolicyAsk
tools\windows-auto-allow-policy-control.cmd -Mode AlwaysAllow
tools\windows-auto-allow-policy-control.cmd -Mode PolicyBlock
tools\windows-auto-allow-policy-control.cmd -Mode Disabled
tools\windows-auto-allow-policy-control.cmd -CliPermissionMode Auto
tools\windows-auto-allow-policy-control.cmd -CliPermissionMode Manual
```

The older command-line override still works for a trusted run:
`-AllowSensitivePrompt`.

## Run

GUI desktop-click mode:

```bat
tools\windows-claude-desktop-click-auto-allow-gui.exe
```

## GUI Button And Control Guide

The GUI starts with the current values from `auto-allow-policy.json`. Most
controls are saved immediately. If the watcher is already running, policy
changes apply on the next scan loop.

Primary buttons:

- `Start`: starts the desktop-click watcher. Use this after choosing the desired
  mode and options. If it is already running, the GUI keeps the existing worker.
- `Stop`: stops only this auto-click watcher. It does not close Claude Code,
  Claude Desktop, terminals, editors, or any project process.
- `Clear Log`: clears the visible GUI log text only. It does not change policy,
  stop the watcher, or delete files.

Desktop mode radio buttons:

- `Ask`: routine known approval buttons are clicked automatically, but prompts
  containing sensitive terms open a Windows confirmation dialog first. This is
  the recommended default for normal use.
- `Block`: routine known approval buttons are clicked automatically, but
  sensitive prompts are not approved and no confirmation dialog is shown.
- `Always`: known approval buttons in trusted Claude windows are clicked even
  when sensitive terms are detected. Use only when you deliberately want the
  least interruption in a trusted local workflow.
- `Disabled`: no buttons are clicked. Use this to pause automation without
  closing the GUI.

The four desktop modes are radio buttons because only one can be active at a
time. They should not be selected together.

Other controls:

- `Prefer`: chooses which approval button type is preferred when more than one
  valid approval button is visible.
- `Prefer: Always`: prefer persistent approval buttons such as `Always allow`
  when available.
- `Prefer: Once`: prefer one-time approval buttons such as `Allow once` when
  available.
- `CLI auto mode`: controls the separate CLI wrapper behavior. When checked,
  new Claude Code sessions launched through the CLI wrapper receive
  `--permission-mode auto` unless the user supplied a permission option
  manually. It does not change an already-running Claude Code CLI process.
- `Dry run`: logs what would be clicked, but does not click. Turn this on for
  first-time testing or troubleshooting.
- `Diagnostic`: writes more detailed matching and policy information to the log.
  Use this when the watcher does not find a button you expected it to find.

Status and log area:

- `Running`: the watcher worker is active.
- `Stopped`: the watcher worker is not active.
- The log area shows startup messages, policy changes, detected approvals,
  dry-run messages, diagnostic details, and worker exit messages.

Common setups:

- First test: `Ask`, `Prefer: Always`, `Dry run` on, `Diagnostic` on, then
  press `Start`.
- Normal use: `Ask`, `Prefer: Always`, `CLI auto mode` on, `Dry run` off,
  `Diagnostic` off.
- Maximum interruption reduction: `Always`, `Prefer: Always`, `Dry run` off.
- Temporary pause: choose `Disabled` or press `Stop`.

Console desktop-click mode:

```bat
tools\windows-claude-desktop-click-auto-allow-console.exe
```

Dry-run:

```bat
tools\windows-claude-desktop-click-auto-allow-console.exe -DryRun -Diagnostic
```

Prefer one-time approval:

```bat
tools\windows-claude-desktop-click-auto-allow-console.exe -Prefer Once
```

Run once and exit:

```bat
tools\windows-claude-desktop-click-auto-allow-console.exe -Once
```

## Advanced Use

Changing the target app now requires explicit opt-in:

```bat
tools\windows-claude-desktop-click-auto-allow-console.exe -AllowCustomTarget -WindowTitleRegex "claude|code" -ProcessNameRegex "claude|code" -TargetPathRegex ""
```

Changing approval button labels now requires explicit opt-in:

```bat
tools\windows-claude-desktop-click-auto-allow-console.exe -AllowCustomButtonText -ButtonText "Always allow,Allow once"
```

Disabling sensitive prompt blocking requires explicit opt-in:

```bat
tools\windows-claude-desktop-click-auto-allow-console.exe -AllowSensitivePrompt
```

Use these overrides only in trusted local environments.
