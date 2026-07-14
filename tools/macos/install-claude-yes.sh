#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"

chmod +x "$SCRIPT_DIR/claude-yes"
chmod +x "$SCRIPT_DIR/claude-yes-folder.command"

mkdir -p "$HOME/bin"
cp "$SCRIPT_DIR/claude-yes" "$HOME/bin/claude-yes"
chmod +x "$HOME/bin/claude-yes"

DESKTOP_LINK="$HOME/Desktop/Claude Yes CLI - Folder Picker.command"
cat > "$DESKTOP_LINK" <<'COMMAND'
#!/bin/zsh
set -euo pipefail

CLAUDE_YES="$HOME/bin/claude-yes"

if [[ ! -x "$CLAUDE_YES" ]]; then
  echo "claude-yes 실행 파일을 찾을 수 없습니다:"
  echo "$CLAUDE_YES"
  echo
  echo "install-claude-yes.sh를 먼저 실행하세요."
  read -k "?Press any key to close..."
  exit 1
fi

selected_path="$(osascript <<'APPLESCRIPT'
try
  set chosenFolder to choose folder with prompt "Claude Code를 실행할 프로젝트 폴더를 선택하세요."
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
echo "[claude-yes CLI wrapper] project: $PWD"
echo
exec "$CLAUDE_YES"
COMMAND
chmod +x "$DESKTOP_LINK"

echo "설치 완료"
echo
echo "터미널 사용:"
echo "  cd /path/to/project"
echo "  $HOME/bin/claude-yes"
echo
echo "아이콘 사용:"
echo "  Double-click 'Claude Yes CLI - Folder Picker.command' on the Desktop"
echo
echo "PATH에 $HOME/bin 이 없으면 ~/.zshrc에 아래 줄을 추가하세요:"
echo '  export PATH="$HOME/bin:$PATH"'
