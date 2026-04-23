[CmdletBinding()]
param(
    [string]$VersionFile,
    [string]$SolutionFile,
    [string]$ProjectFile,
    [string]$InstallerScript,
    [string]$PublishDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$repoRoot = Split-Path -Parent $scriptRoot
$srcDotnetRoot = Join-Path -Path $repoRoot -ChildPath "src-dotnet"

if (-not $VersionFile) {
    $VersionFile = Join-Path -Path $repoRoot -ChildPath "VERSION"
}
if (-not $SolutionFile) {
    $SolutionFile = Join-Path -Path $srcDotnetRoot -ChildPath "ImageConverter.sln"
}
if (-not $ProjectFile) {
    $ProjectFile = Join-Path -Path $srcDotnetRoot -ChildPath "src\ImageConverter.Cli\ImageConverter.Cli.csproj"
}
if (-not $InstallerScript) {
    $InstallerScript = Join-Path -Path $repoRoot -ChildPath "installer\installer.iss"
}
if (-not $PublishDir) {
    $PublishDir = Join-Path -Path $repoRoot -ChildPath "build\publish\win-x64"
}

function Write-Stage {
    param([string]$Message)

    Write-Host ""
    Write-Host $Message -ForegroundColor Cyan
}

function Assert-PathExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        throw "$Label not found: $LiteralPath"
    }
}

function Use-RepoDotnetEnvironment {
    $env:DOTNET_CLI_HOME = $srcDotnetRoot
    $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE = "1"
    $env:DOTNET_NOLOGO = "1"
    $env:APPDATA = Join-Path -Path $srcDotnetRoot -ChildPath ".appdata"
    if (-not (Test-Path -LiteralPath $env:APPDATA)) {
        New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
    }
}

function Get-InnoSetupCompiler {
    $command = Get-Command -Name "ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) {
        return [string]$command.Source
    }

    $candidatePaths = @(
        (Join-Path -Path $env:LOCALAPPDATA -ChildPath "Programs\Inno Setup 6\ISCC.exe"),
        (Join-Path -Path $env:ProgramFiles -ChildPath "Inno Setup 6\ISCC.exe")
    )

    if (${env:ProgramFiles(x86)}) {
        $candidatePaths += (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath "Inno Setup 6\ISCC.exe")
    }

    foreach ($path in $candidatePaths) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return $path
        }
    }

    return $null
}

function Get-FourPartVersion {
    param([Parameter(Mandatory = $true)][string]$Version)

    $parts = $Version.Split(".")
    while ($parts.Count -lt 4) {
        $parts += "0"
    }

    return ($parts[0..3] -join ".")
}

Assert-PathExists -LiteralPath $VersionFile -Label "Version file"
Assert-PathExists -LiteralPath $SolutionFile -Label "Solution"
Assert-PathExists -LiteralPath $ProjectFile -Label "CLI project"
Assert-PathExists -LiteralPath $InstallerScript -Label "Installer script"

$version = (Get-Content -LiteralPath $VersionFile -Raw).Trim()
if (-not $version) {
    throw "VERSION file is empty."
}

$fileVersion = Get-FourPartVersion -Version $version
$releaseDir = Join-Path -Path $repoRoot -ChildPath "release"
$publishDir = [System.IO.Path]::GetFullPath($PublishDir)
$shellProjectFile = Join-Path -Path $srcDotnetRoot -ChildPath "src\ImageConverter.Shell\ImageConverter.Shell.csproj"
$testsProjectFile = Join-Path -Path $srcDotnetRoot -ChildPath "tests\ImageConverter.Tests\ImageConverter.Tests.csproj"
$restoreProjects = @(
    $ProjectFile,
    $shellProjectFile,
    $testsProjectFile
)

Use-RepoDotnetEnvironment

Write-Stage "Restoring projects"
foreach ($restoreProject in $restoreProjects) {
    dotnet restore $restoreProject --configfile (Join-Path -Path $srcDotnetRoot -ChildPath "NuGet.Config")
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet restore failed for $restoreProject with exit code $LASTEXITCODE."
    }
}

Write-Stage "Building solution"
dotnet build $SolutionFile -c Release --no-restore -m:1
if ($LASTEXITCODE -ne 0) {
    throw "dotnet build failed with exit code $LASTEXITCODE."
}

Write-Stage "Running tests"
dotnet test $testsProjectFile -c Release --no-build
if ($LASTEXITCODE -ne 0) {
    throw "dotnet test failed with exit code $LASTEXITCODE."
}

Write-Stage "Restoring publish dependencies"
dotnet restore $ProjectFile `
    --configfile (Join-Path -Path $srcDotnetRoot -ChildPath "NuGet.Config") `
    -r win-x64
if ($LASTEXITCODE -ne 0) {
    throw "dotnet restore for publish failed with exit code $LASTEXITCODE."
}

if (Test-Path -LiteralPath $publishDir) {
    Remove-Item -LiteralPath $publishDir -Recurse -Force
}
New-Item -ItemType Directory -Path $publishDir -Force | Out-Null

Write-Stage "Publishing ImageConverter.exe"
dotnet publish $ProjectFile `
    -c Release `
    --no-restore `
    -r win-x64 `
    --self-contained true `
    -o $publishDir `
    -p:PublishSingleFile=true `
    -p:EnableCompressionInSingleFile=true `
    -p:PublishTrimmed=false `
    -p:Version=$version `
    -p:FileVersion=$fileVersion `
    -p:InformationalVersion=$version
if ($LASTEXITCODE -ne 0) {
    throw "dotnet publish failed with exit code $LASTEXITCODE."
}

$publishedExe = Join-Path -Path $publishDir -ChildPath "ImageConverter.exe"
Assert-PathExists -LiteralPath $publishedExe -Label "Published executable"

$compilerPath = Get-InnoSetupCompiler
if (-not $compilerPath) {
    throw "Inno Setup compiler not found. Install JRSoftware.InnoSetup, then rerun this build."
}

if (-not (Test-Path -LiteralPath $releaseDir)) {
    New-Item -ItemType Directory -Path $releaseDir -Force | Out-Null
}

Write-Stage "Building Setup.exe version $version"
& $compilerPath "/DAppVersion=$version" "/DPublishDir=$publishDir" $InstallerScript
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup build failed with exit code $LASTEXITCODE."
}

$setupPath = Join-Path -Path $releaseDir -ChildPath "Setup.exe"
Assert-PathExists -LiteralPath $setupPath -Label "Installer output"

Write-Host ""
Write-Host "Published app: $publishedExe" -ForegroundColor Green
Write-Host "Built installer: $setupPath" -ForegroundColor Green
