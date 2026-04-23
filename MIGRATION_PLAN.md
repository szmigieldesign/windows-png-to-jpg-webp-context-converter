# Migration Plan

## Summary

This repository has been migrated from a script-first Explorer tool into a .NET 8 solution centered on a single executable, `ImageConverter.exe`.

The migration keeps the old PowerShell/VBS implementation available for audit and rollback while moving the active runtime, shell registration, tests, and packaging flow into `src-dotnet/`.

## Current State

Completed:

- New `ImageConverter.Core`, `ImageConverter.Cli`, `ImageConverter.Shell`, and `ImageConverter.Tests` projects
- Managed conversion pipeline using `Magick.NET`
- CLI command surface for conversion and shell registration
- HKCU shell menu registration and unregistration
- Single-process batch orchestration with shell batching support
- Unit tests for path generation, overwrite behavior, safety rules, remove-original gating, and shell menu intent
- Thin installer definition that packages published binaries instead of downloading dependencies at install time
- Updated root docs for the new architecture and release flow

Retained during migration:

- `legacy/` snapshot of the script-based implementation
- original `src/` folder for compatibility while the rewrite settles

## Migration Phases

1. Preserve and isolate the legacy implementation.
2. Introduce the .NET 8 solution and core domain model.
3. Replace shell/runtime behavior with a single executable.
4. Add tests around the critical non-UI logic.
5. Switch packaging to published binaries plus a thin installer.
6. Update repo-facing docs and agent instructions.

## Risks And Follow-Up

- `Magick.NET-Q8-AnyCPU 14.10.4` currently emits NuGet advisory warnings. It is pinned for reproducibility, but the advisories remain open.
- Explorer shell batching logic is implemented, but should still be smoke-tested in a real Explorer session before a public release.
- The legacy top-level `src/` directory is still present in addition to `legacy/src/`; once the .NET path is fully adopted, that duplication can be removed in a follow-up cleanup.

## Migration Checklist

- [x] Preserve legacy implementation
- [x] Add .NET 8 solution and projects
- [x] Replace runtime with one primary executable
- [x] Remove VBS and PowerShell from the new runtime path
- [x] Remove install-time dependency downloads from the new installer path
- [x] Implement HKCU shell registration/unregistration
- [x] Add critical-path tests
- [x] Update build and packaging scripts
- [x] Update README and add agent guidance
- [x] Run final Explorer install/uninstall smoke tests against the generated `Setup.exe`
