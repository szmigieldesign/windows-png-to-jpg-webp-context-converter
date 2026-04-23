using ImageConverter.Core;

namespace ImageConverter.Shell;

public sealed record ShellMenuEntryDefinition(
    string Id,
    string Label,
    string Icon,
    string Command,
    bool SeparatorBefore = false);

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
        BuildEntry("10_ToJpg", "Convert to JPG", JpegIcon, executablePath, ImageFormat.Jpg),
        BuildEntry("11_ToJpgNew", "Convert to JPG (new folder)", JpegIcon, executablePath, ImageFormat.Jpg, OutputMode.TargetSubfolder),
        BuildEntry("12_ToJpgRemove", "Convert to JPG (remove)", RemoveIcon, executablePath, ImageFormat.Jpg, removeOriginal: true),
        BuildEntry("20_ToWebp", "Convert to WebP", ModernIcon, executablePath, ImageFormat.Webp, separatorBefore: true),
        BuildEntry("21_ToWebpNew", "Convert to WebP (new folder)", ModernIcon, executablePath, ImageFormat.Webp, OutputMode.TargetSubfolder),
        BuildEntry("22_ToWebpRemove", "Convert to WebP (remove)", RemoveIcon, executablePath, ImageFormat.Webp, removeOriginal: true),
        BuildEntry("30_ToAvif", "Convert to AVIF", ModernIcon, executablePath, ImageFormat.Avif, separatorBefore: true),
        BuildEntry("31_ToAvifNew", "Convert to AVIF (new folder)", ModernIcon, executablePath, ImageFormat.Avif, OutputMode.TargetSubfolder),
        BuildEntry("32_ToAvifRemove", "Convert to AVIF (remove)", RemoveIcon, executablePath, ImageFormat.Avif, removeOriginal: true)
    ];

    private static IReadOnlyList<ShellMenuEntryDefinition> BuildJpegEntries(string executablePath) =>
    [
        BuildEntry("20_ToWebp", "Convert to WebP", ModernIcon, executablePath, ImageFormat.Webp),
        BuildEntry("21_ToWebpNew", "Convert to WebP (new folder)", ModernIcon, executablePath, ImageFormat.Webp, OutputMode.TargetSubfolder),
        BuildEntry("22_ToWebpRemove", "Convert to WebP (remove)", RemoveIcon, executablePath, ImageFormat.Webp, removeOriginal: true),
        BuildEntry("30_ToAvif", "Convert to AVIF", ModernIcon, executablePath, ImageFormat.Avif, separatorBefore: true),
        BuildEntry("31_ToAvifNew", "Convert to AVIF (new folder)", ModernIcon, executablePath, ImageFormat.Avif, OutputMode.TargetSubfolder),
        BuildEntry("32_ToAvifRemove", "Convert to AVIF (remove)", RemoveIcon, executablePath, ImageFormat.Avif, removeOriginal: true)
    ];

    private static IReadOnlyList<ShellMenuEntryDefinition> BuildWebpEntries(string executablePath) =>
    [
        BuildEntry("10_ToJpg", "Convert to JPG", JpegIcon, executablePath, ImageFormat.Jpg),
        BuildEntry("11_ToJpgNew", "Convert to JPG (new folder)", JpegIcon, executablePath, ImageFormat.Jpg, OutputMode.TargetSubfolder),
        BuildEntry("12_ToJpgRemove", "Convert to JPG (remove)", RemoveIcon, executablePath, ImageFormat.Jpg, removeOriginal: true),
        BuildEntry("30_ToAvif", "Convert to AVIF", ModernIcon, executablePath, ImageFormat.Avif, separatorBefore: true),
        BuildEntry("31_ToAvifNew", "Convert to AVIF (new folder)", ModernIcon, executablePath, ImageFormat.Avif, OutputMode.TargetSubfolder),
        BuildEntry("32_ToAvifRemove", "Convert to AVIF (remove)", RemoveIcon, executablePath, ImageFormat.Avif, removeOriginal: true)
    ];

    private static IReadOnlyList<ShellMenuEntryDefinition> BuildAvifEntries(string executablePath) =>
    [
        BuildEntry("10_ToJpg", "Convert to JPG", JpegIcon, executablePath, ImageFormat.Jpg),
        BuildEntry("11_ToJpgNew", "Convert to JPG (new folder)", JpegIcon, executablePath, ImageFormat.Jpg, OutputMode.TargetSubfolder),
        BuildEntry("12_ToJpgRemove", "Convert to JPG (remove)", RemoveIcon, executablePath, ImageFormat.Jpg, removeOriginal: true),
        BuildEntry("20_ToWebp", "Convert to WebP", ModernIcon, executablePath, ImageFormat.Webp, separatorBefore: true),
        BuildEntry("21_ToWebpNew", "Convert to WebP (new folder)", ModernIcon, executablePath, ImageFormat.Webp, OutputMode.TargetSubfolder),
        BuildEntry("22_ToWebpRemove", "Convert to WebP (remove)", RemoveIcon, executablePath, ImageFormat.Webp, removeOriginal: true)
    ];

    private static ShellMenuEntryDefinition BuildEntry(
        string id,
        string label,
        string icon,
        string executablePath,
        ImageFormat targetFormat,
        OutputMode outputMode = OutputMode.SameFolder,
        bool removeOriginal = false,
        bool separatorBefore = false)
    {
        var command = BuildCommand(executablePath, targetFormat, outputMode, removeOriginal);
        return new ShellMenuEntryDefinition(id, label, icon, command, separatorBefore);
    }

    private static string BuildCommand(
        string executablePath,
        ImageFormat targetFormat,
        OutputMode outputMode,
        bool removeOriginal)
    {
        var parts = new List<string>
        {
            Quote(executablePath),
            "convert",
            "--from-shell",
            "--to",
            ImageFormatInfo.ToCliToken(targetFormat),
            "--if-exists",
            "skip"
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
}
