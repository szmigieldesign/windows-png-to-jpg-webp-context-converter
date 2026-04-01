[CmdletBinding()]
param(
    [string]$VersionFile,
    [string]$InstallerScript
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $VersionFile) {
    $VersionFile = Join-Path -Path $scriptRoot -ChildPath "VERSION"
}
if (-not $InstallerScript) {
    $InstallerScript = Join-Path -Path $scriptRoot -ChildPath "installer.iss"
}

function Write-Stage {
    param([string]$Message)
    Write-Host ""
    Write-Host $Message -ForegroundColor Cyan
}

if (-not (Test-Path -LiteralPath $VersionFile)) {
    throw "Version file not found: $VersionFile"
}

if (-not (Test-Path -LiteralPath $InstallerScript)) {
    throw "Installer script not found: $InstallerScript"
}

$version = (Get-Content -LiteralPath $VersionFile -Raw).Trim()
if (-not $version) {
    throw "VERSION file is empty."
}

function Get-InnoSetupCompiler {
    $candidatePaths = @()

    $command = Get-Command -Name "ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        return [string]$command.Source
    }

    $candidatePaths += Join-Path -Path $env:LOCALAPPDATA -ChildPath "Programs\Inno Setup 6\ISCC.exe"
    $candidatePaths += Join-Path -Path $env:ProgramFiles -ChildPath "Inno Setup 6\ISCC.exe"
    if (${env:ProgramFiles(x86)}) {
        $candidatePaths += Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath "Inno Setup 6\ISCC.exe"
    }

    foreach ($path in $candidatePaths) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    return $null
}

$compilerPath = Get-InnoSetupCompiler
if (-not $compilerPath) {
    throw "Inno Setup compiler not found. Install JRSoftware.InnoSetup, then rerun this build."
}

Write-Stage "Building Setup.exe version $version"
& $compilerPath "/DAppVersion=$version" $InstallerScript
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup build failed with exit code $LASTEXITCODE."
}

$setupPath = Join-Path -Path $scriptRoot -ChildPath "relase\Setup.exe"
if (-not (Test-Path -LiteralPath $setupPath)) {
    throw "Build completed but Setup.exe was not produced: $setupPath"
}

Write-Host ""
Write-Host "Built installer: $setupPath" -ForegroundColor Green
