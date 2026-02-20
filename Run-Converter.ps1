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
& $converterPath @Args
exit $LASTEXITCODE
