using ImageConverter.Core;
using ImageConverter.Shell;

namespace ImageConverter.Tests;

public sealed class ShellMenuCatalogTests
{
    [Fact]
    public void ShellCatalogBuildsExpectedMenuMatrix()
    {
        var plan = ShellMenuCatalog.Build(@"C:\Apps\ImageConverter\ImageConverter.exe");

        Assert.Equal(5, plan.Menus.Count);

        // Top level = target formats; each format -> 3 presets -> 3 behaviors.
        Assert.Equal(3, plan.Menus.Single(menu => menu.Extension == ".png").Entries.Count);
        Assert.Equal(2, plan.Menus.Single(menu => menu.Extension == ".jpg").Entries.Count);
        Assert.Equal(2, plan.Menus.Single(menu => menu.Extension == ".webp").Entries.Count);

        // Leaf commands: (#formats) * 3 presets * 3 behaviors.
        Assert.Equal(27, CountLeaves(plan.Menus.Single(menu => menu.Extension == ".png").Entries));
        Assert.Equal(18, CountLeaves(plan.Menus.Single(menu => menu.Extension == ".jpg").Entries));
        Assert.Equal(18, CountLeaves(plan.Menus.Single(menu => menu.Extension == ".webp").Entries));
    }

    [Fact]
    public void EveryFormatNodeExposesThreeQualityPresets()
    {
        var plan = ShellMenuCatalog.Build(@"C:\Apps\ImageConverter\ImageConverter.exe");
        var pngMenu = plan.Menus.Single(menu => menu.Extension == ".png");

        foreach (var formatNode in pngMenu.Entries)
        {
            Assert.Null(formatNode.Command);
            Assert.NotNull(formatNode.Children);
            Assert.Equal(3, formatNode.Children!.Count);
            Assert.All(formatNode.Children, preset => Assert.Equal(3, preset.Children!.Count));
        }
    }

    [Fact]
    public void PresetLeafCommandsCarryQualityAndBehavior()
    {
        var plan = ShellMenuCatalog.Build(@"C:\Apps\ImageConverter\ImageConverter.exe");
        var pngMenu = plan.Menus.Single(menu => menu.Extension == ".png");

        // PNG -> Convert to WebP -> Web (quality) -> Same folder
        var sameFolder = Leaf(pngMenu.Entries, "20_ToWebp", "20_Quality", "1_Same");
        Assert.Contains("\"C:\\Apps\\ImageConverter\\ImageConverter.exe\"", sameFolder.Command!, StringComparison.Ordinal);
        Assert.Contains("convert --from-shell --to webp --if-exists skip --quality 88", sameFolder.Command!, StringComparison.Ordinal);
        Assert.DoesNotContain("--remove-original", sameFolder.Command!, StringComparison.Ordinal);
        Assert.DoesNotContain("--output new", sameFolder.Command!, StringComparison.Ordinal);
        Assert.Contains("\"%1\"", sameFolder.Command!, StringComparison.Ordinal);

        // PNG -> Convert to JPG -> Storage (premium) -> Remove original
        var premiumRemove = Leaf(pngMenu.Entries, "10_ToJpg", "30_Premium", "3_Remove");
        Assert.Contains("--to jpg --if-exists skip --quality 95", premiumRemove.Command!, StringComparison.Ordinal);
        Assert.Contains("--remove-original", premiumRemove.Command!, StringComparison.Ordinal);

        // PNG -> Convert to AVIF -> Web (fast) -> New folder
        var fastNew = Leaf(pngMenu.Entries, "30_ToAvif", "10_Fast", "2_New");
        Assert.Contains("--to avif --if-exists skip --quality 75", fastNew.Command!, StringComparison.Ordinal);
        Assert.Contains("--output new", fastNew.Command!, StringComparison.Ordinal);
    }

    private static ShellMenuEntryDefinition Leaf(
        IReadOnlyList<ShellMenuEntryDefinition> formatNodes,
        string formatId,
        string presetId,
        string behaviorId)
    {
        var preset = formatNodes.Single(node => node.Id == formatId).Children!.Single(child => child.Id == presetId);
        return preset.Children!.Single(child => child.Id == behaviorId);
    }

    private static int CountLeaves(IReadOnlyList<ShellMenuEntryDefinition> entries) =>
        entries.Sum(entry => entry.Children is { Count: > 0 } children ? CountLeaves(children) : 1);

    [Fact]
    public void CleanupListIncludesLegacyRegistryKeys()
    {
        var plan = ShellMenuCatalog.Build(@"C:\Apps\ImageConverter\ImageConverter.exe");

        Assert.Contains(@"Software\Classes\SystemFileAssociations\.png\shell\PngConvert", plan.CleanupKeyPaths);
        Assert.Contains(@"Software\Microsoft\Windows\CurrentVersion\Explorer\CommandStore\shell\PngConvert.ToAvif", plan.CleanupKeyPaths);
    }

    [Fact]
    public void CleanupListCoversEveryRegisteredMenuRoot()
    {
        var plan = ShellMenuCatalog.Build(@"C:\Apps\ImageConverter\ImageConverter.exe");

        foreach (var menu in plan.Menus)
        {
            var expectedPath = $@"Software\Classes\SystemFileAssociations\{menu.Extension}\shell\{menu.MenuKey}";
            Assert.Contains(expectedPath, plan.CleanupKeyPaths);
        }
    }
}
