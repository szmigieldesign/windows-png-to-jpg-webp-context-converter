# Architecture

## Overview

The active implementation is a .NET 8 Windows utility split into small projects with one runtime executable:

- `ImageConverter.Core`
- `ImageConverter.Cli`
- `ImageConverter.Shell`
- `ImageConverter.Tests`

The shipped runtime is `ImageConverter.exe`, produced from `ImageConverter.Cli`.

## Project Responsibilities

### ImageConverter.Core

Owns the conversion domain and reusable behavior:

- `ImageFormat`, `OutputMode`, `FileExistsPolicy`, `FileConversionStatus`
- `BatchConversionRequest`, `FileConversionResult`, `BatchConversionResult`, `NotificationSummary`
- input file resolution and target path generation
- lossy/lossless safety rules
- batch orchestration
- `IImageTranscoder` abstraction
- `MagickImageTranscoder` implementation using `Magick.NET`

Design choice:

- Conversion runs sequentially in v1. That keeps the runtime simple, avoids memory spikes, and still removes the expensive per-file process spawning from the old script model.

### ImageConverter.Shell

Owns shell integration:

- shell menu definitions
- command generation for each verb
- `HKCU\Software\Classes\SystemFileAssociations\...` registry writes
- shell uninstall cleanup for both new keys and legacy keys

The CLI references `ImageConverter.Shell` via a normal `ProjectReference`.

### ImageConverter.Cli

Owns the process entrypoint:

- command-line parsing
- `convert`, `register-shell`, `unregister-shell`
- structured logging
- Windows console attachment for terminal launches
- named-pipe shell batching to collapse multiple Explorer launches into one processed batch
- final shell notification display

### ImageConverter.Tests

Owns the critical-path regression suite:

- output path policies
- `skip` / `suffix` / `overwrite`
- lossy-to-lossless blocking
- remove-original gating
- mixed batch summary behavior
- shell menu command intent generation

## Runtime Flow

### Convert

1. Parse the command line into a `BatchConversionRequest`.
2. Resolve supported files from the provided file and directory paths.
3. Apply safety rules before any write.
4. Resolve the destination path based on output mode and collision policy.
5. Transcode with `Magick.NET`.
6. Verify the output exists and is non-empty.
7. Remove the original only after output verification when requested.
8. Emit structured logs and a single shell summary when launched from Explorer.

### Shell Batch Mode

Explorer may invoke multiple processes for one multi-select action. To avoid one popup per process, `--from-shell` mode uses:

- a named mutex to elect one owner process
- a named pipe to forward file paths from follower processes to the owner
- a quiet-period collection window before the owner starts the batch

## Packaging

Packaging is intentionally thin:

1. `dotnet restore`
2. `dotnet build`
3. `dotnet test`
4. `dotnet publish` for `win-x64`, self-contained, single-file
5. Inno Setup packages the published output and runs `ImageConverter.exe register-shell --install-dir "{app}"`

No PowerShell runtime bootstrap, VBS launcher, or ImageMagick download occurs at user install time.

## Logging

CLI mode:

- deterministic `key=value` lines to stdout/stderr

Shell mode:

- same line format
- appended to `%LOCALAPPDATA%\ImageConverter\Logs\image-converter.log`
- one final message box summary for the batch

## Compatibility Notes

- The legacy implementation is kept under `legacy/`.
- The original top-level `src/` folder still exists during the transition window.
- The new runtime preserves the old product behavior where it matters, but with a far simpler dependency and installation model.
