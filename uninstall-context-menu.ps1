Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$shellRoot = "HKCU:\Software\Classes\SystemFileAssociations\.png\shell"
$verbs = @("ConvertToJpg", "ConvertToJpgRemove", "ConvertToWebp", "ConvertToWebpRemove")

foreach ($verb in $verbs) {
    $path = Join-Path -Path $shellRoot -ChildPath $verb
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force
        Write-Host "Removed context menu entry: $verb"
    }
}

Write-Host "Uninstall complete."
