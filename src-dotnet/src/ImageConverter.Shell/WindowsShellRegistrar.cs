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

    private static string ToClassesRelative(string fullClassesPath)
    {
        const string prefix = @"Software\Classes\";
        return fullClassesPath.StartsWith(prefix, StringComparison.OrdinalIgnoreCase)
            ? fullClassesPath[prefix.Length..]
            : fullClassesPath;
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

        menuKey.SetValue("MUIVerb", menu.MenuLabel, RegistryValueKind.String);
        menuKey.SetValue("Icon", menu.MenuIcon, RegistryValueKind.String);
        menuKey.SetValue("MultiSelectModel", "Player", RegistryValueKind.String);
        menuKey.SetValue("CommandFlags", 32, RegistryValueKind.DWord);

        // The flyout's children live in a *separate* cascade-holder key under the
        // ImageConverter.Menu namespace; ExtendedSubCommandsKey points the verb at it.
        // (A verb pointing ExtendedSubCommandsKey at its own \shell does not nest past
        // one level.) Each holder's children can again point at deeper holders, which is
        // what makes format -> preset -> behavior render.
        var holderId = menu.MenuKey;
        menuKey.SetValue("ExtendedSubCommandsKey", ToClassesRelative(HolderPath(holderId)), RegistryValueKind.String);
        BuildHolder(currentUser, holderId, menu.Entries);
    }

    private static string HolderPath(string holderId) =>
        $@"{ShellMenuCatalog.ContextMenuNamespacePath}\{holderId}";

    private static void BuildHolder(RegistryKey currentUser, string holderId, IReadOnlyList<ShellMenuEntryDefinition> entries)
    {
        var shellPath = $@"{HolderPath(holderId)}\shell";
        using (var shellKey = currentUser.CreateSubKey(shellPath, writable: true))
        {
            _ = shellKey ?? throw new InvalidOperationException($"Failed to create holder shell key: {shellPath}");
        }

        foreach (var entry in entries)
        {
            WriteNode(currentUser, holderId, shellPath, entry);
        }
    }

    private static void WriteNode(RegistryKey currentUser, string holderId, string parentShellPath, ShellMenuEntryDefinition entry)
    {
        var verbPath = $@"{parentShellPath}\{entry.Id}";
        using var verbKey = currentUser.CreateSubKey(verbPath, writable: true)
            ?? throw new InvalidOperationException($"Failed to create registry key for entry: {entry.Id}");

        verbKey.SetValue(string.Empty, entry.Label, RegistryValueKind.String);
        verbKey.SetValue("MUIVerb", entry.Label, RegistryValueKind.String);
        verbKey.SetValue("Icon", entry.Icon, RegistryValueKind.String);
        verbKey.SetValue("MultiSelectModel", "Player", RegistryValueKind.String);

        if (entry.SeparatorBefore)
        {
            verbKey.SetValue("CommandFlags", 32, RegistryValueKind.DWord);
        }

        if (entry.Children is { Count: > 0 } children)
        {
            var childHolderId = $"{holderId}__{entry.Id}";
            verbKey.SetValue("ExtendedSubCommandsKey", ToClassesRelative(HolderPath(childHolderId)), RegistryValueKind.String);
            BuildHolder(currentUser, childHolderId, children);
            return;
        }

        var command = entry.Command
            ?? throw new InvalidOperationException($"Leaf entry has no command: {entry.Id}");
        using var commandKey = currentUser.CreateSubKey($@"{verbPath}\command", writable: true)
            ?? throw new InvalidOperationException($"Failed to create command key for entry: {entry.Id}");
        commandKey.SetValue(string.Empty, command, RegistryValueKind.String);
    }
}
