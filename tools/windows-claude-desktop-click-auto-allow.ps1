param(
    [string[]]$ButtonText,
    [string]$WindowTitleRegex = '',
    [string]$ProcessNameRegex = '(?i)^claude$',
    [string]$TargetPathRegex = '(?i)(\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude\.exe$|\\anthropicclaude\\.*\\claude\.exe$|\\windowsapps\\claude_[^\\]+\\app\\claude\.exe$|\\appdata\\roaming\\claude\\claude-code\\[^\\]+\\claude\.exe$)',
    [string[]]$BlockedPromptText,
    [string]$PolicyFile = '',
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
Add-Type -AssemblyName System.Windows.Forms
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
$DefaultTargetPathRegex = '(?i)(\\node_modules\\@anthropic-ai\\claude-code\\bin\\claude\.exe$|\\anthropicclaude\\.*\\claude\.exe$|\\windowsapps\\claude_[^\\]+\\app\\claude\.exe$|\\appdata\\roaming\\claude\\claude-code\\[^\\]+\\claude\.exe$)'
$CommandLinePreferProvided = $PSBoundParameters.ContainsKey('Prefer')
$CommandLineDryRunProvided = $PSBoundParameters.ContainsKey('DryRun')
$CommandLineDiagnosticProvided = $PSBoundParameters.ContainsKey('Diagnostic')

if ([string]::IsNullOrWhiteSpace($PolicyFile)) {
    $PolicyFile = Join-Path $PSScriptRoot 'auto-allow-policy.json'
}

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
    $preferValue = $Prefer
    $dryRunValue = $false
    $diagnosticValue = $false

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

                if ($config.PSObject.Properties.Name -contains 'prefer') {
                    $candidatePrefer = "$($config.prefer)".Trim()
                    if ($candidatePrefer -in @('Always', 'Once')) {
                        $preferValue = $candidatePrefer
                    }
                }

                if ($config.PSObject.Properties.Name -contains 'dryRun') {
                    $dryRunValue = ConvertTo-PolicyBool -Value $config.dryRun -Default $dryRunValue
                }

                if ($config.PSObject.Properties.Name -contains 'diagnostic') {
                    $diagnosticValue = ConvertTo-PolicyBool -Value $config.diagnostic -Default $diagnosticValue
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

    if ($CommandLinePreferProvided) {
        $preferValue = $Prefer
    }

    if ($CommandLineDryRunProvided) {
        $dryRunValue = [bool]$DryRun
    }

    if ($CommandLineDiagnosticProvided) {
        $diagnosticValue = [bool]$Diagnostic
    }

    [pscustomobject]@{
        Mode = $mode
        Prefer = $preferValue
        DryRun = $dryRunValue
        Diagnostic = $diagnosticValue
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
Claude approval prompt contains sensitive text.

Target : $($Target.Title)
Process: $($Target.ProcessName):$($Target.ProcessId)
Matched: $Reason

Allow this one automatic click?
"@

    $result = [System.Windows.Forms.MessageBox]::Show(
        $message,
        'Claude Auto Allow - policy confirmation',
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
    $yFractions = @(0.78, 0.80, 0.86, 0.88, 0.90)
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
    $regionBottom = $windowRect.Top + ($windowRect.Height * 0.94)
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
    $allowKo = New-TextFromCodePoints @(0xD5C8, 0xC6A9)

    $ButtonText = @(
        'Always allow',
        'Always Allow',
        $alwaysAllowKo,
        $alwaysAllowKoNoSpace,
        'Allow once',
        'Allow Once',
        $allowOnceKo,
        $allowOnceKoNoFirstSpace,
        $allowOnceKoNoSpace,
        'Allow',
        $allowKo
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
$initialPolicy = Get-LivePolicy

Write-ToolLog "Watching for button: $($ButtonText -join ', ')"
Write-ToolLog "Owner: $ToolOwner"
Write-ToolLog "Repository: $ToolRepository"
Write-ToolLog "Provenance: $ToolProvenance"
Write-ToolLog "Policy file: $PolicyFile"
Write-ToolLog "Live policy: mode=$($initialPolicy.Mode), prefer=$($initialPolicy.Prefer), dryRun=$($initialPolicy.DryRun), diagnostic=$($initialPolicy.Diagnostic)"
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
    Write-ToolLog 'Sensitive prompt guard is disabled for this run by command-line override.'
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

    $policy = Get-LivePolicy
    if ($policy.Mode -eq 'Disabled') {
        Start-Sleep -Milliseconds $IntervalMilliseconds
        continue
    }

    $targetWindows = Get-TargetWindows -TitleRegex $WindowTitleRegex -ProcRegex $ProcessNameRegex -PathRegex $TargetPathRegex

    foreach ($target in $targetWindows) {
        $window = $target.Element
        $blockedReason = Get-BlockedPromptReason -Window $window -Patterns $BlockedPromptText

        $elements = Get-PointSampledButtonElements -Window $window
        $candidates = Get-AllowedButtonCandidates -Elements $elements -AllowedNames $allowedButtonNames -AlwaysNames $alwaysButtonNames -OnceNames $onceButtonNames -Prefer $policy.Prefer -Diagnostic:$policy.Diagnostic

        if (-not $DisableCoveredFallback -and $candidates.Count -eq 0) {
            $elements = Get-RegionButtonElements -Window $window
            $candidates = Get-AllowedButtonCandidates -Elements $elements -AllowedNames $allowedButtonNames -AlwaysNames $alwaysButtonNames -OnceNames $onceButtonNames -Prefer $policy.Prefer -Diagnostic:$policy.Diagnostic
        }

        if ($DeepScan -and $candidates.Count -eq 0) {
            $elements = Get-VisibleButtonElements -Window $window
            $candidates = Get-AllowedButtonCandidates -Elements $elements -AllowedNames $allowedButtonNames -AlwaysNames $alwaysButtonNames -OnceNames $onceButtonNames -Prefer $policy.Prefer -Diagnostic:$policy.Diagnostic
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

            if (-not [string]::IsNullOrWhiteSpace($blockedReason)) {
                if (-not (Request-SensitivePromptApproval -Target $target -Window $window -Reason $blockedReason -Policy $policy)) {
                    break
                }
            }

            $recentClicks[$clickKey] = Get-Date
            $action = if ($policy.DryRun) { 'Would click' } else { 'Clicking' }
            Write-ToolLog "$action '$buttonLabel' in '$($target.Title)' [$($target.ProcessName):$($target.ProcessId)]"

            Invoke-Button -Element $element -DryRun:$policy.DryRun | Out-Null

            if ($Once) {
                exit 0
            }

            break
        }
    }

    Start-Sleep -Milliseconds $IntervalMilliseconds
}
