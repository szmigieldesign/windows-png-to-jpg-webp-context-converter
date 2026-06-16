using System.Globalization;
using ImageConverter.Core;

namespace ImageConverter.Shell;

public sealed record ShellMenuEntryDefinition(
    string Id,
    string Label,
    string Icon,
    string? Command,
    bool SeparatorBefore = false,
    IReadOnlyList<ShellMenuEntryDefinition>? Children = null);

public sealed record ShellMenuDefinition(
    string Extension,
    string MenuKey,
    string MenuLabel,
    string MenuIcon,
    IReadOnlyList<ShellMenuEntryDefinition> Entries);

public sealed class ShellRegistrationPlan
{
    public required IReadOnlyList<ShellMenuDefinition> Menus { get; init; }

    public required IReadOnlyList<string> CleanupKeyPaths { get; init; }
}

public static class ShellMenuCatalog
{
    private const string ParentMenuIcon = @"%SystemRoot%\System32\imageres.dll,-70";
    private const string JpegIcon = @"%SystemRoot%\System32\imageres.dll,-72";
    private const string ModernIcon = @"%SystemRoot%\System32\imageres.dll,-71";
    private const string RemoveIcon = @"%SystemRoot%\System32\shell32.dll,-240";
    private const string NewFolderIcon = @"%SystemRoot%\System32\shell32.dll,-4";

    private static readonly QualityPreset[] Presets =
    [
        new("10_Fast", "Web (fast)", ModernIcon, 75),
        new("20_Quality", "Web (quality)", ModernIcon, 88),
        new("30_Premium", "Storage (premium)", JpegIcon, 95)
    ];

    private static readonly BehaviorVariant[] Behaviors =
    [
        new("1_Same", "Same folder", ParentMenuIcon, OutputMode.SameFolder, RemoveOriginal: false),
        new("2_New", "New folder", NewFolderIcon, OutputMode.TargetSubfolder, RemoveOriginal: false),
        new("3_Remove", "Remove original", RemoveIcon, OutputMode.SameFolder, RemoveOriginal: true)
    ];

    private static readonly ShellMenuTemplate[] MenuTemplates =
    [
        new(".png", "PngConvert", "PNG Convert", BuildPngEntries),
        new(".jpg", "JpegConvert", "JPEG Convert", BuildJpegEntries),
        new(".jpeg", "JpegConvert", "JPEG Convert", BuildJpegEntries),
        new(".webp", "WebpConvert", "WEBP Convert", BuildWebpEntries),
        new(".avif", "AvifConvert", "AVIF Convert", BuildAvifEntries)
    ];

    public static ShellRegistrationPlan Build(string executablePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(executablePath);

        var menus = MenuTemplates
            .Select(template => BuildMenu(
                template.Extension,
                template.MenuKey,
                template.Label,
                template.EntryFactory(executablePath)))
            .ToArray();

        return new ShellRegistrationPlan
        {
            Menus = menus,
            CleanupKeyPaths = BuildCleanupKeyPaths()
        };
    }

    public static IReadOnlyList<string> BuildCleanupKeyPaths() =>
    [
        .. MenuTemplates.Select(template => $@"Software\Classes\SystemFileAssociations\{template.Extension}\shell\{template.MenuKey}"),
        .. BuildLegacyCleanupKeys()
    ];

    private static ShellMenuDefinition BuildMenu(
        string extension,
        string menuKey,
        string label,
        IReadOnlyList<ShellMenuEntryDefinition> entries) =>
        new(extension, menuKey, label, ParentMenuIcon, entries);

    private static IReadOnlyList<ShellMenuEntryDefinition> BuildPngEntries(string executablePath) =>
    [
        BuildFormatNode("10_ToJpg", "Convert to JPG", JpegIcon, executablePath, ImageFormat.Jpg),
        BuildFormatNode("20_ToWebp", "Convert to WebP", ModernIcon, executablePath, ImageFormat.Webp, separatorBefore: true),
        BuildFormatNode("30_ToAvif", "Convert to AVIF", ModernIcon, executablePath, ImageFormat.Avif, separatorBefore: true)
    ];

    private static IReadOnlyList<ShellMenuEntryDefinition> BuildJpegEntries(string executablePath) =>
    [
        BuildFormatNode("20_ToWebp", "Convert to WebP", ModernIcon, executablePath, ImageFormat.Webp),
        BuildFormatNode("30_ToAvif", "Convert to AVIF", ModernIcon, executablePath, ImageFormat.Avif, separatorBefore: true)
    ];

    private static IReadOnlyList<ShellMenuEntryDefinition> BuildWebpEntries(string executablePath) =>
    [
        BuildFormatNode("10_ToJpg", "Convert to JPG", JpegIcon, executablePath, ImageFormat.Jpg),
        BuildFormatNode("30_ToAvif", "Convert to AVIF", ModernIcon, executablePath, ImageFormat.Avif, separatorBefore: true)
    ];

    private static IReadOnlyList<ShellMenuEntryDefinition> BuildAvifEntries(string executablePath) =>
    [
        BuildFormatNode("10_ToJpg", "Convert to JPG", JpegIcon, executablePath, ImageFormat.Jpg),
        BuildFormatNode("20_ToWebp", "Convert to WebP", ModernIcon, executablePath, ImageFormat.Webp, separatorBefore: true)
    ];

    private static ShellMenuEntryDefinition BuildFormatNode(
        string id,
        string label,
        string icon,
        string executablePath,
        ImageFormat targetFormat,
        bool separatorBefore = false)
    {
        var presets = Presets
            .Select(preset => BuildPresetNode(preset, executablePath, targetFormat))
            .ToArray();

        return new ShellMenuEntryDefinition(id, label, icon, Command: null, separatorBefore, presets);
    }

    private static ShellMenuEntryDefinition BuildPresetNode(
        QualityPreset preset,
        string executablePath,
        ImageFormat targetFormat)
    {
        var behaviors = Behaviors
            .Select(behavior => BuildBehaviorLeaf(preset, behavior, executablePath, targetFormat))
            .ToArray();

        return new ShellMenuEntryDefinition(preset.Id, preset.Label, preset.Icon, Command: null, SeparatorBefore: false, behaviors);
    }

    private static ShellMenuEntryDefinition BuildBehaviorLeaf(
        QualityPreset preset,
        BehaviorVariant behavior,
        string executablePath,
        ImageFormat targetFormat)
    {
        var command = BuildCommand(executablePath, targetFormat, behavior.OutputMode, behavior.RemoveOriginal, preset.Quality);
        return new ShellMenuEntryDefinition(behavior.Id, behavior.Label, behavior.Icon, command);
    }

    private static string BuildCommand(
        string executablePath,
        ImageFormat targetFormat,
        OutputMode outputMode,
        bool removeOriginal,
        int quality)
    {
        var parts = new List<string>
        {
            Quote(executablePath),
            "convert",
            "--from-shell",
            "--to",
            ImageFormatInfo.ToCliToken(targetFormat),
            "--if-exists",
            "skip",
            "--quality",
            quality.ToString(CultureInfo.InvariantCulture)
        };

        if (outputMode == OutputMode.TargetSubfolder)
        {
            parts.Add("--output");
            parts.Add("new");
        }

        if (removeOriginal)
        {
            parts.Add("--remove-original");
        }

        parts.Add("\"%1\"");
        return string.Join(' ', parts);
    }

    private static IReadOnlyList<string> BuildLegacyCleanupKeys() =>
    [
        @"Software\Classes\SystemFileAssociations\.png\shell\ConvertToJpg",
        @"Software\Classes\SystemFileAssociations\.png\shell\ConvertToJpgRemove",
        @"Software\Classes\SystemFileAssociations\.png\shell\ConvertToWebp",
        @"Software\Classes\SystemFileAssociations\.png\shell\ConvertToWebpRemove",
        @"Software\Classes\SystemFileAssociations\.jpg\shell\ConvertToJpg",
        @"Software\Classes\SystemFileAssociations\.jpg\shell\ConvertToJpgRemove",
        @"Software\Classes\SystemFileAssociations\.jpg\shell\ConvertToWebp",
        @"Software\Classes\SystemFileAssociations\.jpg\shell\ConvertToWebpRemove",
        @"Software\Classes\SystemFileAssociations\.jpeg\shell\ConvertToJpg",
        @"Software\Classes\SystemFileAssociations\.jpeg\shell\ConvertToJpgRemove",
        @"Software\Classes\SystemFileAssociations\.jpeg\shell\ConvertToWebp",
        @"Software\Classes\SystemFileAssociations\.jpeg\shell\ConvertToWebpRemove",
        @"Software\Classes\SystemFileAssociations\.webp\shell\ConvertToJpg",
        @"Software\Classes\SystemFileAssociations\.webp\shell\ConvertToJpgRemove",
        @"Software\Classes\SystemFileAssociations\.webp\shell\ConvertToWebp",
        @"Software\Classes\SystemFileAssociations\.webp\shell\ConvertToWebpRemove",
        @"Software\Classes\SystemFileAssociations\.avif\shell\ConvertToJpg",
        @"Software\Classes\SystemFileAssociations\.avif\shell\ConvertToJpgRemove",
        @"Software\Classes\SystemFileAssociations\.avif\shell\ConvertToWebp",
        @"Software\Classes\SystemFileAssociations\.avif\shell\ConvertToWebpRemove",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\PngConvert.ToJpg",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\PngConvert.ToJpgNew",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\PngConvert.ToJpgRemove",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\PngConvert.ToWebp",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\PngConvert.ToWebpNew",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\PngConvert.ToWebpRemove",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\PngConvert.ToAvif",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\PngConvert.ToAvifNew",
        @"Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\PngConvert.ToAvifRemove"
    ];

    private static string Quote(string value) => $"\"{value}\"";

    private sealed record ShellMenuTemplate(
        string Extension,
        string MenuKey,
        string Label,
        Func<string, IReadOnlyList<ShellMenuEntryDefinition>> EntryFactory);

    private sealed record QualityPreset(
        string Id,
        string Label,
        string Icon,
        int Quality);

    private sealed record BehaviorVariant(
        string Id,
        string Label,
        string Icon,
        OutputMode OutputMode,
        bool RemoveOriginal);
}
