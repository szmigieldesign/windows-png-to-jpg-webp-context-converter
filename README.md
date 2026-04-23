# Image Converter

Windows Explorer context menu and CLI utility for converting PNG, JPG/JPEG, WEBP, and AVIF files with a .NET 8 runtime.

## Status

- New runtime: `.NET 8`, `Magick.NET`, single-process batch conversion.
- Shell integration: classic `HKCU` verbs, no admin required.
- Packaging: self-contained single-file publish plus Inno Setup installer.
- Legacy path: retained under `legacy/` and mirrored in the original `src/` folder during the migration window.

Current repository version: **0.3.3**

## Repository Layout

- [src-dotnet/ImageConverter.sln](/C:/szmigieldesign/Works/Apps/image-converter/src-dotnet/ImageConverter.sln)
  - `src/ImageConverter.Core`: formats, requests/results, path logic, safety rules, batch orchestration, Magick.NET transcoder
  - `src/ImageConverter.Cli`: primary executable, argument parsing, shell batching, logging, notifications
  - `src/ImageConverter.Shell`: shell menu catalog and registry installer/uninstaller
  - `tests/ImageConverter.Tests`: unit tests for pathing, safety rules, batch behavior, shell intent generation
- [build/Build-Installer.ps1](/C:/szmigieldesign/Works/Apps/image-converter/build/Build-Installer.ps1): restore, build, test, publish, then package with Inno Setup
- [installer/installer.iss](/C:/szmigieldesign/Works/Apps/image-converter/installer/installer.iss): thin installer definition
- [legacy/](/C:/szmigieldesign/Works/Apps/image-converter/legacy): legacy PowerShell/VBS implementation snapshot

## Supported Behavior

Source formats:

- PNG
- JPG / JPEG
- WEBP
- AVIF

Target formats:

- JPG
- WEBP
- AVIF
- PNG for CLI only

Policies:

- Output to same folder or a sibling target-format folder (`JPEG`, `WEBP`, `AVIF`, `PNG`)
- Existing target handling: `skip`, `suffix`, `overwrite`
- Remove original only after a verified non-empty output file exists
- Block lossy-to-lossless conversion such as `jpg -> png`
- Process multiple files in one run
- Emit one final shell notification per batch

## Build Prerequisites

- `.NET 8 SDK`
- `Inno Setup 6` for installer creation

Optional:

- Existing legacy installs should be removed before adopting the new installer if you want a clean transition from the old script-based path.

## Build And Test

Restore, build, and test the solution:

```powershell
dotnet restore .\src-dotnet\ImageConverter.sln --configfile .\src-dotnet\NuGet.Config
dotnet build .\src-dotnet\ImageConverter.sln -c Release
dotnet test .\src-dotnet\tests\ImageConverter.Tests\ImageConverter.Tests.csproj -c Release
```

Publish the runtime and build the installer:

```powershell
.\build\Build-Installer.ps1
```

That script:

1. Restores the solution with the repo-local NuGet config.
2. Builds all projects in `Release`.
3. Runs the unit tests.
4. Publishes `ImageConverter.exe` as a self-contained single-file `win-x64` app into `build/publish/win-x64`.
5. Packages the published output into `release/Setup.exe`.

## CLI Usage

From a local build:

```powershell
.\src-dotnet\src\ImageConverter.Cli\bin\Release\net8.0-windows\ImageConverter.exe convert --to jpg .\image.png
```

Examples:

```powershell
# Skip existing output
.\ImageConverter.exe convert --to jpg .\image.png

# Write to WEBP sibling folder
.\ImageConverter.exe convert --to webp --output new .\image.png

# Keep existing output by suffixing
.\ImageConverter.exe convert --to avif --if-exists suffix .\image.png

# Replace existing output
.\ImageConverter.exe convert --to jpg --if-exists overwrite .\image.png

# Remove original after success
.\ImageConverter.exe convert --to webp --remove-original .\image.png

# Convert several files in one process
.\ImageConverter.exe convert --to avif .\one.png .\two.jpg .\three.webp

# Register Explorer verbs for the current user
.\ImageConverter.exe register-shell --install-dir "$env:LOCALAPPDATA\Programs\Image Converter"

# Remove Explorer verbs for the current user
.\ImageConverter.exe unregister-shell
```

Exit codes:

- `0`: success, including all-skipped runs
- `1`: one or more file conversions failed
- `2`: invalid arguments or unsupported request
- `3`: shell registration or registry access failure

## Explorer Integration

The new installer registers classic `HKCU` shell verbs for:

- `.png`
- `.jpg`
- `.jpeg`
- `.webp`
- `.avif`

The menu surface remains format-specific and intentionally close to the old product:

- PNG: JPG / WEBP / AVIF, each with default, `new folder`, and `remove`
- JPG/JPEG: WEBP / AVIF, each with default, `new folder`, and `remove`
- WEBP: JPG / AVIF, each with default, `new folder`, and `remove`
- AVIF: JPG / WEBP, each with default, `new folder`, and `remove`

## Legacy Notes

- The old PowerShell/VBS implementation was preserved under [legacy/](/C:/szmigieldesign/Works/Apps/image-converter/legacy).
- The original top-level `src/` folder is still retained during the migration window for compatibility and auditability.
- The new runtime path does not depend on VBS launchers, PowerShell conversion scripts, or install-time downloads.

## Known Risks

- `Magick.NET-Q8-AnyCPU 14.10.4` currently restores with upstream NuGet advisory warnings. The package is pinned for reproducibility, but those advisories should be re-evaluated on the next dependency update cycle.
- Explorer multi-select batching is handled with a named-pipe owner/forwarder model. Unit tests cover menu intent; Explorer smoke testing should still be done on a real Windows shell session before public release.

## License

MIT. See [LICENSE](/C:/szmigieldesign/Works/Apps/image-converter/LICENSE).
