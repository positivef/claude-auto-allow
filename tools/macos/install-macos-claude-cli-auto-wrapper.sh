#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
WRAPPER_SOURCE="$SCRIPT_DIR/macos-claude-cli-auto-wrapper"
PICKER_SOURCE="$SCRIPT_DIR/macos-claude-cli-auto-folder-picker.command"
POLICY_SOURCE="$SCRIPT_DIR/../auto-allow-policy.json"

chmod +x "$WRAPPER_SOURCE"
chmod +x "$PICKER_SOURCE"

mkdir -p "$HOME/bin"
cp "$WRAPPER_SOURCE" "$HOME/bin/macos-claude-cli-auto-wrapper"
chmod +x "$HOME/bin/macos-claude-cli-auto-wrapper"

if [[ -f "$POLICY_SOURCE" ]]; then
  cp "$POLICY_SOURCE" "$HOME/bin/auto-allow-policy.json"
fi

ln -sf "$HOME/bin/macos-claude-cli-auto-wrapper" "$HOME/bin/claude-cli-auto"

DESKTOP_LINK="$HOME/Desktop/macOS Claude CLI Auto Wrapper - Folder Picker.command"
cat > "$DESKTOP_LINK" <<'COMMAND'
#!/bin/zsh
set -euo pipefail

WRAPPER="$HOME/bin/macos-claude-cli-auto-wrapper"

if [[ ! -x "$WRAPPER" ]]; then
  echo "macOS Claude CLI auto wrapper was not found:"
  echo "$WRAPPER"
  echo
  echo "Run install-macos-claude-cli-auto-wrapper.sh first."
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
COMMAND
chmod +x "$DESKTOP_LINK"

echo "Install complete."
echo
echo "Terminal use:"
echo "  cd /path/to/project"
echo "  macos-claude-cli-auto-wrapper"
echo
echo "Short alias:"
echo "  claude-cli-auto"
echo
echo "Desktop launcher:"
echo "  macOS Claude CLI Auto Wrapper - Folder Picker.command"
echo
echo "If ~/bin is not on PATH, add this to ~/.zshrc:"
echo '  export PATH="$HOME/bin:$PATH"'
