# AGENTS.md

## Repo Map

- `src-dotnet/`: active .NET 8 implementation
- `legacy/`: preserved legacy PowerShell/VBS installer and runtime snapshot
- `build/Build-Installer.ps1`: restore, build, test, publish, installer build
- `installer/installer.iss`: thin Inno Setup installer

## Default Workflow

Build:

```powershell
dotnet restore .\src-dotnet\ImageConverter.sln --configfile .\src-dotnet\NuGet.Config
dotnet build .\src-dotnet\ImageConverter.sln -c Release
dotnet test .\src-dotnet\tests\ImageConverter.Tests\ImageConverter.Tests.csproj -c Release
```

Publish and package:

```powershell
.\build\Build-Installer.ps1
```

## Mutation Boundaries

- Treat `src-dotnet/` as the active codebase.
- Do not remove `legacy/` or the original top-level `src/` without explicitly finishing the migration cleanup.
- Keep shell registration under `HKCU` only in this first-pass architecture.
- Do not reintroduce PowerShell or VBS into the new runtime path.

## Notes

- `Magick.NET-Q8-AnyCPU` is pinned centrally in `Directory.Packages.props`.
- The test suite covers the core non-UI behavior; Explorer shell behavior still needs manual Windows smoke testing.
