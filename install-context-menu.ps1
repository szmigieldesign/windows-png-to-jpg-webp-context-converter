Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$launcherPath = Join-Path -Path $PSScriptRoot -ChildPath "Run-Converter.vbs"
if (-not (Test-Path -LiteralPath $launcherPath)) {
    throw "Launcher script not found: $launcherPath"
}

$shellRoot = "HKCU:\Software\Classes\SystemFileAssociations\.png\shell"
$hostCommand = "wscript.exe //nologo `"$launcherPath`""
$commandLineBase = "$hostCommand `"%1`""

$entries = @(
    @{
        Name = "ConvertToJpg";
        Label = "Convert to JPG";
        Command = $commandLineBase;
    },
    @{
        Name = "ConvertToJpgRemove";
        Label = "Convert to JPG (remove)";
        Command = "$hostCommand -RemoveOriginal `"%1`"";
    },
    @{
        Name = "ConvertToWebp";
        Label = "Convert to WebP";
        Command = "$hostCommand -Format Webp `"%1`"";
    },
    @{
        Name = "ConvertToWebpRemove";
        Label = "Convert to WebP (remove)";
        Command = "$hostCommand -Format Webp -RemoveOriginal `"%1`"";
    }
)

if (-not (Test-Path -LiteralPath $shellRoot)) {
    New-Item -Path $shellRoot -Force | Out-Null
}

foreach ($entry in $entries) {
    $verbKey = Join-Path -Path $shellRoot -ChildPath $entry.Name
    $commandKey = Join-Path -Path $verbKey -ChildPath "command"

    New-Item -Path $verbKey -Force | Out-Null
    New-Item -Path $commandKey -Force | Out-Null

    New-ItemProperty -Path $verbKey -Name "(default)" -Value $entry.Label -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $verbKey -Name "MultiSelectModel" -Value "Player" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $commandKey -Name "(default)" -Value $entry.Command -PropertyType String -Force | Out-Null
}

Write-Host "Context menu installed for PNG files:"
Write-Host " - Convert to JPG"
Write-Host " - Convert to JPG (remove)"
Write-Host " - Convert to WebP"
Write-Host " - Convert to WebP (remove)"
