using Microsoft.Win32;
using System.Runtime.Versioning;

namespace ImageConverter.Shell;

[SupportedOSPlatform("windows")]
public sealed class WindowsShellRegistrar
{
    public ShellRegistrationPlan Register(string executablePath)
    {
        var plan = ShellMenuCatalog.Build(executablePath);
        Unregister();

        using var currentUser = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Default);
        foreach (var menu in plan.Menus)
        {
            CreateMenu(currentUser, menu);
        }

        return plan;
    }

    public void Unregister()
    {
        using var currentUser = RegistryKey.OpenBaseKey(RegistryHive.CurrentUser, RegistryView.Default);

        foreach (var path in ShellMenuCatalog.BuildCleanupKeyPaths())
        {
            DeleteNestedSubKeyTree(currentUser, path);
        }
    }

    private static void DeleteNestedSubKeyTree(RegistryKey root, string path)
    {
        var lastSep = path.LastIndexOf('\\');
        if (lastSep < 0)
        {
            root.DeleteSubKeyTree(path, throwOnMissingSubKey: false);
            return;
        }
        using var parentKey = root.OpenSubKey(path[..lastSep], writable: true);
        parentKey?.DeleteSubKeyTree(path[(lastSep + 1)..], throwOnMissingSubKey: false);
    }

    private static void CreateMenu(RegistryKey currentUser, ShellMenuDefinition menu)
    {
        var menuPath = $@"Software\Classes\SystemFileAssociations\{menu.Extension}\shell\{menu.MenuKey}";
        DeleteNestedSubKeyTree(currentUser, menuPath);

        using var menuKey = currentUser.CreateSubKey(menuPath, writable: true)
            ?? throw new InvalidOperationException($"Failed to create registry key: {menuPath}");
        using var shellKey = currentUser.CreateSubKey($@"{menuPath}\shell", writable: true)
            ?? throw new InvalidOperationException($"Failed to create registry key: {menuPath}\\shell");

        menuKey.SetValue("MUIVerb", menu.MenuLabel, RegistryValueKind.String);
        menuKey.SetValue("Icon", menu.MenuIcon, RegistryValueKind.String);
        menuKey.SetValue("MultiSelectModel", "Player", RegistryValueKind.String);
        menuKey.SetValue("SubCommands", string.Empty, RegistryValueKind.String);
        menuKey.SetValue("CommandFlags", 32, RegistryValueKind.DWord);

        foreach (var entry in menu.Entries)
        {
            WriteEntry(currentUser, $@"{menuPath}\shell", entry);
        }
    }

    private static void WriteEntry(RegistryKey currentUser, string parentShellPath, ShellMenuEntryDefinition entry)
    {
        var entryPath = $@"{parentShellPath}\{entry.Id}";
        using var entryKey = currentUser.CreateSubKey(entryPath, writable: true)
            ?? throw new InvalidOperationException($"Failed to create registry key for entry: {entry.Id}");

        entryKey.SetValue(string.Empty, entry.Label, RegistryValueKind.String);
        entryKey.SetValue("MUIVerb", entry.Label, RegistryValueKind.String);
        entryKey.SetValue("Icon", entry.Icon, RegistryValueKind.String);
        entryKey.SetValue("MultiSelectModel", "Player", RegistryValueKind.String);

        if (entry.SeparatorBefore)
        {
            entryKey.SetValue("CommandFlags", 32, RegistryValueKind.DWord);
        }

        if (entry.Children is { Count: > 0 } children)
        {
            entryKey.SetValue("SubCommands", string.Empty, RegistryValueKind.String);
            using (var childShellKey = currentUser.CreateSubKey($@"{entryPath}\shell", writable: true))
            {
                _ = childShellKey ?? throw new InvalidOperationException($"Failed to create shell key for entry: {entry.Id}");
            }

            foreach (var child in children)
            {
                WriteEntry(currentUser, $@"{entryPath}\shell", child);
            }

            return;
        }

        var command = entry.Command
            ?? throw new InvalidOperationException($"Leaf entry has no command: {entry.Id}");
        using var commandKey = currentUser.CreateSubKey($@"{entryPath}\command", writable: true)
            ?? throw new InvalidOperationException($"Failed to create command key for entry: {entry.Id}");
        commandKey.SetValue(string.Empty, command, RegistryValueKind.String);
    }
}
