# Copilot Auto Allow

Windows helper for GitHub Copilot permission prompts in VS Code / Cursor.

It watches trusted editor windows and clicks known approval buttons such as
`Allow`. It is intended for personal, trusted local workflows only.

## Ownership

Copyright (c) 2026 positivef. All rights reserved.

`positivef` is the public rights-holder and creator-account identifier for this
release. Provenance should be verified against:

- GitHub account: `positivef`
- Repository: `https://github.com/positivef/claude-auto-allow`
- Commit timestamps and pushed commit hashes
- Release artifacts and file hashes
- Provenance marker: `COPILOT-AA-POSITIVEF-2026-07`

This repository is public for inspection, but it is not open source. No
permission is granted to copy, modify, redistribute, repackage, sell, publish,
train AI systems on, or present this work as someone else's original work.

## Security Model

This tool cannot make automated approval risk-free, and no tool can be made
"unhackable." The current build reduces common attack and mis-click risks with:

- strict default target process names: `code` and `cursor`
- strict default executable path checks for VS Code / Cursor / VSCodium
- known approval button labels only
- custom target regex blocked unless `-AllowCustomTarget` is provided
- custom button labels blocked unless `-AllowCustomButtonText` is provided
- sensitive prompt text guard for secrets, production, deletion, publishing,
  payments, and similar high-impact actions
- sibling script resolution from the executable directory only
- symbolic link / reparse point rejection for the PowerShell engine script
- `RemoteSigned` PowerShell execution policy instead of `Bypass`
- dry-run mode for verification before use

If a prompt contains sensitive terms, the tool logs a block and does not click.
To override that for a specific trusted run, use `-AllowSensitivePrompt`.

## Run

Console mode:

```bat
tools\copilot-auto-allow.exe
```

Dry-run:

```bat
tools\copilot-auto-allow.exe -DryRun
```

Run once and exit:

```bat
tools\copilot-auto-allow.exe -Once
```

Disable mouse fallback:

```bat
tools\copilot-auto-allow.exe -NoMouseFallback
```

## Advanced Use

Changing the target app now requires explicit opt-in:

```bat
tools\copilot-auto-allow.exe -AllowCustomTarget -WindowTitleRegex "copilot|code" -ProcessNameRegex "code|cursor" -TargetPathRegex ""
```

Changing approval button labels now requires explicit opt-in:

```bat
tools\copilot-auto-allow.exe -AllowCustomButtonText -ButtonText "Allow,Continue"
```

Disabling sensitive prompt blocking requires explicit opt-in:

```bat
tools\copilot-auto-allow.exe -AllowSensitivePrompt
```

Use these overrides only in trusted local environments.
