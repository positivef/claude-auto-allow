#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
CLAUDE_YES="$SCRIPT_DIR/claude-yes"

if [[ ! -x "$CLAUDE_YES" ]]; then
  chmod +x "$CLAUDE_YES" 2>/dev/null || true
fi

if [[ ! -x "$CLAUDE_YES" ]]; then
  echo "claude-yes 실행 권한이 없습니다:"
  echo "$CLAUDE_YES"
  echo
  echo "아래 명령을 한 번 실행하세요:"
  echo "chmod +x ${(q)CLAUDE_YES} ${(q)0}"
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
