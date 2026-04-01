[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path -Path $env:LOCALAPPDATA -ChildPath "Programs\PNG-JPG-WebP-AVIF-Converter"),
    [ValidateSet("Auto", "Vbs", "PowerShell")]
    [string]$LauncherMode = "PowerShell",
    [switch]$NoCopy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
} catch {
    # Older hosts may not expose the flag. Ignore and continue.
}

$sourceRoot = $PSScriptRoot
$installRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$magickPackageId = "ImageMagick.ImageMagick"

function Write-Stage {
    param([string]$Message)
    Write-Host ""
    Write-Host $Message -ForegroundColor Cyan
}

function Test-Command {
    param([Parameter(Mandatory = $true)][string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Assert-SourceFiles {
    $required = @(
        "ConvertPngToJpg.ps1",
        "install-context-menu.ps1",
        "uninstall-context-menu.ps1",
        "Run-Converter.ps1",
        "Run-Converter.vbs",
        "README.md",
        "LICENSE",
        "VERSION",
        "Install-ImageConverter.ps1",
        "Uninstall-ImageConverter.ps1",
        "Setup.cmd",
        "Uninstall.cmd"
    )

    foreach ($name in $required) {
        $path = Join-Path -Path $sourceRoot -ChildPath $name
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Required package file not found: $path"
        }
    }
}

function Copy-PackageFiles {
    if (-not (Test-Path -LiteralPath $installRoot)) {
        New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
    }

    $files = @(
        "ConvertPngToJpg.ps1",
        "install-context-menu.ps1",
        "uninstall-context-menu.ps1",
        "Run-Converter.ps1",
        "Run-Converter.vbs",
        "README.md",
        "LICENSE",
        "VERSION",
        "Install-ImageConverter.ps1",
        "Uninstall-ImageConverter.ps1",
        "Setup.cmd",
        "Uninstall.cmd"
    )

    foreach ($name in $files) {
        $sourcePath = Join-Path -Path $sourceRoot -ChildPath $name
        $targetPath = Join-Path -Path $installRoot -ChildPath $name
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
    }
}

function Get-MagickExePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SearchRoot
    )

    if (Test-Path -LiteralPath $SearchRoot) {
        $bundled = Get-ChildItem -Path $SearchRoot -Recurse -Filter "magick.exe" -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($bundled) {
            return [string]$bundled.FullName
        }
    }

    $cmd = Get-Command -Name "magick.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) {
        return [string]$cmd.Source
    }

    return $null
}

function Install-MagickWithWinget {
    Write-Stage "Checking ImageMagick via winget"

    if (-not (Test-Command -Name "winget.exe")) {
        return $false
    }

    $args = @(
        "install",
        "--id", $magickPackageId,
        "-e",
        "--silent",
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--disable-interactivity"
    )

    & winget.exe @args
    if ($LASTEXITCODE -eq 0) {
        $available = Get-MagickExePath -SearchRoot (Join-Path -Path $installRoot -ChildPath "tools\ImageMagick")
        if ($available) {
            return $true
        }
    }

    $installed = Get-MagickExePath -SearchRoot (Join-Path -Path $installRoot -ChildPath "tools\ImageMagick")
    return [bool]$installed
}

function Get-ImageMagickReleaseAsset {
    Write-Stage "Locating ImageMagick portable package"

    $headers = @{
        "User-Agent" = "ImageConverterInstaller/1.0"
        "Accept" = "application/vnd.github+json"
    }

    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/ImageMagick/ImageMagick/releases/latest" -Headers $headers -Method Get
    $assets = @($release.assets)
    if (-not $assets -or $assets.Count -eq 0) {
        throw "ImageMagick release did not include any downloadable assets."
    }

    $patterns = @(
        "(?i)portable.*x64.*\.zip$",
        "(?i)x64.*\.zip$",
        "(?i)\.zip$"
    )

    foreach ($pattern in $patterns) {
        $candidate = $assets | Where-Object { $_.name -match $pattern } | Select-Object -First 1
        if ($candidate) {
            return $candidate
        }
    }

    throw "No suitable ImageMagick zip asset was found in the latest release."
}

function Install-MagickPortable {
    Write-Stage "Downloading ImageMagick portable package"

    $asset = Get-ImageMagickReleaseAsset
    $packageDir = Join-Path -Path $installRoot -ChildPath "tools\ImageMagick"
    if (-not (Test-Path -LiteralPath $packageDir)) {
        New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
    }

    $tempZip = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("imagemagick-{0}.zip" -f ([Guid]::NewGuid().ToString("N")))
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -Headers @{
            "User-Agent" = "ImageConverterInstaller/1.0"
        } -OutFile $tempZip

        $stagingDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("imagemagick-{0}" -f ([Guid]::NewGuid().ToString("N")))
        New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null
        try {
            Expand-Archive -LiteralPath $tempZip -DestinationPath $stagingDir -Force

            Remove-Item -LiteralPath $packageDir -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Path $packageDir -Force | Out-Null

            Copy-Item -Path (Join-Path -Path $stagingDir -ChildPath "*") -Destination $packageDir -Recurse -Force
        } finally {
            Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    } finally {
        Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
    }

    $magick = Get-MagickExePath -SearchRoot $packageDir
    return [bool]$magick
}

function Ensure-ImageMagick {
    $existing = Get-MagickExePath -SearchRoot (Join-Path -Path $installRoot -ChildPath "tools\ImageMagick")
    if ($existing) {
        Write-Host "ImageMagick found: $existing"
        return
    }

    if (Install-MagickWithWinget) {
        Write-Host "ImageMagick installed via winget."
        return
    }

    $portableError = $null
    try {
        if (Install-MagickPortable) {
            Write-Host "ImageMagick installed in the app folder."
            return
        }
    } catch {
        $portableError = $_.Exception.Message
    }

    $extra = if ($portableError) { "`n`nPortable fallback error:`n$portableError" } else { "" }
    throw @"
ImageMagick could not be installed automatically.
Install it manually with:
winget install ImageMagick.ImageMagick
"@ + $extra
}

function Resolve-LauncherMode {
    param([string]$Mode)

    if ($Mode -ne "Auto") {
        return $Mode
    }

    return if (Test-Command -Name "wscript.exe") { "Vbs" } else { "PowerShell" }
}

function Invoke-ContextMenuInstall {
    $resolvedLauncherMode = Resolve-LauncherMode -Mode $LauncherMode
    $installScript = Join-Path -Path $installRoot -ChildPath "install-context-menu.ps1"
    if (-not (Test-Path -LiteralPath $installScript)) {
        throw "Installed context menu script not found: $installScript"
    }

    Write-Stage "Registering context menu"
    & $installScript -LauncherMode $resolvedLauncherMode
}

Assert-SourceFiles
Write-Stage "Installing to $installRoot"
if (-not $NoCopy) {
    Copy-PackageFiles
}
Ensure-ImageMagick
Invoke-ContextMenuInstall

Write-Host ""
Write-Host "Install complete." -ForegroundColor Green
Write-Host "Installed files: $installRoot"
Write-Host "Right-click PNG, JPG, JPEG, WEBP, or AVIF files to use the new menu."
