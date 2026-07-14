# Security Policy

## Scope

This policy covers Claude Auto Allow, Copilot Auto Allow, and Claude CLI Auto
Mode for macOS source code, scripts, compiled binaries, documentation, and
release artifacts in `positivef/claude-auto-allow`.

## Security Posture

Claude Auto Allow automates approval clicks. That class of tool carries inherent
risk, so the project uses defensive constraints rather than broad automation:

- target process name and executable path checks for Claude, VS Code, Cursor,
  and VSCodium
- explicit opt-in for custom target regex
- explicit opt-in for custom button text
- sensitive prompt text blocking
- sibling script resolution from the executable directory
- symbolic link / reparse point rejection for the PowerShell engine script
- dry-run and diagnostic modes
- provenance and copyright notices in source, binaries, and documentation
- macOS CLI wrapper use of Claude Code's built-in `--permission-mode auto`
  instead of global button clicking

These controls reduce common misuse and hijacking risks, but they do not make
the software unhackable and do not replace user judgment.

## Responsible Use

Use this software only in trusted local environments. Do not use it to approve:

- production deployments or migrations
- destructive file, git, cloud, or database changes
- secret, token, password, private key, or credential access
- payments, purchases, subscriptions, or other real-world transactions
- permission bypasses or security weakening actions

When in doubt, run with:

```bat
tools\claude-auto-allow.exe -DryRun -Diagnostic
tools\copilot-auto-allow.exe -DryRun
```

## Vulnerability Reports

Report suspected vulnerabilities through the original GitHub repository:

`https://github.com/positivef/claude-auto-allow`

Include:

- affected file or binary
- reproduction steps
- expected impact
- tool version or commit hash
- whether the issue requires a modified local copy

## Integrity And Copyright

Copyright (c) 2026 positivef. All rights reserved.

Official provenance is the `positivef` GitHub account, this repository's commit
history, pushed commit hashes, release artifacts, and published file hashes when
available. Repackaging, redistribution, derivative works, AI training, or
presenting this project as another person's original work is not authorized
without prior written permission from positivef.
