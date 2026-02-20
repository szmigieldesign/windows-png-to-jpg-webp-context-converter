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

# Keep this launcher as a no-friction fallback when wscript.exe is blocked by policy.
$runningInPwsh = $PSVersionTable.PSEdition -eq "Core"
$pwsh = Get-Command -Name "pwsh.exe" -ErrorAction SilentlyContinue

if (-not $runningInPwsh -and $pwsh) {
    & $pwsh.Source -NoProfile -STA -ExecutionPolicy Bypass -File $converterPath @Args
    exit $LASTEXITCODE
}

& $converterPath @Args
exit $LASTEXITCODE
