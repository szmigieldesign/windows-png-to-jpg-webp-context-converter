# PNG/JPEG/WEBP/AVIF Converter Context Menu Tool (Windows 11)

Version: **0.2**

Quick right-click transcoding with submenu actions:

- PNG inputs (`.png`):
  - `Convert to JPG`
  - `Convert to JPG (new folder)`
  - `Convert to JPG (remove)`
  - `Convert to WebP`
  - `Convert to WebP (new folder)`
  - `Convert to WebP (remove)`
  - `Convert to AVIF`
  - `Convert to AVIF (new folder)`
  - `Convert to AVIF (remove)`
- JPEG inputs (`.jpg`, `.jpeg`):
  - `Convert to WebP`
  - `Convert to WebP (new folder)`
  - `Convert to WebP (remove)`
  - `Convert to AVIF`
  - `Convert to AVIF (new folder)`
  - `Convert to AVIF (remove)`
- WEBP inputs (`.webp`):
  - `Convert to JPG` / `Convert to AVIF` (+ `new folder` / `remove`)
- AVIF inputs (`.avif`):
  - `Convert to JPG` / `Convert to WebP` (+ `new folder` / `remove`)

JPG/WebP/AVIF quality is set to **80**.

## Files

- `ConvertPngToJpg.ps1` - converter script
- `Run-Converter.vbs` - hidden launcher
- `Run-Converter.ps1` - fallback launcher for environments where `wscript.exe` is blocked
- `install-context-menu.ps1` - registers context menu entries for `.png`, `.jpg`, `.jpeg`, `.webp`, `.avif`
- `uninstall-context-menu.ps1` - removes registered entries

## Install

Run PowerShell in this folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-context-menu.ps1
```

This installs entries under current user (`HKCU`), so admin rights are not required.

If your environment blocks `wscript.exe`, install using direct PowerShell launcher mode:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-context-menu.ps1 -LauncherMode PowerShell
```

## WebP Requirement

WebP conversion uses `magick.exe` (ImageMagick). Install it and ensure it's in `PATH`, for example:

```powershell
winget install ImageMagick.ImageMagick
```

## Conversion Behavior

- Existing output handling:
  - Default: `Skip` (if target `.jpg`/`.webp`/`.avif` already exists).
  - Alternative: `Suffix` (creates `name-1.ext`, `name-2.ext`, ...).
  - Explicit replace: `-Overwrite`.
- Output location:
  - Default: `Same` folder as input.
  - New mode: `-OutputMode New` writes to a sibling subfolder named `JPEG`, `WEBP`, `AVIF` (or `PNG` for CLI `-Format Png`).
- `-RemoveOriginal` safety guard:
  - Original source file is deleted only when output exists and has non-zero size.
- Transcoding safety rule:
  - Lossy -> lossless is blocked (e.g. JPG/WEBP/AVIF -> PNG).
- WebP conversion requires ImageMagick:
  - If missing, converter shows one clear popup with:
    - `winget install ImageMagick.ImageMagick`
- AVIF conversion requires ImageMagick:
  - If missing, converter shows one clear popup with:
    - `winget install ImageMagick.ImageMagick`
- WebP export defaults:
  - `-strip`, `sRGB`, `8-bit`, `webp:method=6`, `webp:use-sharp-yuv=true`, `webp:alpha-quality=90`.
- AVIF export defaults:
  - `-strip`, `sRGB`, `8-bit`, `heic:speed=6`.
- JPG engine:
  - Default: `System.Drawing` (GDI+).
  - Optional consistency mode: `-UseMagickForJpg` (if ImageMagick is installed).

## Use

1. Select one or more PNG/JPEG/WEBP/AVIF files in File Explorer (or tools that expose shell context menu).
2. Right-click.
3. Choose:
   - `PNG Convert` submenu for PNG files
   - `JPEG Convert` submenu for JPG/JPEG files
   - `WEBP Convert` submenu for WEBP files
   - `AVIF Convert` submenu for AVIF files

Output files are saved next to originals as `.jpg`, `.webp`, or `.avif`.
You get a single completion popup per burst of conversions (aggregated across parallel invocations to avoid popup spam).
Run log is written to `%TEMP%\png-converter-context.log`.

## CLI Examples

```powershell
# Default behavior (skip existing output)
powershell -NoProfile -ExecutionPolicy Bypass -File .\ConvertPngToJpg.ps1 image.png

# Add suffix when output exists
powershell -NoProfile -ExecutionPolicy Bypass -File .\ConvertPngToJpg.ps1 -IfExists Suffix image.png

# Force overwrite existing output
powershell -NoProfile -ExecutionPolicy Bypass -File .\ConvertPngToJpg.ps1 -Overwrite image.png

# WebP conversion
powershell -NoProfile -ExecutionPolicy Bypass -File .\ConvertPngToJpg.ps1 -Format Webp image.png

# AVIF conversion
powershell -NoProfile -ExecutionPolicy Bypass -File .\ConvertPngToJpg.ps1 -Format Avif image.png

# New-folder output mode
powershell -NoProfile -ExecutionPolicy Bypass -File .\ConvertPngToJpg.ps1 -Format Webp -OutputMode New image.png

# JPEG to WebP
powershell -NoProfile -ExecutionPolicy Bypass -File .\ConvertPngToJpg.ps1 -Format Webp photo.jpg

# WEBP to AVIF
powershell -NoProfile -ExecutionPolicy Bypass -File .\ConvertPngToJpg.ps1 -Format Avif image.webp

# JPG conversion using ImageMagick (when installed)
powershell -NoProfile -ExecutionPolicy Bypass -File .\ConvertPngToJpg.ps1 -UseMagickForJpg image.png
```

## Release Notes

### 0.2

- Added AVIF conversion support.
- Added cross-format transcoding between PNG/JPEG/WEBP/AVIF where sensible.
- Enforced safety rule: no lossy -> lossless conversions.
- Added new-folder mode actions in context menus.
- Added JPEG/WEBP/AVIF specific submenus and format group separators.

### 0.1.1

- Added WebP conversion actions in context menu.
- WebP export now strips metadata by default.
- WebP export defaults tuned for web: `sRGB`, `8-bit`, `webp:method=6`, `webp:use-sharp-yuv=true`, `webp:alpha-quality=90`.
- Improved completion notifications to avoid popup spam for multi-file runs.
- Added safe output handling (`Skip`/`Suffix`/`-Overwrite`), remove-original guard, submenu grouping with icons, and optional PowerShell launcher mode.

## Uninstall

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\uninstall-context-menu.ps1
```

## License

MIT. See `LICENSE`.
