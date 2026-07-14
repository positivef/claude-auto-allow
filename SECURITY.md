# Security Policy

## Scope

This policy covers Windows Claude CLI Auto Wrapper, macOS Claude CLI Auto
Wrapper, Windows Claude Desktop Click Auto Allow, and Windows Copilot Desktop
Click Auto Allow source code, scripts, compiled binaries, documentation, and
release artifacts in `positivef/claude-auto-allow`.

## Security Posture

The desktop-click tools automate approval clicks. That class of tool carries
inherent risk, so the project uses defensive constraints rather than broad
automation:

- target process name and executable path checks for Claude, VS Code, Cursor,
  and VSCodium
- explicit opt-in for custom target regex
- explicit opt-in for custom button text
- live sensitive prompt policy with `PolicyAsk`, `PolicyBlock`, `AlwaysAllow`,
  and `Disabled` modes
- sibling script resolution from the executable directory
- symbolic link / reparse point rejection for the PowerShell engine script
- dry-run and diagnostic modes
- provenance and copyright notices in source, binaries, and documentation
- Windows and macOS CLI wrappers use Claude Code's built-in
  `--permission-mode auto` instead of global button clicking

These controls reduce common misuse and hijacking risks, but they do not make
the software unhackable and do not replace user judgment.

## Live Policy

Windows desktop-click tools read `tools/auto-allow-policy.json` while running.
The default `PolicyAsk` mode clicks routine approval prompts but asks before
approving prompts that match sensitive terms. `PolicyBlock` blocks those
prompts, `AlwaysAllow` bypasses the sensitive-text guard while keeping target
and button checks, and `Disabled` stops all automatic clicks.

Changing this file through `tools\windows-auto-allow-policy-control.cmd` or the
GUI applies to the running watcher on the next scan loop. It does not change the
internal permission mode of a Claude Code CLI process that has already started.

## Responsible Use

Use this software only in trusted local environments. Do not use it to approve:

- production deployments or migrations
- destructive file, git, cloud, or database changes
- secret, token, password, private key, or credential access
- payments, purchases, subscriptions, or other real-world transactions
- permission bypasses or security weakening actions

When in doubt, run with:

```bat
tools\windows-claude-desktop-click-auto-allow-console.exe -DryRun -Diagnostic
tools\windows-copilot-desktop-click-auto-allow-console.exe -DryRun
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
