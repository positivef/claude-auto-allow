#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
WRAPPER="$SCRIPT_DIR/macos-claude-cli-auto-wrapper"

if [[ ! -x "$WRAPPER" ]]; then
  chmod +x "$WRAPPER" 2>/dev/null || true
fi

if [[ ! -x "$WRAPPER" ]]; then
  echo "macOS Claude CLI auto wrapper is not executable:"
  echo "$WRAPPER"
  echo
  echo "Run this once:"
  echo "chmod +x ${(q)WRAPPER} ${(q)0}"
  read -k "?Press any key to close..."
  exit 1
fi

selected_path="$(osascript <<'APPLESCRIPT'
try
  set chosenFolder to choose folder with prompt "Select the project folder for Claude Code CLI auto wrapper."
  return POSIX path of chosenFolder
on error number -128
  return ""
end try
APPLESCRIPT
)"

if [[ -z "$selected_path" ]]; then
  exit 0
fi

cd "$selected_path"
exec "$WRAPPER"
