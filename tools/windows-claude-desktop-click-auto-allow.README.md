# Windows Claude Desktop Click Auto Allow

Windows desktop-click helper for visible Claude Code / Claude permission
prompts.

This is not a CLI wrapper. It watches trusted Claude windows and clicks known
approval buttons such as `Always allow` or `Allow once` after safety checks.

## Files

- `windows-claude-desktop-click-auto-allow-gui.exe`: desktop-click GUI launcher.
- `windows-claude-desktop-click-auto-allow-console.exe`: desktop-click console launcher.
- `windows-claude-desktop-click-auto-allow.ps1`: Windows UI Automation engine.
- `windows-claude-desktop-click-auto-allow.cmd`: cmd convenience launcher.

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
- strict default executable path check for Claude installations
- known approval button labels only
- custom target regex blocked unless `-AllowCustomTarget` is provided
- custom button labels blocked unless `-AllowCustomButtonText` is provided
- sensitive prompt text guard for secrets, production, deletion, publishing,
  payments, and similar high-impact actions
- sibling script resolution from the executable directory only
- symbolic link / reparse point rejection for the PowerShell engine script
- `RemoteSigned` PowerShell execution policy instead of `Bypass`
- dry-run and diagnostic modes for verification before use

If a prompt contains sensitive terms, the tool logs a block and does not click.
To override that for a specific trusted run, use `-AllowSensitivePrompt`.

## Run

GUI desktop-click mode:

```bat
tools\windows-claude-desktop-click-auto-allow-gui.exe
```

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
