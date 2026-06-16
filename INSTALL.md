# Install Location & Setup

`ImageConverter.exe` is a single self-contained file. Installation is per-user
(`HKCU`), needs no admin rights, and no separate installer.

## Where it is installed

The exe lives in a stable per-user programs folder, and the Explorer context-menu
entries in the registry point at that exact path:

| | Path |
|---|---|
| **Install folder** | `%LOCALAPPDATA%\Programs\Image Converter\` |
| **Executable** | `%LOCALAPPDATA%\Programs\Image Converter\ImageConverter.exe` |
| **Registry (menu)** | `HKCU\Software\Classes\SystemFileAssociations\<.png\|.jpg\|.jpeg\|.webp\|.avif>\shell\*Convert` |

On this machine that resolves to
`C:\Users\szmigieldesign\AppData\Local\Programs\Image Converter\ImageConverter.exe`.

> The registry commands store the **absolute path** of the exe at registration time.
> Keep the exe in the install folder — if you move or delete it, the menu entries
> break until you re-register from the new location.

## Install on a new computer

You only need the single `ImageConverter.exe`.

1. Copy `ImageConverter.exe` to the target machine.
2. Put it in a **permanent** folder, e.g. `%LOCALAPPDATA%\Programs\Image Converter\`
   (not Downloads/Desktop "for now" — the menu remembers this path).
3. **Double-click the exe.** A confirmation dialog appears and the right-click menu is
   registered. Done.

The context menu offers a three-level path: **format → quality preset → behavior**
(`Web (fast)` = q75, `Web (quality)` = q88, `Storage (premium)` = q95).

## Update to a new version

1. Overwrite the old `ImageConverter.exe` in the install folder with the new one.
2. **Double-click it.** The menu is rebuilt; old/legacy entries are cleaned first.

## Uninstall

Run once, then delete the folder:

```powershell
& "$env:LOCALAPPDATA\Programs\Image Converter\ImageConverter.exe" unregister-shell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Programs\Image Converter"
```

## Notes

- If the new menu doesn't show immediately, restart `explorer.exe` (or sign out/in) —
  Explorer caches context menus.
- First launch is slightly slower (native libraries self-extract to `%TEMP%` once).
- A `Setup.exe` (Inno Setup) installer is still available and does the same thing:
  copies the exe to the install folder and triggers self-registration. It is optional.
