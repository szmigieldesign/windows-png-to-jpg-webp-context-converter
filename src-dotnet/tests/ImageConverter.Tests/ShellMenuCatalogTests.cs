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
        Assert.Equal(9, plan.Menus.Single(menu => menu.Extension == ".png").Entries.Count);
        Assert.Equal(6, plan.Menus.Single(menu => menu.Extension == ".jpg").Entries.Count);
        Assert.Equal(6, plan.Menus.Single(menu => menu.Extension == ".webp").Entries.Count);
    }

    [Fact]
    public void CommandsPointToNewExecutableAndShellMode()
    {
        var plan = ShellMenuCatalog.Build(@"C:\Apps\ImageConverter\ImageConverter.exe");
        var pngMenu = plan.Menus.Single(menu => menu.Extension == ".png");
        var toWebp = pngMenu.Entries.Single(entry => entry.Id == "20_ToWebp");

        Assert.Contains("\"C:\\Apps\\ImageConverter\\ImageConverter.exe\"", toWebp.Command, StringComparison.Ordinal);
        Assert.Contains("convert --from-shell --to webp", toWebp.Command, StringComparison.Ordinal);
        Assert.Contains("\"%1\"", toWebp.Command, StringComparison.Ordinal);
    }

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
