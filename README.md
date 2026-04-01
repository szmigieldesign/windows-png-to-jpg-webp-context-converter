# PNG/JPEG/WEBP/AVIF Converter Context Menu Tool (Windows 11)

Version: **0.3.3**

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

- `src/` - runtime scripts and source-side installer wrappers
- `build/Build-Installer.ps1` - reproducible build script for `Setup.exe`
- `installer/installer.iss` - Inno Setup definition for the installer
- `release/Setup.exe` - compiled end-user installer
- `README.md`, `LICENSE`, `VERSION` - repository metadata

Key scripts inside `src/`:

- `ConvertPngToJpg.ps1` - converter script
- `Run-Converter.vbs` - hidden launcher
- `Run-Converter.ps1` - fallback launcher for environments where `wscript.exe` is blocked
- `Install-ImageConverter.ps1` - installer that copies the app locally, bootstraps ImageMagick, and registers the context menu
- `Uninstall-ImageConverter.ps1` - removes the installed files and context menu entries
- `install-context-menu.ps1` - registers context menu entries for `.png`, `.jpg`, `.jpeg`, `.webp`, `.avif`
- `uninstall-context-menu.ps1` - removes registered entries
- `Setup.cmd` - double-click installer wrapper
- `Uninstall.cmd` - double-click uninstall wrapper

## Install

For the public release package, run `release\Setup.exe` and let it handle the rest:

1. Copies the scripts into `%LOCALAPPDATA%\Programs\PNG-JPG-WebP-AVIF-Converter`
2. Checks for `pwsh.exe`
3. Downloads a portable PowerShell 7 runtime into the app folder if `pwsh` is missing
4. Checks for `magick.exe`
5. Installs ImageMagick automatically if it is missing
6. Registers the context menu entries for the current user

If you prefer to install from source, double-click `src\Setup.cmd` or run:

```powershell
.\src\Setup.cmd
```

This installs entries under current user (`HKCU`), so admin rights are not required.

If your environment blocks `wscript.exe`, install using direct PowerShell launcher mode:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\src\install-context-menu.ps1 -LauncherMode PowerShell
```

## WebP Requirement

WebP conversion uses `magick.exe` (ImageMagick). Install it and ensure it's in `PATH`, for example:

```powershell
winget install ImageMagick.ImageMagick
```

The installer will try to do this automatically.

If `pwsh.exe` is missing, the installer downloads a portable PowerShell 7 runtime into the app folder and the converter uses it on the next run.

To rebuild the installer, run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\build\Build-Installer.ps1
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
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\ConvertPngToJpg.ps1 image.png

# Add suffix when output exists
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\ConvertPngToJpg.ps1 -IfExists Suffix image.png

# Force overwrite existing output
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\ConvertPngToJpg.ps1 -Overwrite image.png

# WebP conversion
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\ConvertPngToJpg.ps1 -Format Webp image.png

# AVIF conversion
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\ConvertPngToJpg.ps1 -Format Avif image.png

# New-folder output mode
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\ConvertPngToJpg.ps1 -Format Webp -OutputMode New image.png

# JPEG to WebP
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\ConvertPngToJpg.ps1 -Format Webp photo.jpg

# WEBP to AVIF
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\ConvertPngToJpg.ps1 -Format Avif image.webp

# JPG conversion using ImageMagick (when installed)
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\ConvertPngToJpg.ps1 -UseMagickForJpg image.png
```

## Release Notes

### 0.3.3

- Reorganized the repository into `src/`, `build/`, `installer/`, and `release/`.
- Renamed the typo'd release folder to `release/`.
- Kept the public build output limited to `release/Setup.exe`.

### 0.3.2

- Added automatic portable PowerShell 7 bootstrap when `pwsh.exe` is missing.
- Updated runtime launchers to prefer bundled PowerShell 7 when available.
- Kept the ImageMagick bootstrap flow in the installer.

### 0.3.1

- Added a proper `Setup.exe` installer build via Inno Setup.
- Added a reproducible `Build-Installer.ps1` build path.
- Kept the public release package under `release/` for the generated installer.

### 0.3.0

- Added a simple end-user installer entry point via `Setup.cmd`.
- Added automatic dependency bootstrap for ImageMagick.
- Added uninstall entry point via `Uninstall.cmd`.
- Added a distributable `release/` package for public release builds.

### 0.2.1

- Fixed VBS launcher host selection to avoid accidental double execution when a conversion run fails.
- Added `-auto-orient` before metadata stripping in ImageMagick conversion paths (JPG/WebP/AVIF/PNG via Magick).
- Improved `IfExists=Skip` behavior to recover from broken zero-byte outputs instead of skipping forever.
- Added stale notification-state recovery with a single "possible interruption" completion popup.
- Updated PowerShell launcher path to prefer `pwsh.exe` when available, with host fallback.

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

For a source install, double-click `src\Uninstall.cmd` or run:

```powershell
.\src\Uninstall.cmd
```

If you want to remove the context menu directly, run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\src\uninstall-context-menu.ps1
```

For the public release package, use the standard Windows uninstall entry created by `release\Setup.exe`.

## License

MIT. See `LICENSE`.
