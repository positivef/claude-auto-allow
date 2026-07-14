param(
    [string]$Mode,
    [string]$Prefer,
    [string]$CliPermissionMode,
    [string]$CliAuto,
    [string]$DryRun,
    [string]$Diagnostic,
    [string]$PolicyFile = '',
    [switch]$Show
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($PolicyFile)) {
    $PolicyFile = Join-Path $PSScriptRoot 'auto-allow-policy.json'
}

$validModes = @('AlwaysAllow', 'PolicyAsk', 'PolicyBlock', 'Disabled')
$validPrefer = @('Always', 'Once')
$validCliPermissionModes = @('Auto', 'Manual')
$validSwitch = @('On', 'Off', 'True', 'False', '1', '0', 'Yes', 'No')

function ConvertTo-ControlBool {
    param(
        [string]$Value,
        [bool]$Current
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Current
    }

    switch ($Value.Trim().ToLowerInvariant()) {
        'on' { return $true }
        'true' { return $true }
        '1' { return $true }
        'yes' { return $true }
        'off' { return $false }
        'false' { return $false }
        '0' { return $false }
        'no' { return $false }
        default { throw "Invalid boolean value '$Value'. Use On or Off." }
    }
}

function Get-CurrentPolicy {
    $policy = [ordered]@{
        mode = 'PolicyAsk'
        prefer = 'Always'
        cliPermissionMode = 'Auto'
        dryRun = $false
        diagnostic = $false
        updatedAt = (Get-Date).ToUniversalTime().ToString('o')
        schema = 'claude-auto-allow-policy-v1'
    }

    if (Test-Path -LiteralPath $PolicyFile -PathType Leaf) {
        try {
            $json = Get-Content -LiteralPath $PolicyFile -Raw -Encoding UTF8
            if (-not [string]::IsNullOrWhiteSpace($json)) {
                $existing = $json | ConvertFrom-Json
                foreach ($name in @('mode', 'prefer', 'cliPermissionMode', 'dryRun', 'diagnostic', 'schema')) {
                    if ($existing.PSObject.Properties.Name -contains $name) {
                        $policy[$name] = $existing.$name
                    }
                }
            }
        }
        catch {
            Write-Warning "Existing policy file could not be read. A new policy will be written. Error: $($_.Exception.Message)"
        }
    }

    return $policy
}

if (-not [string]::IsNullOrWhiteSpace($Mode) -and $validModes -notcontains $Mode) {
    throw "Invalid Mode '$Mode'. Use one of: $($validModes -join ', ')"
}

if (-not [string]::IsNullOrWhiteSpace($Prefer) -and $validPrefer -notcontains $Prefer) {
    throw "Invalid Prefer '$Prefer'. Use one of: $($validPrefer -join ', ')"
}

if (-not [string]::IsNullOrWhiteSpace($CliPermissionMode) -and $validCliPermissionModes -notcontains $CliPermissionMode) {
    throw "Invalid CliPermissionMode '$CliPermissionMode'. Use one of: $($validCliPermissionModes -join ', ')"
}

if (-not [string]::IsNullOrWhiteSpace($CliAuto) -and $validSwitch -notcontains $CliAuto) {
    throw "Invalid CliAuto '$CliAuto'. Use On or Off."
}

if (-not [string]::IsNullOrWhiteSpace($DryRun) -and $validSwitch -notcontains $DryRun) {
    throw "Invalid DryRun '$DryRun'. Use On or Off."
}

if (-not [string]::IsNullOrWhiteSpace($Diagnostic) -and $validSwitch -notcontains $Diagnostic) {
    throw "Invalid Diagnostic '$Diagnostic'. Use On or Off."
}

$policy = Get-CurrentPolicy
if ($validCliPermissionModes -notcontains $policy.cliPermissionMode) {
    $policy.cliPermissionMode = 'Auto'
}

if (-not [string]::IsNullOrWhiteSpace($Mode)) {
    $policy.mode = $Mode
}
if (-not [string]::IsNullOrWhiteSpace($Prefer)) {
    $policy.prefer = $Prefer
}
if (-not [string]::IsNullOrWhiteSpace($CliPermissionMode)) {
    $policy.cliPermissionMode = $CliPermissionMode
}
if (-not [string]::IsNullOrWhiteSpace($CliAuto)) {
    $policy.cliPermissionMode = if (ConvertTo-ControlBool -Value $CliAuto -Current $true) { 'Auto' } else { 'Manual' }
}
$currentDryRun = ConvertTo-ControlBool -Value "$($policy.dryRun)" -Current $false
$currentDiagnostic = ConvertTo-ControlBool -Value "$($policy.diagnostic)" -Current $false
$policy.dryRun = ConvertTo-ControlBool -Value $DryRun -Current $currentDryRun
$policy.diagnostic = ConvertTo-ControlBool -Value $Diagnostic -Current $currentDiagnostic
$policy.updatedAt = (Get-Date).ToUniversalTime().ToString('o')
$policy.schema = 'claude-auto-allow-policy-v1'

$directory = Split-Path -Parent $PolicyFile
if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory -PathType Container)) {
    New-Item -ItemType Directory -Path $directory | Out-Null
}

$jsonOut = [pscustomobject]$policy | ConvertTo-Json -Depth 4
Set-Content -LiteralPath $PolicyFile -Value $jsonOut -Encoding UTF8

Write-Host "Policy file: $PolicyFile"
Write-Host "Mode       : $($policy.mode)"
Write-Host "Prefer     : $($policy.prefer)"
Write-Host "CLI mode   : $($policy.cliPermissionMode)"
Write-Host "Dry run    : $($policy.dryRun)"
Write-Host "Diagnostic : $($policy.diagnostic)"

if ($Show) {
    Write-Host ''
    Get-Content -LiteralPath $PolicyFile -Raw -Encoding UTF8
}
