[CmdletBinding()]
param(
    [string]$VersionFile,
    [string]$InstallerScript
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = Split-Path -Parent $scriptRoot
if (-not $VersionFile) {
    $VersionFile = Join-Path -Path $repoRoot -ChildPath "VERSION"
}
if (-not $InstallerScript) {
    $InstallerScript = Join-Path -Path $repoRoot -ChildPath "installer\installer.iss"
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

$releaseDir = Join-Path -Path $repoRoot -ChildPath "release"
if (-not (Test-Path -LiteralPath $releaseDir)) {
    New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
}

function Remove-ReleaseTempFiles {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like "*.tmp" -or
            $_.Name -like "RCX*.tmp" -or
            $_.Name -like "Setup.e32*"
        } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

Remove-ReleaseTempFiles -Path $releaseDir

Write-Stage "Building Setup.exe version $version"
& $compilerPath "/DAppVersion=$version" $InstallerScript
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup build failed with exit code $LASTEXITCODE."
}

$setupPath = Join-Path -Path $releaseDir -ChildPath "Setup.exe"
if (-not (Test-Path -LiteralPath $setupPath)) {
    throw "Build completed but Setup.exe was not produced: $setupPath"
}

Remove-ReleaseTempFiles -Path $releaseDir

Write-Host ""
Write-Host "Built installer: $setupPath" -ForegroundColor Green
