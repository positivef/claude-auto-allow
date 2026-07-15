# Contribution And Release Workflow

This repository uses a verified-merge workflow for code, executable, and
documentation changes.

## Branch Policy

- `main` is the stable branch.
- Do not commit feature or fix work directly to `main`.
- Create a short-lived branch for each change, using the `codex/` prefix when
  Codex performs the work.
- Keep each branch focused on one fix, feature, release, or documentation
  update.
- Do not include runtime-local files such as `tools/auto-allow-policy.json`
  unless the change intentionally updates the default policy.

Recommended branch names:

```text
codex/windows-cli-wrapper-fix
codex/desktop-auto-click-fix
codex/macos-support
codex/release-v0.2.0
```

## Required Flow

1. Start from the latest `main`.
2. Create a change branch.
3. Make the smallest scoped change that solves the issue.
4. Rebuild any affected executable artifacts.
5. Run the relevant verification commands.
6. Commit on the change branch.
7. Push the change branch.
8. Merge into `main` only after verification passes.
9. Push `main`.

## Verification Checklist

For Windows executable changes, run the applicable checks:

```bat
tools\windows-claude-cli-auto-wrapper.exe --self-test
tools\windows-claude-cli-auto-folder-picker.exe --self-test
tools\windows-claude-desktop-click-auto-allow-console.exe --self-test
tools\windows-claude-desktop-click-auto-allow-gui.exe --self-test
tools\windows-copilot-desktop-click-auto-allow-console.exe --self-test
```

Also verify the launchers:

```bat
tools\windows-auto-allow-policy-control.cmd --self-test
tools\windows-claude-cli-auto-wrapper.cmd --self-test
tools\windows-claude-cli-auto-folder-picker.cmd --self-test
tools\windows-claude-desktop-click-auto-allow.cmd --self-test
tools\windows-copilot-desktop-click-auto-allow.cmd --self-test
```

For desktop-click engine changes, also parse the PowerShell scripts and run a
short disabled-policy engine smoke test so the worker starts and exits without
clicking any UI.

For macOS wrapper changes, verify on macOS before merging to `main`. Windows
can review file contents, but it cannot fully validate `.command` launcher
behavior or zsh execution.

## Merge Rule

Use a merge commit when practical so `main` history shows which branch introduced
each verified change. The branch can be deleted after `main` is pushed and the
change is no longer needed for review.
