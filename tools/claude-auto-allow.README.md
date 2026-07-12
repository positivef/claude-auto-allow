# Claude Auto Allow

Windows에서 Claude/Code 계열 팝업에 `Always allow`, `항상 허용`, `Allow once`, `한 번만 허용` 버튼이 보이면 자동으로 누르는 로컬 도구입니다. 기본 실행 파일은 `claude-auto-allow.exe`입니다. 이 exe는 같은 폴더의 `claude-auto-allow.ps1`을 호출하므로 두 파일을 같이 두세요.

## 실행

```bat
tools\claude-auto-allow.exe
```

`tools\claude-auto-allow.cmd`도 같은 방식으로 실행할 수 있습니다. 실행 중인 창은 그대로 두고 Claude 작업을 시작하면 됩니다. 멈추려면 해당 창에서 `Ctrl+C`를 누르세요. 기본 모드는 Claude 승인 카드가 뜨는 고정 영역에서 실제 허용 버튼 객체를 찾아 내부 UI Automation으로 누릅니다.

GUI로 실행/정지와 로그 확인을 하려면:

```bat
tools\claude-auto-allow-gui.exe
```

GUI는 실행되면 자동으로 감시를 시작합니다. `Stop`으로 중지하고 `Start`로 다시 시작할 수 있으며, 클릭 이벤트와 진단 출력은 하단 로그 영역에 표시됩니다.

## 테스트 실행

클릭하지 않고 감지만 확인하려면:

```bat
tools\claude-auto-allow.exe -DryRun
```

버튼이 왜 안 잡히는지 로그를 더 보려면:

```bat
tools\claude-auto-allow.exe -DryRun -Diagnostic
```

한 번만 누르고 종료하려면:

```bat
tools\claude-auto-allow.exe -Once
```

## 대상 조정

기본값은 `claude.exe` 창에서만 동작합니다. 버튼 문구가 다르면 직접 지정할 수 있습니다. Claude Desktop은 버튼명을 `항상 허용 2` 또는 `한 번만 허용 2 Ctrl +Enter`처럼 단축키 번호와 함께 노출할 수 있어서, 이 도구는 지정한 버튼 문구와 정확히 같거나 그 문구로 시작하는 버튼을 클릭합니다. `항상 허용`과 `한 번만 허용`이 둘 다 있으면 `항상 허용`을 우선 클릭합니다. 키보드로 `2`를 입력하는 방식은 사용하지 않습니다.

다른 창이 버튼 위를 가려서 화면 좌표 감지가 실패하면, 기본적으로 같은 고정 영역에서 내부 UI Automation fallback을 사용합니다. 창이 최소화되어 있거나 Claude가 접근성 트리에서 승인 카드를 제거한 상태라면 동작하지 않을 수 있습니다.

```bat
tools\claude-auto-allow.exe -ButtonText "항상허용,Always allow"
```

VS Code나 Cursor 안에서 뜨는 팝업까지 포함하려면:

```bat
tools\claude-auto-allow.exe -WindowTitleRegex "claude|codex|visual studio code|cursor|code" -ProcessNameRegex "claude|codex|code|cursor"
```

## 주의

이 도구는 지정된 버튼 이름과 대상 창/프로세스 필터가 모두 맞을 때만 동작하도록 제한되어 있습니다. 그래도 권한 허용을 자동화하는 도구이므로, 신뢰하는 작업 환경에서만 실행하세요.
