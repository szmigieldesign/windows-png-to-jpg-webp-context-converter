using ImageConverter.Core;

namespace ImageConverter.Tests;

public sealed class PathResolutionTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "ImageConverter.Tests", Guid.NewGuid().ToString("N"));

    public PathResolutionTests()
    {
        Directory.CreateDirectory(_root);
    }

    [Fact]
    public void SameFolderModeKeepsOutputNextToSource()
    {
        var source = CreateFile("sample.png");

        var output = OutputPathResolver.ResolveOutputPath(
            source,
            ImageFormat.Jpg,
            OutputMode.SameFolder,
            FileExistsPolicy.Skip);

        Assert.Equal(Path.Combine(_root, "sample.jpg"), output);
    }

    [Fact]
    public void TargetSubfolderModeUsesFormatFolder()
    {
        var source = CreateFile("sample.png");

        var output = OutputPathResolver.ResolveOutputPath(
            source,
            ImageFormat.Webp,
            OutputMode.TargetSubfolder,
            FileExistsPolicy.Skip);

        Assert.Equal(Path.Combine(_root, "WEBP", "sample.webp"), output);
    }

    [Fact]
    public void SuffixPolicyCreatesNextAvailableName()
    {
        var source = CreateFile("sample.png");
        File.WriteAllBytes(Path.Combine(_root, "sample.jpg"), [1]);
        File.WriteAllBytes(Path.Combine(_root, "sample-1.jpg"), [1]);

        var output = OutputPathResolver.ResolveOutputPath(
            source,
            ImageFormat.Jpg,
            OutputMode.SameFolder,
            FileExistsPolicy.Suffix);

        Assert.Equal(Path.Combine(_root, "sample-2.jpg"), output);
    }

    [Fact]
    public void OverwritePolicyKeepsOriginalOutputPath()
    {
        var source = CreateFile("sample.png");
        File.WriteAllBytes(Path.Combine(_root, "sample.jpg"), [1]);

        var output = OutputPathResolver.ResolveOutputPath(
            source,
            ImageFormat.Jpg,
            OutputMode.SameFolder,
            FileExistsPolicy.Overwrite);

        Assert.Equal(Path.Combine(_root, "sample.jpg"), output);
    }

    [Fact]
    public void SkipPolicyReturnsNullWhenExistingOutputIsReady()
    {
        var source = CreateFile("sample.png");
        File.WriteAllBytes(Path.Combine(_root, "sample.jpg"), [1]);

        var output = OutputPathResolver.ResolveOutputPath(
            source,
            ImageFormat.Jpg,
            OutputMode.SameFolder,
            FileExistsPolicy.Skip);

        Assert.Null(output);
    }

    public void Dispose()
    {
        if (Directory.Exists(_root))
        {
            Directory.Delete(_root, recursive: true);
        }
    }

    private string CreateFile(string relativePath)
    {
        var path = Path.Combine(_root, relativePath);
        File.WriteAllBytes(path, [1, 2, 3]);
        return path;
    }
}
