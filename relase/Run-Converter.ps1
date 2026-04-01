[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$converterPath = Join-Path -Path $PSScriptRoot -ChildPath "ConvertPngToJpg.ps1"
if (-not (Test-Path -LiteralPath $converterPath)) {
    exit 1
}

function Get-PreferredPwshPath {
    $bundledPwsh = Join-Path -Path $PSScriptRoot -ChildPath "tools\PowerShell7\pwsh.exe"
    if (Test-Path -LiteralPath $bundledPwsh) {
        return $bundledPwsh
    }

    $pwsh = Get-Command -Name "pwsh.exe" -ErrorAction SilentlyContinue
    if ($pwsh) {
        return [string]$pwsh.Source
    }

    return $null
}

# Keep this launcher as a no-friction fallback when wscript.exe is blocked by policy.
$runningInPwsh = $PSVersionTable.PSEdition -eq "Core"
$pwshPath = Get-PreferredPwshPath

if (-not $runningInPwsh -and $pwshPath) {
    & $pwshPath -NoProfile -STA -ExecutionPolicy Bypass -File $converterPath @Args
    exit $LASTEXITCODE
}

& $converterPath @Args
exit $LASTEXITCODE
