Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

Write-Host "Uninstall complete."
