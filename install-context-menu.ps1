param(
    [ValidateSet("Vbs", "PowerShell")]
    [string]$LauncherMode = "Vbs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$converterPath = Join-Path -Path $PSScriptRoot -ChildPath "ConvertPngToJpg.ps1"
if (-not (Test-Path -LiteralPath $converterPath)) {
    throw "Converter script not found: $converterPath"
}

$vbsLauncherPath = Join-Path -Path $PSScriptRoot -ChildPath "Run-Converter.vbs"
$psLauncherPath = Join-Path -Path $PSScriptRoot -ChildPath "Run-Converter.ps1"

if ($LauncherMode -eq "Vbs" -and -not (Test-Path -LiteralPath $vbsLauncherPath)) {
    throw "VBS launcher not found: $vbsLauncherPath"
}

if ($LauncherMode -eq "PowerShell" -and -not (Test-Path -LiteralPath $psLauncherPath)) {
    throw "PowerShell launcher not found: $psLauncherPath"
}

$commandStoreRoot = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell"

$hostCommand = if ($LauncherMode -eq "Vbs") {
    "wscript.exe //nologo `"$vbsLauncherPath`""
} else {
    "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$psLauncherPath`""
}

function Install-SubmenuForExtension {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Extension,
        [Parameter(Mandatory = $true)]
        [string]$MenuKey,
        [Parameter(Mandatory = $true)]
        [string]$MenuLabel,
        [Parameter(Mandatory = $true)]
        [string]$MenuIcon,
        [Parameter(Mandatory = $true)]
        [array]$Entries
    )

    $associationShellRoot = "HKCU:\Software\Classes\SystemFileAssociations\$Extension\shell"
    $submenuKeyPath = Join-Path -Path $associationShellRoot -ChildPath $MenuKey
    $submenuShellPath = Join-Path -Path $submenuKeyPath -ChildPath "shell"

    if (-not (Test-Path -LiteralPath $associationShellRoot)) {
        New-Item -Path $associationShellRoot -Force | Out-Null
    }

    if (Test-Path -LiteralPath $submenuKeyPath) {
        Remove-Item -LiteralPath $submenuKeyPath -Recurse -Force
    }

    New-Item -Path $submenuKeyPath -Force | Out-Null
    New-Item -Path $submenuShellPath -Force | Out-Null
    New-ItemProperty -Path $submenuKeyPath -Name "MUIVerb" -Value $MenuLabel -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $submenuKeyPath -Name "Icon" -Value $MenuIcon -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $submenuKeyPath -Name "MultiSelectModel" -Value "Player" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $submenuKeyPath -Name "SubCommands" -Value "" -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $submenuKeyPath -Name "CommandFlags" -Value 32 -PropertyType DWord -Force | Out-Null

    $parentCommandPath = Join-Path -Path $submenuKeyPath -ChildPath "command"
    if (Test-Path -LiteralPath $parentCommandPath) {
        Remove-Item -LiteralPath $parentCommandPath -Recurse -Force
    }

    foreach ($entry in $Entries) {
        $verbKey = Join-Path -Path $submenuShellPath -ChildPath $entry.Id
        $commandKey = Join-Path -Path $verbKey -ChildPath "command"

        New-Item -Path $verbKey -Force | Out-Null
        New-Item -Path $commandKey -Force | Out-Null

        New-ItemProperty -Path $verbKey -Name "(default)" -Value $entry.Label -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $verbKey -Name "MUIVerb" -Value $entry.Label -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $verbKey -Name "Icon" -Value $entry.Icon -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $verbKey -Name "MultiSelectModel" -Value "Player" -PropertyType String -Force | Out-Null
        if ($entry -is [System.Collections.IDictionary] -and $entry.Contains("SeparatorBefore") -and [bool]$entry["SeparatorBefore"]) {
            # ECF_SEPARATORBEFORE = 0x20
            New-ItemProperty -Path $verbKey -Name "CommandFlags" -Value 32 -PropertyType DWord -Force | Out-Null
            if (Get-ItemProperty -Path $verbKey -Name "SeparatorBefore" -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $verbKey -Name "SeparatorBefore" -ErrorAction SilentlyContinue
            }
        } else {
            if (Get-ItemProperty -Path $verbKey -Name "CommandFlags" -ErrorAction SilentlyContinue) {
                Remove-ItemProperty -Path $verbKey -Name "CommandFlags" -ErrorAction SilentlyContinue
            }
        }
        New-ItemProperty -Path $commandKey -Name "(default)" -Value $entry.Command -PropertyType String -Force | Out-Null
    }
}

$pngEntries = @(
    @{
        Id = "10_ToJpg";
        Label = "Convert to JPG";
        Icon = "%SystemRoot%\System32\imageres.dll,-72";
        Command = "$hostCommand `"%1`"";
    },
    @{
        Id = "11_ToJpgNew";
        Label = "Convert to JPG (new folder)";
        Icon = "%SystemRoot%\System32\imageres.dll,-72";
        Command = "$hostCommand -OutputMode New `"%1`"";
    },
    @{
        Id = "12_ToJpgRemove";
        Label = "Convert to JPG (remove)";
        Icon = "%SystemRoot%\System32\shell32.dll,-240";
        Command = "$hostCommand -RemoveOriginal `"%1`"";
    },
    @{
        Id = "20_ToWebp";
        Label = "Convert to WebP";
        Icon = "%SystemRoot%\System32\imageres.dll,-71";
        SeparatorBefore = $true;
        Command = "$hostCommand -Format Webp `"%1`"";
    },
    @{
        Id = "21_ToWebpNew";
        Label = "Convert to WebP (new folder)";
        Icon = "%SystemRoot%\System32\imageres.dll,-71";
        Command = "$hostCommand -Format Webp -OutputMode New `"%1`"";
    },
    @{
        Id = "22_ToWebpRemove";
        Label = "Convert to WebP (remove)";
        Icon = "%SystemRoot%\System32\shell32.dll,-240";
        Command = "$hostCommand -Format Webp -RemoveOriginal `"%1`"";
    },
    @{
        Id = "30_ToAvif";
        Label = "Convert to AVIF";
        Icon = "%SystemRoot%\System32\imageres.dll,-71";
        SeparatorBefore = $true;
        Command = "$hostCommand -Format Avif `"%1`"";
    },
    @{
        Id = "31_ToAvifNew";
        Label = "Convert to AVIF (new folder)";
        Icon = "%SystemRoot%\System32\imageres.dll,-71";
        Command = "$hostCommand -Format Avif -OutputMode New `"%1`"";
    },
    @{
        Id = "32_ToAvifRemove";
        Label = "Convert to AVIF (remove)";
        Icon = "%SystemRoot%\System32\shell32.dll,-240";
        Command = "$hostCommand -Format Avif -RemoveOriginal `"%1`"";
    }
)

$jpegEntries = @(
    @{
        Id = "20_ToWebp";
        Label = "Convert to WebP";
        Icon = "%SystemRoot%\System32\imageres.dll,-71";
        Command = "$hostCommand -Format Webp `"%1`"";
    },
    @{
        Id = "21_ToWebpNew";
        Label = "Convert to WebP (new folder)";
        Icon = "%SystemRoot%\System32\imageres.dll,-71";
        Command = "$hostCommand -Format Webp -OutputMode New `"%1`"";
    },
    @{
        Id = "22_ToWebpRemove";
        Label = "Convert to WebP (remove)";
        Icon = "%SystemRoot%\System32\shell32.dll,-240";
        Command = "$hostCommand -Format Webp -RemoveOriginal `"%1`"";
    },
    @{
        Id = "30_ToAvif";
        Label = "Convert to AVIF";
        Icon = "%SystemRoot%\System32\imageres.dll,-71";
        SeparatorBefore = $true;
        Command = "$hostCommand -Format Avif `"%1`"";
    },
    @{
        Id = "31_ToAvifNew";
        Label = "Convert to AVIF (new folder)";
        Icon = "%SystemRoot%\System32\imageres.dll,-71";
        Command = "$hostCommand -Format Avif -OutputMode New `"%1`"";
    },
    @{
        Id = "32_ToAvifRemove";
        Label = "Convert to AVIF (remove)";
        Icon = "%SystemRoot%\System32\shell32.dll,-240";
        Command = "$hostCommand -Format Avif -RemoveOriginal `"%1`"";
    }
)

$webpEntries = @(
    @{
        Id = "10_ToJpg";
        Label = "Convert to JPG";
        Icon = "%SystemRoot%\System32\imageres.dll,-72";
        Command = "$hostCommand -Format Jpg `"%1`"";
    },
    @{
        Id = "11_ToJpgNew";
        Label = "Convert to JPG (new folder)";
        Icon = "%SystemRoot%\System32\imageres.dll,-72";
        Command = "$hostCommand -Format Jpg -OutputMode New `"%1`"";
    },
    @{
        Id = "12_ToJpgRemove";
        Label = "Convert to JPG (remove)";
        Icon = "%SystemRoot%\System32\shell32.dll,-240";
        Command = "$hostCommand -Format Jpg -RemoveOriginal `"%1`"";
    },
    @{
        Id = "30_ToAvif";
        Label = "Convert to AVIF";
        Icon = "%SystemRoot%\System32\imageres.dll,-71";
        SeparatorBefore = $true;
        Command = "$hostCommand -Format Avif `"%1`"";
    },
    @{
        Id = "31_ToAvifNew";
        Label = "Convert to AVIF (new folder)";
        Icon = "%SystemRoot%\System32\imageres.dll,-71";
        Command = "$hostCommand -Format Avif -OutputMode New `"%1`"";
    },
    @{
        Id = "32_ToAvifRemove";
        Label = "Convert to AVIF (remove)";
        Icon = "%SystemRoot%\System32\shell32.dll,-240";
        Command = "$hostCommand -Format Avif -RemoveOriginal `"%1`"";
    }
)

$avifEntries = @(
    @{
        Id = "10_ToJpg";
        Label = "Convert to JPG";
        Icon = "%SystemRoot%\System32\imageres.dll,-72";
        Command = "$hostCommand -Format Jpg `"%1`"";
    },
    @{
        Id = "11_ToJpgNew";
        Label = "Convert to JPG (new folder)";
        Icon = "%SystemRoot%\System32\imageres.dll,-72";
        Command = "$hostCommand -Format Jpg -OutputMode New `"%1`"";
    },
    @{
        Id = "12_ToJpgRemove";
        Label = "Convert to JPG (remove)";
        Icon = "%SystemRoot%\System32\shell32.dll,-240";
        Command = "$hostCommand -Format Jpg -RemoveOriginal `"%1`"";
    },
    @{
        Id = "20_ToWebp";
        Label = "Convert to WebP";
        Icon = "%SystemRoot%\System32\imageres.dll,-71";
        SeparatorBefore = $true;
        Command = "$hostCommand -Format Webp `"%1`"";
    },
    @{
        Id = "21_ToWebpNew";
        Label = "Convert to WebP (new folder)";
        Icon = "%SystemRoot%\System32\imageres.dll,-71";
        Command = "$hostCommand -Format Webp -OutputMode New `"%1`"";
    },
    @{
        Id = "22_ToWebpRemove";
        Label = "Convert to WebP (remove)";
        Icon = "%SystemRoot%\System32\shell32.dll,-240";
        Command = "$hostCommand -Format Webp -RemoveOriginal `"%1`"";
    }
)

# Remove old flat menu entries from previous versions.
$legacyFlatVerbs = @("ConvertToJpg", "ConvertToJpgRemove", "ConvertToWebp", "ConvertToWebpRemove")
foreach ($ext in @(".png", ".jpg", ".jpeg", ".webp", ".avif")) {
    $shellRoot = "HKCU:\Software\Classes\SystemFileAssociations\$ext\shell"
    foreach ($legacyVerb in $legacyFlatVerbs) {
        $legacyPath = Join-Path -Path $shellRoot -ChildPath $legacyVerb
        if (Test-Path -LiteralPath $legacyPath) {
            Remove-Item -LiteralPath $legacyPath -Recurse -Force
        }
    }
}

Install-SubmenuForExtension -Extension ".png" -MenuKey "PngConvert" -MenuLabel "PNG Convert" -MenuIcon "%SystemRoot%\System32\imageres.dll,-70" -Entries $pngEntries
Install-SubmenuForExtension -Extension ".jpg" -MenuKey "JpegConvert" -MenuLabel "JPEG Convert" -MenuIcon "%SystemRoot%\System32\imageres.dll,-70" -Entries $jpegEntries
Install-SubmenuForExtension -Extension ".jpeg" -MenuKey "JpegConvert" -MenuLabel "JPEG Convert" -MenuIcon "%SystemRoot%\System32\imageres.dll,-70" -Entries $jpegEntries
Install-SubmenuForExtension -Extension ".webp" -MenuKey "WebpConvert" -MenuLabel "WEBP Convert" -MenuIcon "%SystemRoot%\System32\imageres.dll,-70" -Entries $webpEntries
Install-SubmenuForExtension -Extension ".avif" -MenuKey "AvifConvert" -MenuLabel "AVIF Convert" -MenuIcon "%SystemRoot%\System32\imageres.dll,-70" -Entries $avifEntries

# Cleanup legacy command store entries (from older installer versions).
$legacyCommandStoreVerbs = @(
    "PngConvert.ToJpg",
    "PngConvert.ToJpgNew",
    "PngConvert.ToJpgRemove",
    "PngConvert.ToWebp",
    "PngConvert.ToWebpNew",
    "PngConvert.ToAvif",
    "PngConvert.ToAvifNew",
    "PngConvert.ToAvifRemove",
    "PngConvert.ToWebpRemove"
)
foreach ($legacyVerb in $legacyCommandStoreVerbs) {
    $legacyCommandStorePath = Join-Path -Path $commandStoreRoot -ChildPath $legacyVerb
    if (Test-Path -LiteralPath $legacyCommandStorePath) {
        Remove-Item -LiteralPath $legacyCommandStorePath -Recurse -Force
    }
}

Write-Host "Context menu installed for PNG/JPEG/WEBP/AVIF files."
Write-Host "Launcher mode: $LauncherMode"
Write-Host "Menu: PNG Convert (submenu)"
Write-Host " - Convert to JPG"
Write-Host " - Convert to JPG (new folder)"
Write-Host " - Convert to JPG (remove)"
Write-Host " - Convert to WebP"
Write-Host " - Convert to WebP (new folder)"
Write-Host " - Convert to WebP (remove)"
Write-Host " - Convert to AVIF"
Write-Host " - Convert to AVIF (new folder)"
Write-Host " - Convert to AVIF (remove)"
Write-Host "Menu: JPEG Convert (submenu for .jpg/.jpeg)"
Write-Host " - Convert to WebP"
Write-Host " - Convert to WebP (new folder)"
Write-Host " - Convert to WebP (remove)"
Write-Host " - Convert to AVIF"
Write-Host " - Convert to AVIF (new folder)"
Write-Host " - Convert to AVIF (remove)"
Write-Host "Menu: WEBP Convert (submenu for .webp)"
Write-Host " - Convert to JPG / AVIF (+ new folder / remove)"
Write-Host "Menu: AVIF Convert (submenu for .avif)"
Write-Host " - Convert to JPG / WebP (+ new folder / remove)"
