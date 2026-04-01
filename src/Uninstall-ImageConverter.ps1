[CmdletBinding()]
param(
    [string]$InstallRoot = (Join-Path -Path $env:LOCALAPPDATA -ChildPath "Programs\PNG-JPG-WebP-AVIF-Converter")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$installRoot = [System.IO.Path]::GetFullPath($InstallRoot)
$contextMenuScript = Join-Path -Path $installRoot -ChildPath "uninstall-context-menu.ps1"

function Write-Stage {
    param([string]$Message)
    Write-Host ""
    Write-Host $Message -ForegroundColor Cyan
}

function Remove-ContextMenuEntries {
    $commandStoreRoot = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell"

    $verbs = @(
        "PngConvert",
        "JpegConvert",
        "WebpConvert",
        "AvifConvert",
        "ImageConvert",
        "ConvertToJpg",
        "ConvertToJpgRemove",
        "ConvertToWebp",
        "ConvertToWebpRemove"
    )

    $commandStoreVerbs = @(
        "PngConvert.ToJpg",
        "PngConvert.ToJpgNew",
        "PngConvert.ToJpgRemove",
        "PngConvert.ToWebp",
        "PngConvert.ToWebpNew",
        "PngConvert.ToWebpRemove",
        "PngConvert.ToAvif",
        "PngConvert.ToAvifNew",
        "PngConvert.ToAvifRemove"
    )

    foreach ($ext in @(".png", ".jpg", ".jpeg", ".webp", ".avif")) {
        $shellRoot = "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell"
        foreach ($verb in $verbs) {
            $path = Join-Path -Path $shellRoot -ChildPath $verb
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Recurse -Force
                Write-Host "Removed context menu entry: $ext -> $verb"
            }
        }
    }

    foreach ($verb in $commandStoreVerbs) {
        $path = Join-Path -Path $commandStoreRoot -ChildPath $verb
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
            Write-Host "Removed command store entry: $verb"
        }
    }
}

Write-Stage "Removing context menu entries"
if (Test-Path -LiteralPath $contextMenuScript) {
    & $contextMenuScript
} else {
    Remove-ContextMenuEntries
}

Write-Stage "Removing installed files"
if (Test-Path -LiteralPath $installRoot) {
    $converterPath = Join-Path -Path $installRoot -ChildPath "ConvertPngToJpg.ps1"
    if (Test-Path -LiteralPath $converterPath) {
        Remove-Item -LiteralPath $installRoot -Recurse -Force
        Write-Host "Removed install folder: $installRoot"
    } else {
        throw "Refusing to remove unexpected path: $installRoot"
    }
} else {
    Write-Host "Install folder not found: $installRoot"
}

Write-Host ""
Write-Host "Uninstall complete." -ForegroundColor Green
