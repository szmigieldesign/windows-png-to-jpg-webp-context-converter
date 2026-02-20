# PNG Converter Context Menu Tool (Windows 11)

Version: **0.1.1**

Quick PNG conversion from right-click context menu with four actions:

- `Convert to JPG`
- `Convert to JPG (remove)` (deletes original PNG after successful conversion)
- `Convert to WebP`
- `Convert to WebP (remove)` (deletes original PNG after successful conversion)

JPG/WebP quality is set to **80**.

## Files

- `ConvertPngToJpg.ps1` - converter script (JPG via System.Drawing, WebP via ImageMagick)
- `Run-Converter.vbs` - hidden launcher (no console popups) that prefers `pwsh` (PowerShell 7+) and falls back to `powershell` (Windows PowerShell 5)
- `install-context-menu.ps1` - registers context menu entries for `.png`
- `uninstall-context-menu.ps1` - removes registered entries

## Install

Run PowerShell in this folder:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-context-menu.ps1
```

This installs entries under current user (`HKCU`), so admin rights are not required.

## WebP Requirement

WebP conversion uses `magick.exe` (ImageMagick). Install it and ensure it's in `PATH`, for example:

```powershell
winget install ImageMagick.ImageMagick
```

## Use

1. Select one or more PNG files in File Explorer (or tools that expose shell context menu).
2. Right-click.
3. Choose:
   - `Convert to JPG`
   - or `Convert to JPG (remove)`
   - or `Convert to WebP`
   - or `Convert to WebP (remove)`

Output files are saved next to originals as `.jpg` or `.webp`.
WebP export strips metadata.
WebP export defaults are tuned for web use: `sRGB`, `8-bit`, `webp:method=6`, `webp:use-sharp-yuv=true`, `webp:alpha-quality=90`.
You get a single completion popup per burst of conversions (aggregated across parallel invocations to avoid popup spam).
Run log is written to `%TEMP%\png-converter-context.log`.

## Release Notes

### 0.1.1

- Added WebP conversion actions in context menu.
- WebP export now strips metadata by default.
- WebP export defaults tuned for web: `sRGB`, `8-bit`, `webp:method=6`, `webp:use-sharp-yuv=true`, `webp:alpha-quality=90`.
- Improved completion notifications to avoid popup spam for multi-file runs.

## Uninstall

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\uninstall-context-menu.ps1
```
