# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Windows utility that converts PNG/JPG/JPEG/WEBP/AVIF images, exposed both as a CLI (`ImageConverter.exe convert ...`) and as classic Explorer right-click context-menu verbs. The shipped binary is a self-contained single-file `win-x64` build of the `ImageConverter.Cli` project.

## Active vs. legacy code

The repo is mid-migration. Only `src-dotnet/` is live. `legacy/` (and the historical top-level `src/`, if present) hold the old PowerShell/VBS implementation kept for auditability — **do not edit `legacy/` when working on current behavior.**

## Common commands

All commands assume the repo root. The repo-local `NuGet.Config` must be passed on restore — package restore relies on it.

```powershell
# Restore (required before build; uses repo-local NuGet config)
dotnet restore .\src-dotnet\ImageConverter.sln --configfile .\src-dotnet\NuGet.Config

# Build
dotnet build .\src-dotnet\ImageConverter.sln -c Release

# Test (whole suite)
dotnet test .\src-dotnet\tests\ImageConverter.Tests\ImageConverter.Tests.csproj -c Release

# Run a single test (xUnit) by fully-qualified name or substring
dotnet test .\src-dotnet\tests\ImageConverter.Tests\ImageConverter.Tests.csproj -c Release --filter "FullyQualifiedName~SafetyRule"

# Full release: restore + build + test + self-contained single-file publish + Inno Setup packaging -> release\Setup.exe
.\build\Build-Installer.ps1
```

`Build-Installer.ps1` requires the **.NET 8 SDK** and **Inno Setup 6** (`ISCC.exe`; it probes PATH, `%LOCALAPPDATA%\Programs`, and Program Files). It redirects `DOTNET_CLI_HOME`/`APPDATA` into `src-dotnet/` for a hermetic build, and stamps version from the root `VERSION` file.

## Architecture

Three projects under `src-dotnet/src/` plus tests. Central package versions live in `Directory.Packages.props`; shared build settings (nullable, implicit usings, C# 12) in `src-dotnet/Directory.Build.props`.

- **`ImageConverter.Core`** — the conversion domain, no I/O entrypoint. Owns the enums and records in `Contracts.cs` (`ImageFormat`, `OutputMode`, `FileExistsPolicy`, `BatchConversionRequest`/`Result`), path resolution (`Pathing.cs`), safety rules, batch orchestration (`BatchConversionService.cs`), and the `IImageTranscoder` abstraction with its `Magick.NET` implementation (`Transcoding.cs`). Conversion is **sequential by design** (simplicity, bounded memory).
- **`ImageConverter.Shell`** — Explorer integration only: menu definitions (`ShellMenuCatalog.cs`) and `HKCU\Software\Classes\SystemFileAssociations\...` registry writes (`WindowsShellRegistrar.cs`). No admin required; uninstall also cleans up legacy keys. The menu is a three-level cascade — **format → quality preset → behavior** — built as a recursive `ShellMenuEntryDefinition` tree (an entry is a submenu node when it has `Children`, otherwise a leaf with a `Command`); `WindowsShellRegistrar.WriteEntry` walks it recursively, using the `SubCommands=""` + nested `shell` subkey pattern for nodes. Each leaf emits `--quality` from its preset (`Web (fast)`=75, `Web (quality)`=88, `Storage (premium)`=95).
- **`ImageConverter.Cli`** — the process entrypoint (`Program.cs` / `ProgramEntry.cs`). Parses commands (`Hosting/CommandLineParser.cs`), runs structured `key=value` logging, attaches a Windows console for terminal launches, and owns shell-batch coordination and the final notification.

### Two behaviors worth knowing before changing them

1. **Safety + remove-original gating** (in Core). Lossy→lossless conversions (e.g. `jpg -> png`) are blocked before any write. `--remove-original` deletes the source **only after** the output file is verified to exist and be non-empty. Tests in `SafetyRuleTests.cs` and `BatchConversionServiceTests.cs` lock this in — keep them green.

2. **Shell batch coordination** (`Cli/Infrastructure/ShellBatchCoordinator.cs`). Explorer spawns one process per selected file on multi-select. To produce a single batch + single notification, processes with identical conversion parameters elect one owner via a named `Mutex`, and followers forward their paths to the owner over a named pipe. The pipe/mutex name is a hash of the conversion parameters (`BuildChannel`), so only matching invocations coalesce. There's a 900ms quiet-period collection window. This path is hard to unit-test end-to-end; smoke-test real Explorer multi-select after touching it.

## CLI contract

Commands: `convert`, `register-shell [--install-dir <path>]`, `unregister-shell`, `help`. **No arguments** (double-click from Explorer) maps to `SelfInstallCommand` → self-registers the menu from `Environment.ProcessPath`'s directory and shows a confirmation dialog; this is the hands-free install/update path. Only `-h`/`--help`/`help` print usage.

`convert` flags: `--to <jpg|webp|avif|png>` (required), `--output <same|new>`, `--if-exists <skip|suffix|overwrite>` (default `skip`), `--remove-original`, `--quality <0-100>` (default 80), `--from-shell` (enables batch coordination). Any non-flag token is an input path.

Exit codes: `0` success (including all-skipped), `1` one or more conversions failed, `2` invalid arguments, `3` shell registration/registry failure. `png` is a valid target only via the CLI, not the Explorer menu.

## Known constraints

- `Magick.NET-Q8-AnyCPU` is pinned and may restore with upstream advisory warnings; revisit on dependency bumps.
- Single-file publish uses `EnableCompressionInSingleFile=true`, `PublishTrimmed=false`, self-contained `win-x64`, plus `IncludeNativeLibrariesForSelfExtract=true` (in the CLI csproj) so `Magick.Native` and the WinForms native libs are bundled inside the exe — the published output is a true single portable `ImageConverter.exe` (no sibling DLLs). First launch self-extracts native libs to a temp dir.
