# Claude CLI Auto Mode for macOS

This is the macOS CLI wrapper version.

It does not click buttons globally. It starts Claude Code with:

```sh
--permission-mode auto
```

Routine local actions are approved by Claude Code's built-in auto mode, while
risky or important actions should still ask for confirmation.

## Files

- `claude-yes`: terminal CLI wrapper. Run this inside a project folder.
- `claude-yes-folder.command`: double-click launcher that asks for a project folder.
- `install-claude-yes.sh`: installer that copies `claude-yes` to `~/bin` and creates a Desktop launcher.

## Install

Copy this `tools/macos` folder to the Mac, then run:

```sh
cd /path/to/tools/macos
chmod +x claude-yes claude-yes-folder.command install-claude-yes.sh
./install-claude-yes.sh
```

## CLI Use

```sh
cd /path/to/project
claude-yes
```

If `claude-yes` is not on `PATH`:

```sh
~/bin/claude-yes
```

## Folder Picker Use

Double-click the Desktop launcher:

```text
Claude Yes CLI - Folder Picker.command
```

In the macOS folder picker, press:

```text
Command + Shift + G
```

Then paste or type the project folder path.

## Difference From Windows Auto Clicker

- macOS `claude-yes` is a CLI startup wrapper.
- Windows `claude-auto-allow` is a UI auto-clicker for visible approval prompts.
- Both are intended to reduce routine permission prompts.
- Neither applies to Claude Code sessions that are already running.

## Ownership

Copyright (c) 2026 positivef. All rights reserved.

Provenance should be verified against the original repository:

```text
https://github.com/positivef/claude-auto-allow
```
