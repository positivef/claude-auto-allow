param(
    [string[]]$ButtonText,
    [string]$WindowTitleRegex = '(?i)(github copilot|copilot|visual studio code|cursor|\bcode\b)',
    [string]$ProcessNameRegex = '(?i)(code|cursor)',
    [string]$TargetPathRegex = '(?i)(\\Microsoft VS Code\\Code\.exe$|\\Cursor\\Cursor\.exe$|\\VSCodium\\VSCodium\.exe$)',
    [string]$ContextTextRegex = '(?i)(github copilot|copilot)',
    [string[]]$BlockedPromptText,
    [string]$PolicyFile = '',
    [int]$IntervalMilliseconds = 500,
    [int]$MaxSeconds = 0,
    [switch]$Once,
    [switch]$DryRun,
    [switch]$Quiet,
    [switch]$NoMouseFallback,
    [switch]$AllowCustomTarget,
    [switch]$AllowCustomButtonText,
    [switch]$AllowSensitivePrompt
)

$ErrorActionPreference = 'Stop'

$ToolOwner = 'positivef'
$ToolRepository = 'https://github.com/positivef/claude-auto-allow'
$ToolProvenance = 'COPILOT-AA-POSITIVEF-2026-07'
$DefaultWindowTitleRegex = '(?i)(github copilot|copilot|visual studio code|cursor|\bcode\b)'
$DefaultProcessNameRegex = '(?i)(code|cursor)'
$DefaultTargetPathRegex = '(?i)(\\Microsoft VS Code\\Code\.exe$|\\Cursor\\Cursor\.exe$|\\VSCodium\\VSCodium\.exe$)'
$CommandLineDryRunProvided = $PSBoundParameters.ContainsKey('DryRun')

if ([string]::IsNullOrWhiteSpace($PolicyFile)) {
    $PolicyFile = Join-Path $PSScriptRoot 'auto-allow-policy.json'
}

if (($PSBoundParameters.ContainsKey('ButtonText') -and $ButtonText.Count -gt 0) -and -not $AllowCustomButtonText) {
    throw 'Custom ButtonText requires -AllowCustomButtonText. This prevents accidental approval of unrelated buttons.'
}

if (($WindowTitleRegex -ne $DefaultWindowTitleRegex -or $ProcessNameRegex -ne $DefaultProcessNameRegex -or $TargetPathRegex -ne $DefaultTargetPathRegex) -and -not $AllowCustomTarget) {
    throw 'Custom WindowTitleRegex, ProcessNameRegex, or TargetPathRegex requires -AllowCustomTarget. This prevents targeting unrelated applications.'
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class CopilotAutoAllowNative
{
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT
    {
        public int X;
        public int Y;
    }

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr windowHandle);

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT point);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(int flags, int dx, int dy, int data, UIntPtr extraInfo);
}
"@

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

$script:LastPolicyWarning = ''
$script:RecentSensitivePromptDenials = @{}

function Write-PolicyWarningOnce {
    param([string]$Message)

    if ($script:LastPolicyWarning -ne $Message) {
        Write-ToolLog $Message
        $script:LastPolicyWarning = $Message
    }
}

function ConvertTo-PolicyBool {
    param(
        $Value,
        [bool]$Default
    )

    if ($null -eq $Value) {
        return $Default
    }

    if ($Value -is [bool]) {
        return [bool]$Value
    }

    $text = "$Value".Trim().ToLowerInvariant()
    if ($text -in @('true', '1', 'yes', 'on')) {
        return $true
    }
    if ($text -in @('false', '0', 'no', 'off')) {
        return $false
    }

    return $Default
}

function Get-LivePolicy {
    $mode = 'PolicyAsk'
    $dryRunValue = $false

    if (Test-Path -LiteralPath $PolicyFile -PathType Leaf) {
        try {
            $json = Get-Content -LiteralPath $PolicyFile -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($json)) {
                $config = $json | ConvertFrom-Json

                if ($config.PSObject.Properties.Name -contains 'mode') {
                    $candidateMode = "$($config.mode)".Trim()
                    if ($candidateMode -in @('AlwaysAllow', 'PolicyAsk', 'PolicyBlock', 'Disabled')) {
                        $mode = $candidateMode
                    }
                }

                if ($config.PSObject.Properties.Name -contains 'dryRun') {
                    $dryRunValue = ConvertTo-PolicyBool -Value $config.dryRun -Default $dryRunValue
                }
            }
        }
        catch {
            Write-PolicyWarningOnce "Policy file could not be read; using safe defaults. Path='$PolicyFile' Error='$($_.Exception.Message)'"
        }
    }

    if ($AllowSensitivePrompt) {
        $mode = 'AlwaysAllow'
    }

    if ($CommandLineDryRunProvided) {
        $dryRunValue = [bool]$DryRun
    }

    [pscustomobject]@{
        Mode = $mode
        DryRun = $dryRunValue
    }
}

function Request-SensitivePromptApproval {
    param(
        [object]$Target,
        [System.Windows.Automation.AutomationElement]$Window,
        [string]$Reason,
        [object]$Policy
    )

    if ($Policy.Mode -eq 'AlwaysAllow') {
        return $true
    }

    if ($Policy.Mode -eq 'Disabled') {
        Write-ToolLog "Auto allow is disabled by live policy. Skipping '$($Target.Title)'."
        return $false
    }

    if ($Policy.Mode -eq 'PolicyBlock') {
        Write-ToolLog "Blocked automatic click in '$($Target.Title)' because sensitive prompt text matched: $Reason"
        return $false
    }

    if ($Policy.DryRun) {
        Write-ToolLog "Dry run: would ask before allowing '$($Target.Title)' because sensitive prompt text matched: $Reason"
        return $false
    }

    $windowHandle = $Window.Current.NativeWindowHandle
    $denyKey = "$windowHandle|$Reason"
    if ($script:RecentSensitivePromptDenials.ContainsKey($denyKey)) {
        $elapsed = ((Get-Date) - $script:RecentSensitivePromptDenials[$denyKey]).TotalSeconds
        if ($elapsed -lt 15) {
            return $false
        }
    }

    $message = @"
Copilot approval prompt contains sensitive text.

Target : $($Target.Title)
Process: $($Target.ProcessName):$($Target.ProcessId)
Matched: $Reason

Allow this one automatic click?
"@

    $result = [System.Windows.Forms.MessageBox]::Show(
        $message,
        'Copilot Auto Allow - policy confirmation',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )

    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        Write-ToolLog "User allowed one sensitive prompt in '$($Target.Title)'."
        return $true
    }

    $script:RecentSensitivePromptDenials[$denyKey] = Get-Date
    Write-ToolLog "User denied sensitive prompt in '$($Target.Title)'."
    return $false
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

function Expand-TextList {
    param([string[]]$Values)

    $expanded = @()
    foreach ($value in $Values) {
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }

        $expanded += ($value -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
    }

    return $expanded
}

function Test-TargetWindow {
    param(
        [System.Windows.Automation.AutomationElement]$Window,
        [string]$TitleRegex,
        [string]$ProcRegex,
        [string]$PathRegex
    )

    $title = $Window.Current.Name
    $processId = $Window.Current.ProcessId
    $processName = ''
    $processPath = ''

    if ($processId -gt 0) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($process) {
            $processName = $process.ProcessName
            $processPath = Get-ProcessPath -Process $process
        }
    }

    $titleMatches = -not [string]::IsNullOrWhiteSpace($TitleRegex) -and $title -match $TitleRegex
    $processMatches = -not [string]::IsNullOrWhiteSpace($ProcRegex) -and $processName -match $ProcRegex
    $pathMatches = [string]::IsNullOrWhiteSpace($PathRegex) -or (-not [string]::IsNullOrWhiteSpace($processPath) -and $processPath -match $PathRegex)

    if (-not ($titleMatches -or $processMatches)) {
        return $null
    }

    if (-not $pathMatches) {
        return $null
    }

    return [pscustomobject]@{
        Title = $title
        ProcessName = $processName
        ProcessPath = $processPath
        ProcessId = $processId
        NativeWindowHandle = $Window.Current.NativeWindowHandle
    }
}

function Test-Context {
    param(
        [System.Windows.Automation.AutomationElement]$Window,
        [System.Windows.Automation.AutomationElement]$Element,
        [string]$Regex
    )

    if ([string]::IsNullOrWhiteSpace($Regex)) {
        return $true
    }

    $windowName = $Window.Current.Name
    if (-not [string]::IsNullOrWhiteSpace($windowName) -and $windowName -match $Regex) {
        return $true
    }

    $current = $Element
    while ($current) {
        $name = $current.Current.Name
        if (-not [string]::IsNullOrWhiteSpace($name) -and $name -match $Regex) {
            return $true
        }

        try {
            $current = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($current)
        }
        catch {
            break
        }

        if ($current -and $current.Equals($Window)) {
            break
        }
    }

    $contextNameCondition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::IsOffscreenProperty,
        $false
    )
    $visibleElements = $Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $contextNameCondition)
    foreach ($visibleElement in $visibleElements) {
        $name = $visibleElement.Current.Name
        if (-not [string]::IsNullOrWhiteSpace($name) -and $name -match $Regex) {
            return $true
        }
    }

    return $false
}

function Invoke-AllowElement {
    param(
        [System.Windows.Automation.AutomationElement]$Element,
        [int]$WindowHandle,
        [switch]$DryRun,
        [switch]$NoMouseFallback
    )

    if ($DryRun) {
        return 'dry-run'
    }

    $previousForeground = [CopilotAutoAllowNative]::GetForegroundWindow()
    $previousPoint = New-Object CopilotAutoAllowNative+POINT
    [CopilotAutoAllowNative]::GetCursorPos([ref]$previousPoint) | Out-Null

    try {
        $pattern = $null
        if ($Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
            $pattern.Invoke()
            return 'invoke'
        }

        if ($NoMouseFallback) {
            return 'skipped-no-mouse-fallback'
        }

        $rect = $Element.Current.BoundingRectangle
        if ($rect.IsEmpty -or $rect.Width -le 0 -or $rect.Height -le 0) {
            return 'failed-no-bounds'
        }

        if ($WindowHandle -ne 0) {
            [CopilotAutoAllowNative]::SetForegroundWindow([IntPtr]$WindowHandle) | Out-Null
            Start-Sleep -Milliseconds 80
        }

        $x = [int][Math]::Round($rect.Left + ($rect.Width / 2))
        $y = [int][Math]::Round($rect.Top + ($rect.Height / 2))
        [CopilotAutoAllowNative]::SetCursorPos($x, $y) | Out-Null
        [CopilotAutoAllowNative]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 50
        [CopilotAutoAllowNative]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
        return 'mouse'
    }
    finally {
        if (-not $NoMouseFallback) {
            [CopilotAutoAllowNative]::SetCursorPos($previousPoint.X, $previousPoint.Y) | Out-Null
        }

        if ($previousForeground -ne [IntPtr]::Zero) {
            Start-Sleep -Milliseconds 60
            [CopilotAutoAllowNative]::SetForegroundWindow($previousForeground) | Out-Null
        }
    }
}

if (-not $PSBoundParameters.ContainsKey('ButtonText') -or $ButtonText.Count -eq 0) {
    $ButtonText = @(
        'Allow',
        (New-TextFromCodePoints @(0xD5C8, 0xC6A9))
    )
}

$koreanSensitiveTerms = @(
    (New-TextFromCodePoints @(0xC0AD, 0xC81C)),
    (New-TextFromCodePoints @(0xC81C, 0xAC70)),
    (New-TextFromCodePoints @(0xCD08, 0xAE30, 0xD654)),
    (New-TextFromCodePoints @(0xBC30, 0xD3EC)),
    (New-TextFromCodePoints @(0xC6B4, 0xC601)),
    (New-TextFromCodePoints @(0xBE44, 0xBC00, 0xBC88, 0xD638)),
    (New-TextFromCodePoints @(0xD1A0, 0xD070)),
    (New-TextFromCodePoints @(0xC2DC, 0xD06C, 0xB9BF)),
    (New-TextFromCodePoints @(0xAC1C, 0xC778, 0xC815, 0xBCF4)),
    (New-TextFromCodePoints @(0xACB0, 0xC81C)),
    (New-TextFromCodePoints @(0xAD6C, 0xB3C5))
)
$koreanSensitivePattern = ($koreanSensitiveTerms | ForEach-Object { [regex]::Escape($_) }) -join '|'

$usingDefaultBlockedPromptText = -not $PSBoundParameters.ContainsKey('BlockedPromptText') -or $BlockedPromptText.Count -eq 0
if ($usingDefaultBlockedPromptText) {
    $BlockedPromptText = @(
        '(?i)dangerously',
        '(?i)bypass\s+permissions?',
        '(?i)skip\s+permissions?',
        '(?i)production|prod\b',
        '(?i)deploy|release|publish',
        '(?i)secret|token|password|credential|api\s*key|private\s*key|ssh\s*key',
        '(?i)delete|remove|destroy|truncate|drop\s+table|reset\s+--hard|git\s+clean|force\s+push',
        '(?i)payment|purchase|subscribe|billing'
    )
}

$validatedBlockedPromptText = @()
foreach ($pattern in $BlockedPromptText) {
    if ([string]::IsNullOrWhiteSpace($pattern)) {
        continue
    }

    try {
        $null = '' -match $pattern
        $validatedBlockedPromptText += $pattern
    }
    catch {
        Write-ToolLog "Ignoring invalid blocked prompt regex: $pattern"
    }
}
if ($usingDefaultBlockedPromptText -and -not [string]::IsNullOrWhiteSpace($koreanSensitivePattern)) {
    $validatedBlockedPromptText += $koreanSensitivePattern
}
$BlockedPromptText = $validatedBlockedPromptText

$ButtonText = Expand-TextList $ButtonText

$allowedButtonNames = @{}
foreach ($text in $ButtonText) {
    $normalized = Normalize-Text $text
    if ($normalized.Length -gt 0) {
        $allowedButtonNames[$normalized] = $true
    }
}

if ($allowedButtonNames.Count -eq 0) {
    throw 'At least one button label must be provided.'
}

if ($IntervalMilliseconds -lt 100) {
    throw 'IntervalMilliseconds must be at least 100.'
}

$windowCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Window
)

$nameConditions = @()
foreach ($text in $ButtonText) {
    if (-not [string]::IsNullOrWhiteSpace($text)) {
        $nameConditions += New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::NameProperty,
            $text
        )
    }
}

if ($nameConditions.Count -eq 1) {
    $candidateCondition = $nameConditions[0]
}
else {
    $candidateCondition = New-Object System.Windows.Automation.OrCondition(
        [System.Windows.Automation.Condition[]]$nameConditions
    )
}

$root = [System.Windows.Automation.AutomationElement]::RootElement
$recentClicks = @{}
$startedAt = Get-Date
$initialPolicy = Get-LivePolicy

Write-ToolLog "Watching for Copilot allow button: $($ButtonText -join ', ')"
Write-ToolLog "Owner: $ToolOwner"
Write-ToolLog "Repository: $ToolRepository"
Write-ToolLog "Provenance: $ToolProvenance"
Write-ToolLog "Policy file: $PolicyFile"
Write-ToolLog "Live policy: mode=$($initialPolicy.Mode), dryRun=$($initialPolicy.DryRun)"
Write-ToolLog "Target title regex: $WindowTitleRegex"
Write-ToolLog "Target process regex: $ProcessNameRegex"
Write-ToolLog "Target path regex: $TargetPathRegex"
Write-ToolLog "Context regex: $ContextTextRegex"
if ($AllowCustomTarget) {
    Write-ToolLog 'Custom target mode is enabled.'
}
if ($AllowCustomButtonText) {
    Write-ToolLog 'Custom button text mode is enabled.'
}
if ($AllowSensitivePrompt) {
    Write-ToolLog 'Sensitive prompt guard is disabled for this run by command-line override.'
}
if ($NoMouseFallback) {
    Write-ToolLog 'Mouse fallback is off; only accessibility invoke will be used.'
}
Write-ToolLog 'Press Ctrl+C to stop.'

while ($true) {
    if ($MaxSeconds -gt 0 -and ((Get-Date) - $startedAt).TotalSeconds -ge $MaxSeconds) {
        Write-ToolLog "Stopped after $MaxSeconds seconds."
        exit 0
    }

    $policy = Get-LivePolicy
    if ($policy.Mode -eq 'Disabled') {
        Start-Sleep -Milliseconds $IntervalMilliseconds
        continue
    }

    $windows = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $windowCondition)

    foreach ($window in $windows) {
        $target = Test-TargetWindow -Window $window -TitleRegex $WindowTitleRegex -ProcRegex $ProcessNameRegex -PathRegex $TargetPathRegex
        if (-not $target) {
            continue
        }

        $blockedReason = Get-BlockedPromptReason -Window $window -Patterns $BlockedPromptText

        $elements = $window.FindAll([System.Windows.Automation.TreeScope]::Descendants, $candidateCondition)
        foreach ($element in $elements) {
            $elementName = Normalize-Text $element.Current.Name
            if (-not $allowedButtonNames.ContainsKey($elementName)) {
                continue
            }

            if (-not (Test-Context -Window $window -Element $element -Regex $ContextTextRegex)) {
                continue
            }

            $label = $element.Current.Name
            $automationId = $element.Current.AutomationId
            $clickKey = "$($target.NativeWindowHandle)|$automationId|$elementName"

            if ($recentClicks.ContainsKey($clickKey)) {
                $elapsed = ((Get-Date) - $recentClicks[$clickKey]).TotalSeconds
                if ($elapsed -lt 2) {
                    continue
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($blockedReason)) {
                if (-not (Request-SensitivePromptApproval -Target $target -Window $window -Reason $blockedReason -Policy $policy)) {
                    break
                }
            }

            $recentClicks[$clickKey] = Get-Date
            $action = if ($policy.DryRun) { 'Would click' } else { 'Clicking' }
            Write-ToolLog "$action '$label' in '$($target.Title)' [$($target.ProcessName):$($target.ProcessId)]"

            $method = Invoke-AllowElement -Element $element -WindowHandle $target.NativeWindowHandle -DryRun:$policy.DryRun -NoMouseFallback:$NoMouseFallback
            Write-ToolLog "Action method: $method"

            if ($Once) {
                exit 0
            }
        }
    }

    Start-Sleep -Milliseconds $IntervalMilliseconds
}
