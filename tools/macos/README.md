# macOS Claude CLI Auto Wrapper

This is the macOS CLI wrapper version.

It does not click buttons globally. By default it starts Claude Code with:

```sh
--permission-mode auto
```

Routine local actions are approved by Claude Code's built-in auto mode, while
risky or important actions should still ask for confirmation.

The wrapper also reads `auto-allow-policy.json` when it can find it in either
the same folder or the parent `tools` folder. Set `cliPermissionMode` to control
new CLI sessions:

- `Auto`: inject `--permission-mode auto`.
- `Manual`: do not inject a permission option; Claude Code asks normally.

You can also point to a policy file with `CLAUDE_AUTO_ALLOW_POLICY_FILE`.

## Files

- `macos-claude-cli-auto-wrapper`: terminal CLI wrapper. Run this inside a project folder.
- `macos-claude-cli-auto-folder-picker.command`: double-click launcher that asks for a project folder.
- `install-macos-claude-cli-auto-wrapper.sh`: installer that copies the wrapper and policy file to `~/bin` and creates a Desktop launcher.

## What You See In The Terminal

When the wrapper starts, it sets the terminal title to:

```text
Claude CLI | Project=project-name | Mode=AUTO | Topic=task-summary
```

It also prints:

- project name
- project path
- status, currently `launching Claude Code under wrapper`
- topic, from command arguments or `interactive session`
- topic source, either `command arguments`, `CLAUDE_AUTO_ALLOW_TOPIC`, or `default`
- whether CLI policy is `Auto` or `Manual`
- whether `--permission-mode auto` was injected
- policy file path, if found
- provenance marker

For an interactive session with no initial prompt, set a title topic first:

```sh
CLAUDE_AUTO_ALLOW_TOPIC="payment API refactor" macos-claude-cli-auto-wrapper
```

The wrapper cannot read Claude Code's live internal progress after Claude has
started, so the title topic is a launch-time label.

## Install

Copy this `tools/macos` folder to the Mac, then run:

```sh
cd /path/to/tools/macos
chmod +x macos-claude-cli-auto-wrapper macos-claude-cli-auto-folder-picker.command install-macos-claude-cli-auto-wrapper.sh
./install-macos-claude-cli-auto-wrapper.sh
```

## CLI Use

```sh
cd /path/to/project
macos-claude-cli-auto-wrapper
```

Short alias installed by the installer:

```sh
claude-cli-auto
```

## Folder Picker Use

Double-click the Desktop launcher:

```text
macOS Claude CLI Auto Wrapper - Folder Picker.command
```

In the macOS folder picker, press:

```text
Command + Shift + G
```

Then paste or type the project folder path.

## Difference From Windows Desktop Click Tools

- macOS `macos-claude-cli-auto-wrapper` is a CLI startup wrapper.
- Windows `windows-claude-desktop-click-auto-allow-*` files are UI auto-clickers for visible approval prompts.
- Both are intended to reduce routine permission prompts.
- Neither applies to Claude Code sessions that are already running.

## Ownership

Copyright (c) 2026 positivef. All rights reserved.

Provenance should be verified against the original repository:

```text
https://github.com/positivef/claude-auto-allow
```
