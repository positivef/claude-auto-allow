param(
    [string[]]$ButtonText,
    [string]$WindowTitleRegex = '',
    [string]$ProcessNameRegex = '(?i)^claude$',
    [string]$TargetPathRegex = '(?i)(\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude\.exe$|\\anthropicclaude\\.*\\claude\.exe$)',
    [string[]]$BlockedPromptText,
    [ValidateSet('Always', 'Once')]
    [string]$Prefer = 'Always',
    [int]$IntervalMilliseconds = 120,
    [int]$MaxSeconds = 0,
    [switch]$Once,
    [switch]$DryRun,
    [switch]$Diagnostic,
    [switch]$DeepScan,
    [switch]$DisableCoveredFallback,
    [switch]$AllowCustomTarget,
    [switch]$AllowCustomButtonText,
    [switch]$AllowSensitivePrompt,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName WindowsBase
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class ClaudeAutoAllowNative
{
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(int flags, int dx, int dy, int data, UIntPtr extraInfo);
}
"@

$ToolOwner = 'positivef'
$ToolRepository = 'https://github.com/positivef/claude-auto-allow'
$ToolProvenance = 'CAA-POSITIVEF-2026-07'
$DefaultProcessNameRegex = '(?i)^claude$'
$DefaultTargetPathRegex = '(?i)(\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude\.exe$|\\anthropicclaude\\.*\\claude\.exe$)'

if (($PSBoundParameters.ContainsKey('ButtonText') -and $ButtonText.Count -gt 0) -and -not $AllowCustomButtonText) {
    throw 'Custom ButtonText requires -AllowCustomButtonText. This prevents accidental approval of unrelated buttons.'
}

if ((-not [string]::IsNullOrWhiteSpace($WindowTitleRegex) -or $ProcessNameRegex -ne $DefaultProcessNameRegex -or $TargetPathRegex -ne $DefaultTargetPathRegex) -and -not $AllowCustomTarget) {
    throw 'Custom WindowTitleRegex, ProcessNameRegex, or TargetPathRegex requires -AllowCustomTarget. This prevents targeting unrelated applications.'
}

function New-TextFromCodePoints {
    param([int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Normalize-Text {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    return (($Value -replace '\s+', ' ').Trim()).ToLowerInvariant()
}

function Write-ToolLog {
    param([string]$Message)

    if (-not $Quiet) {
        $timestamp = Get-Date -Format 'HH:mm:ss'
        Write-Host "[$timestamp] $Message"
    }
}

function Get-ProcessPath {
    param([System.Diagnostics.Process]$Process)

    try {
        if ($Process -and $Process.MainModule) {
            return $Process.MainModule.FileName
        }
    }
    catch {
        return ''
    }

    return ''
}

function Get-WindowVisibleText {
    param([System.Windows.Automation.AutomationElement]$Window)

    $parts = New-Object System.Collections.ArrayList
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $stack = New-Object System.Collections.Stack
    $stack.Push($Window)

    while ($stack.Count -gt 0 -and $parts.Count -lt 300) {
        $node = [System.Windows.Automation.AutomationElement]$stack.Pop()

        try {
            if (-not $node.Current.IsOffscreen -and -not [string]::IsNullOrWhiteSpace($node.Current.Name)) {
                [void]$parts.Add($node.Current.Name)
            }

            $children = New-Object System.Collections.ArrayList
            $child = $walker.GetFirstChild($node)
            while ($child) {
                [void]$children.Add($child)
                $child = $walker.GetNextSibling($child)
            }

            for ($i = $children.Count - 1; $i -ge 0; $i--) {
                $stack.Push($children[$i])
            }
        }
        catch {
            continue
        }
    }

    return ($parts -join ' ')
}

function Get-BlockedPromptReason {
    param(
        [System.Windows.Automation.AutomationElement]$Window,
        [string[]]$Patterns
    )

    if ($AllowSensitivePrompt) {
        return ''
    }

    $windowText = Get-WindowVisibleText -Window $Window
    if ([string]::IsNullOrWhiteSpace($windowText)) {
        return ''
    }

    foreach ($pattern in $Patterns) {
        if (-not [string]::IsNullOrWhiteSpace($pattern) -and $windowText -match $pattern) {
            return $pattern
        }
    }

    return ''
}

function Test-AllowedButtonName {
    param(
        [string]$ElementName,
        [hashtable]$AllowedNames
    )

    if ([string]::IsNullOrWhiteSpace($ElementName)) {
        return $false
    }

    if ($AllowedNames.ContainsKey($ElementName)) {
        return $true
    }

    foreach ($allowedName in $AllowedNames.Keys) {
        if (
            $ElementName.StartsWith("$allowedName ", [System.StringComparison]::Ordinal) -or
            $ElementName.StartsWith("$allowedName`n", [System.StringComparison]::Ordinal) -or
            $ElementName.StartsWith("$allowedName`t", [System.StringComparison]::Ordinal)
        ) {
            return $true
        }
    }

    return $false
}

function Test-VisibleRect {
    param(
        [System.Windows.Rect]$Rect,
        [System.Windows.Rect]$ContainerRect
    )

    if ($Rect.IsEmpty -or $Rect.Width -le 0 -or $Rect.Height -le 0) {
        return $false
    }

    if ($ContainerRect.IsEmpty -or $ContainerRect.Width -le 0 -or $ContainerRect.Height -le 0) {
        return $true
    }

    $left = [Math]::Max($Rect.Left, $ContainerRect.Left)
    $right = [Math]::Min($Rect.Right, $ContainerRect.Right)
    $top = [Math]::Max($Rect.Top, $ContainerRect.Top)
    $bottom = [Math]::Min($Rect.Bottom, $ContainerRect.Bottom)

    return ($right -gt $left -and $bottom -gt $top)
}

function Get-VisibleButtonElements {
    param([System.Windows.Automation.AutomationElement]$Window)

    $windowRect = $Window.Current.BoundingRectangle
    $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker
    $stack = New-Object System.Collections.Stack
    $stack.Push($Window)
    $buttons = New-Object System.Collections.ArrayList

    while ($stack.Count -gt 0) {
        $node = [System.Windows.Automation.AutomationElement]$stack.Pop()
        $children = New-Object System.Collections.ArrayList

        try {
            $child = $walker.GetFirstChild($node)
            while ($child) {
                [void]$children.Add($child)
                $child = $walker.GetNextSibling($child)
            }
        }
        catch {
            continue
        }

        for ($i = $children.Count - 1; $i -ge 0; $i--) {
            $child = [System.Windows.Automation.AutomationElement]$children[$i]

            try {
                if ($child.Current.IsOffscreen) {
                    continue
                }

                $rect = $child.Current.BoundingRectangle
                if (-not (Test-VisibleRect -Rect $rect -ContainerRect $windowRect)) {
                    continue
                }

                if ($child.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button) {
                    [void]$buttons.Add($child)
                    continue
                }

                $stack.Push($child)
            }
            catch {
                continue
            }
        }
    }

    return $buttons
}

function Get-ButtonAncestorFromPoint {
    param(
        [double]$X,
        [double]$Y,
        [int]$TargetProcessId
    )

    try {
        $point = New-Object System.Windows.Point($X, $Y)
        $element = [System.Windows.Automation.AutomationElement]::FromPoint($point)
        $walker = [System.Windows.Automation.TreeWalker]::ControlViewWalker

        for ($i = 0; $i -lt 8 -and $element; $i++) {
            if ($element.Current.ProcessId -ne $TargetProcessId) {
                return $null
            }

            if ($element.Current.ControlType -eq [System.Windows.Automation.ControlType]::Button) {
                return $element
            }

            $element = $walker.GetParent($element)
        }
    }
    catch {
        return $null
    }

    return $null
}

function Test-ApprovalElement {
    param([System.Windows.Automation.AutomationElement]$Element)

    try {
        $className = $Element.Current.ClassName
        $name = $Element.Current.Name

        if ($className -match '(?i)approval|epitaxy-approval') {
            return $true
        }

        if ($name -match '(?i)permission|allow') {
            return $true
        }

        $permissionRequestKo = New-TextFromCodePoints @(0xAD8C, 0xD55C, 0x20, 0xC694, 0xCCAD)
        $allowQuestionKo = New-TextFromCodePoints @(0xD5C8, 0xC6A9, 0xD558, 0xC2DC, 0xACA0, 0xC2B5, 0xB2C8, 0xAE4C)
        $allowKo = New-TextFromCodePoints @(0xD5C8, 0xC6A9)

        if ($name -like "*$permissionRequestKo*" -or $name -like "*$allowQuestionKo*" -or $name -like "*$allowKo*") {
            return $true
        }
    }
    catch {
        return $false
    }

    return $false
}

function Get-PointSampledButtonElements {
    param([System.Windows.Automation.AutomationElement]$Window)

    $windowRect = $Window.Current.BoundingRectangle
    if ($windowRect.IsEmpty -or $windowRect.Width -le 0 -or $windowRect.Height -le 0) {
        return @()
    }

    $targetProcessId = $Window.Current.ProcessId
    $buttonsByKey = @{}
    $yFractions = @(0.78, 0.80)
    $xFractions = @(0.52, 0.58, 0.62, 0.68, 0.72, 0.76, 0.48)

    foreach ($yFraction in $yFractions) {
        $y = $windowRect.Top + ($windowRect.Height * $yFraction)

        foreach ($xFraction in $xFractions) {
            $x = $windowRect.Left + ($windowRect.Width * $xFraction)
            $button = Get-ButtonAncestorFromPoint -X $x -Y $y -TargetProcessId $targetProcessId
            if (-not $button) {
                continue
            }

            $rect = $button.Current.BoundingRectangle
            if (-not (Test-VisibleRect -Rect $rect -ContainerRect $windowRect)) {
                continue
            }

            $name = Normalize-Text $button.Current.Name
            if ([string]::IsNullOrWhiteSpace($name)) {
                continue
            }

            $key = "$($button.Current.AutomationId)|$name|$($rect.Left),$($rect.Top),$($rect.Width),$($rect.Height)"
            $buttonsByKey[$key] = $button
        }

        if ($buttonsByKey.Count -gt 0) {
            break
        }
    }

    return @($buttonsByKey.Values)
}

function Get-RegionButtonElements {
    param([System.Windows.Automation.AutomationElement]$Window)

    $windowRect = $Window.Current.BoundingRectangle
    if ($windowRect.IsEmpty -or $windowRect.Width -le 0 -or $windowRect.Height -le 0) {
        return @()
    }

    $regionLeft = $windowRect.Left + ($windowRect.Width * 0.22)
    $regionRight = $windowRect.Left + ($windowRect.Width * 0.82)
    $regionTop = $windowRect.Top + ($windowRect.Height * 0.54)
    $regionBottom = $windowRect.Top + ($windowRect.Height * 0.84)
    $region = New-Object System.Windows.Rect(
        $regionLeft,
        $regionTop,
        ($regionRight - $regionLeft),
        ($regionBottom - $regionTop)
    )

    $buttonCondition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::Button
    )

    $buttonsByKey = @{}

    try {
        $buttons = $Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $buttonCondition)
        foreach ($button in $buttons) {
            if ($button.Current.IsOffscreen) {
                continue
            }

            $rect = $button.Current.BoundingRectangle
            if (-not (Test-VisibleRect -Rect $rect -ContainerRect $region)) {
                continue
            }

            $name = Normalize-Text $button.Current.Name
            if ([string]::IsNullOrWhiteSpace($name)) {
                continue
            }

            $key = "$($button.Current.AutomationId)|$name|$($rect.Left),$($rect.Top),$($rect.Width),$($rect.Height)"
            $buttonsByKey[$key] = $button
        }
    }
    catch {
        return @()
    }

    return @($buttonsByKey.Values)
}

function Get-AllowedButtonPriority {
    param(
        [string]$ElementName,
        [hashtable]$AllowedNames,
        [hashtable]$AlwaysNames,
        [hashtable]$OnceNames,
        [string]$Prefer
    )

    if (-not (Test-AllowedButtonName -ElementName $ElementName -AllowedNames $AllowedNames)) {
        return $null
    }

    $isAlways = Test-AllowedButtonName -ElementName $ElementName -AllowedNames $AlwaysNames
    $isOnce = Test-AllowedButtonName -ElementName $ElementName -AllowedNames $OnceNames

    if ($Prefer -eq 'Once') {
        if ($isOnce) {
            return 0
        }

        if ($isAlways) {
            return 1
        }
    }

    if ($isAlways) {
        return 0
    }

    if ($isOnce) {
        return 1
    }

    return 2
}

function Get-AllowedButtonCandidates {
    param(
        [object[]]$Elements,
        [hashtable]$AllowedNames,
        [hashtable]$AlwaysNames,
        [hashtable]$OnceNames,
        [string]$Prefer,
        [switch]$Diagnostic
    )

    $candidates = @()
    foreach ($element in $Elements) {
        $elementName = Normalize-Text $element.Current.Name
        if ($Diagnostic -and -not [string]::IsNullOrWhiteSpace($element.Current.Name)) {
            $rect = $element.Current.BoundingRectangle
            Write-ToolLog "Seen '$($element.Current.Name)' type='$($element.Current.ControlType.ProgrammaticName)' rect='$rect'"
        }

        $priority = Get-AllowedButtonPriority -ElementName $elementName -AllowedNames $AllowedNames -AlwaysNames $AlwaysNames -OnceNames $OnceNames -Prefer $Prefer
        if ($null -eq $priority) {
            continue
        }

        $candidates += [pscustomobject]@{
            Element = $element
            Priority = $priority
            Name = $elementName
            Label = $element.Current.Name
            AutomationId = $element.Current.AutomationId
        }
    }

    return @($candidates)
}

function Test-TargetWindow {
    param(
        [System.Windows.Automation.AutomationElement]$Window,
        [string]$TitleRegex,
        [string]$ProcRegex
    )

    $title = $Window.Current.Name
    $processId = $Window.Current.ProcessId
    $processName = ''

    if ($processId -gt 0) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($process) {
            $processName = $process.ProcessName
        }
    }

    $titleMatches = -not [string]::IsNullOrWhiteSpace($TitleRegex) -and $title -match $TitleRegex
    $processMatches = -not [string]::IsNullOrWhiteSpace($ProcRegex) -and $processName -match $ProcRegex

    if (-not ($titleMatches -or $processMatches)) {
        return $null
    }

    return [pscustomobject]@{
        Title = $title
        ProcessName = $processName
        ProcessId = $processId
    }
}

function Get-TargetWindows {
    param(
        [string]$TitleRegex,
        [string]$ProcRegex,
        [string]$PathRegex
    )

    $targets = New-Object System.Collections.ArrayList

    if ([string]::IsNullOrWhiteSpace($TitleRegex) -and $ProcRegex -eq '(?i)^claude$') {
        $processes = Get-Process -Name claude -ErrorAction SilentlyContinue | Where-Object {
            $_.MainWindowHandle -ne 0
        }
    }
    else {
        $processes = Get-Process -ErrorAction SilentlyContinue | Where-Object {
            $_.MainWindowHandle -ne 0 -and
            $_.ProcessName -ne 'claude-auto-allow'
        }
    }

    foreach ($process in $processes) {
        $title = $process.MainWindowTitle
        $processName = $process.ProcessName
        $processPath = Get-ProcessPath -Process $process
        $titleMatches = -not [string]::IsNullOrWhiteSpace($TitleRegex) -and $title -match $TitleRegex
        $processMatches = -not [string]::IsNullOrWhiteSpace($ProcRegex) -and $processName -match $ProcRegex
        $pathMatches = [string]::IsNullOrWhiteSpace($PathRegex) -or (-not [string]::IsNullOrWhiteSpace($processPath) -and $processPath -match $PathRegex)

        if (-not ($titleMatches -or $processMatches)) {
            continue
        }

        if (-not $pathMatches) {
            if ($Diagnostic) {
                Write-ToolLog "Skipped target with unexpected executable path: process='$processName' path='$processPath'"
            }
            continue
        }

        try {
            $element = [System.Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
            if (-not $element) {
                continue
            }

            [void]$targets.Add([pscustomobject]@{
                Element = $element
                Title = $element.Current.Name
                ProcessName = $processName
                ProcessPath = $processPath
                ProcessId = $process.Id
            })
        }
        catch {
            continue
        }
    }

    return @($targets)
}

function Invoke-Button {
    param(
        [System.Windows.Automation.AutomationElement]$Element,
        [switch]$DryRun
    )

    if ($DryRun) {
        return $true
    }

    $pattern = $null
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        $pattern.Invoke()
        return $true
    }

    $rect = $Element.Current.BoundingRectangle
    if (-not $rect.IsEmpty -and $rect.Width -gt 0 -and $rect.Height -gt 0) {
        $x = [int][Math]::Round($rect.Left + ($rect.Width / 2))
        $y = [int][Math]::Round($rect.Top + ($rect.Height / 2))
        [ClaudeAutoAllowNative]::SetCursorPos($x, $y) | Out-Null
        [ClaudeAutoAllowNative]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 50
        [ClaudeAutoAllowNative]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
        return $true
    }

    return $false
}

Add-Type -AssemblyName System.Windows.Forms

if (-not $PSBoundParameters.ContainsKey('ButtonText') -or $ButtonText.Count -eq 0) {
    $alwaysAllowKo = New-TextFromCodePoints @(0xD56D, 0xC0C1, 0x20, 0xD5C8, 0xC6A9)
    $alwaysAllowKoNoSpace = New-TextFromCodePoints @(0xD56D, 0xC0C1, 0xD5C8, 0xC6A9)
    $allowOnceKo = New-TextFromCodePoints @(0xD55C, 0x20, 0xBC88, 0xB9CC, 0x20, 0xD5C8, 0xC6A9)
    $allowOnceKoNoFirstSpace = New-TextFromCodePoints @(0xD55C, 0xBC88, 0xB9CC, 0x20, 0xD5C8, 0xC6A9)
    $allowOnceKoNoSpace = New-TextFromCodePoints @(0xD55C, 0xBC88, 0xB9CC, 0xD5C8, 0xC6A9)

    $ButtonText = @(
        'Always allow',
        'Always Allow',
        $alwaysAllowKo,
        $alwaysAllowKoNoSpace,
        'Allow once',
        'Allow Once',
        $allowOnceKo,
        $allowOnceKoNoFirstSpace,
        $allowOnceKoNoSpace
    )
}

if (-not $PSBoundParameters.ContainsKey('BlockedPromptText') -or $BlockedPromptText.Count -eq 0) {
    $BlockedPromptText = @(
        '(?i)dangerously',
        '(?i)bypass\s+permissions?',
        '(?i)skip\s+permissions?',
        '(?i)production|prod\b',
        '(?i)deploy|release|publish',
        '(?i)secret|token|password|credential|api\s*key|private\s*key|ssh\s*key',
        '(?i)delete|remove|destroy|truncate|drop\s+table|reset\s+--hard|git\s+clean|force\s+push',
        '(?i)payment|purchase|subscribe|billing',
        '삭제|제거|초기화|배포|운영|비밀번호|토큰|시크릿|개인정보|결제'
    )
}

$alwaysButtonText = @(
    'Always allow',
    'Always Allow',
    (New-TextFromCodePoints @(0xD56D, 0xC0C1, 0x20, 0xD5C8, 0xC6A9)),
    (New-TextFromCodePoints @(0xD56D, 0xC0C1, 0xD5C8, 0xC6A9))
)
$onceButtonText = @(
    'Allow once',
    'Allow Once',
    (New-TextFromCodePoints @(0xD55C, 0x20, 0xBC88, 0xB9CC, 0x20, 0xD5C8, 0xC6A9)),
    (New-TextFromCodePoints @(0xD55C, 0xBC88, 0xB9CC, 0x20, 0xD5C8, 0xC6A9)),
    (New-TextFromCodePoints @(0xD55C, 0xBC88, 0xB9CC, 0xD5C8, 0xC6A9))
)

$allowedButtonNames = @{}
foreach ($text in $ButtonText) {
    $normalized = Normalize-Text $text
    if ($normalized.Length -gt 0) {
        $allowedButtonNames[$normalized] = $true
    }
}

$alwaysButtonNames = @{}
foreach ($text in $alwaysButtonText) {
    $normalized = Normalize-Text $text
    if ($normalized.Length -gt 0) {
        $alwaysButtonNames[$normalized] = $true
    }
}

$onceButtonNames = @{}
foreach ($text in $onceButtonText) {
    $normalized = Normalize-Text $text
    if ($normalized.Length -gt 0) {
        $onceButtonNames[$normalized] = $true
    }
}

if ($allowedButtonNames.Count -eq 0) {
    throw 'At least one button label must be provided.'
}

if ($IntervalMilliseconds -lt 100) {
    throw 'IntervalMilliseconds must be at least 100.'
}

$root = [System.Windows.Automation.AutomationElement]::RootElement
$recentClicks = @{}
$startedAt = Get-Date

Write-ToolLog "Watching for button: $($ButtonText -join ', ')"
Write-ToolLog "Owner: $ToolOwner"
Write-ToolLog "Repository: $ToolRepository"
Write-ToolLog "Provenance: $ToolProvenance"
Write-ToolLog "Preference: $Prefer"
Write-ToolLog "Target title regex: $WindowTitleRegex"
Write-ToolLog "Target process regex: $ProcessNameRegex"
Write-ToolLog "Target path regex: $TargetPathRegex"
if ($AllowCustomTarget) {
    Write-ToolLog 'Custom target mode is enabled.'
}
if ($AllowCustomButtonText) {
    Write-ToolLog 'Custom button text mode is enabled.'
}
if ($AllowSensitivePrompt) {
    Write-ToolLog 'Sensitive prompt guard is disabled for this run.'
}
if ($DryRun) {
    Write-ToolLog 'Dry run mode is on; matching buttons will be logged but not clicked.'
}
if ($Diagnostic) {
    Write-ToolLog 'Diagnostic mode is on; permission-like elements in target windows will be logged.'
}
if ($DeepScan) {
    Write-ToolLog 'Deep scan mode is on; this is slower and should only be used when point sampling misses a button.'
}
if (-not $DisableCoveredFallback) {
    Write-ToolLog 'Covered-window fallback is on; fixed-region UIA invoke is used when point sampling misses a visible button.'
}
Write-ToolLog 'Press Ctrl+C to stop.'

while ($true) {
    if ($MaxSeconds -gt 0 -and ((Get-Date) - $startedAt).TotalSeconds -ge $MaxSeconds) {
        Write-ToolLog "Stopped after $MaxSeconds seconds."
        exit 0
    }

    $targetWindows = Get-TargetWindows -TitleRegex $WindowTitleRegex -ProcRegex $ProcessNameRegex -PathRegex $TargetPathRegex

    foreach ($target in $targetWindows) {
        $window = $target.Element
        $blockedReason = Get-BlockedPromptReason -Window $window -Patterns $BlockedPromptText
        if (-not [string]::IsNullOrWhiteSpace($blockedReason)) {
            Write-ToolLog "Blocked automatic click in '$($target.Title)' because sensitive prompt text matched: $blockedReason"
            continue
        }

        $elements = Get-PointSampledButtonElements -Window $window
        $candidates = Get-AllowedButtonCandidates -Elements $elements -AllowedNames $allowedButtonNames -AlwaysNames $alwaysButtonNames -OnceNames $onceButtonNames -Prefer $Prefer -Diagnostic:$Diagnostic

        if (-not $DisableCoveredFallback -and $candidates.Count -eq 0) {
            $elements = Get-RegionButtonElements -Window $window
            $candidates = Get-AllowedButtonCandidates -Elements $elements -AllowedNames $allowedButtonNames -AlwaysNames $alwaysButtonNames -OnceNames $onceButtonNames -Prefer $Prefer -Diagnostic:$Diagnostic
        }

        if ($DeepScan -and $candidates.Count -eq 0) {
            $elements = Get-VisibleButtonElements -Window $window
            $candidates = Get-AllowedButtonCandidates -Elements $elements -AllowedNames $allowedButtonNames -AlwaysNames $alwaysButtonNames -OnceNames $onceButtonNames -Prefer $Prefer -Diagnostic:$Diagnostic
        }

        foreach ($candidate in ($candidates | Sort-Object Priority)) {
            $element = $candidate.Element
            $elementName = $candidate.Name
            $buttonLabel = $element.Current.Name
            $windowHandle = $window.Current.NativeWindowHandle
            $automationId = $candidate.AutomationId
            $clickKey = "$windowHandle|$automationId|$elementName"

            if ($recentClicks.ContainsKey($clickKey)) {
                $elapsed = ((Get-Date) - $recentClicks[$clickKey]).TotalSeconds
                if ($elapsed -lt 2) {
                    continue
                }
            }

            $recentClicks[$clickKey] = Get-Date
            $action = if ($DryRun) { 'Would click' } else { 'Clicking' }
            Write-ToolLog "$action '$buttonLabel' in '$($target.Title)' [$($target.ProcessName):$($target.ProcessId)]"

            Invoke-Button -Element $element -DryRun:$DryRun | Out-Null

            if ($Once) {
                exit 0
            }

            break
        }
    }

    Start-Sleep -Milliseconds $IntervalMilliseconds
}
