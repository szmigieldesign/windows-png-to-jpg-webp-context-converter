using ImageConverter.Core;

namespace ImageConverter.Tests;

public sealed class BatchConversionServiceTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "ImageConverter.Tests", Guid.NewGuid().ToString("N"));

    public BatchConversionServiceTests()
    {
        Directory.CreateDirectory(_root);
    }

    [Fact]
    public async Task LossyToLosslessConversionIsSkipped()
    {
        var source = CreateFile("photo.jpg");
        var service = new BatchConversionService(new FakeTranscoder());

        var result = await service.ConvertAsync(new BatchConversionRequest(
            [source],
            ImageFormat.Png,
            OutputMode.SameFolder,
            FileExistsPolicy.Skip,
            RemoveOriginal: false));

        var file = Assert.Single(result.Files);
        Assert.Equal(FileConversionStatus.Skipped, file.Status);
        Assert.Equal("lossy-to-lossless-blocked", file.Message);
    }

    [Fact]
    public async Task RemoveOriginalOnlyHappensAfterSuccessfulOutput()
    {
        var source = CreateFile("image.png");
        var service = new BatchConversionService(new FakeTranscoder(request =>
        {
            Directory.CreateDirectory(Path.GetDirectoryName(request.DestinationPath)!);
            File.WriteAllBytes(request.DestinationPath, [9, 8, 7]);
        }));

        var result = await service.ConvertAsync(new BatchConversionRequest(
            [source],
            ImageFormat.Jpg,
            OutputMode.SameFolder,
            FileExistsPolicy.Skip,
            RemoveOriginal: true));

        var file = Assert.Single(result.Files);
        Assert.Equal(FileConversionStatus.Converted, file.Status);
        Assert.True(file.OriginalRemoved);
        Assert.False(File.Exists(source));
        Assert.True(File.Exists(Path.Combine(_root, "image.jpg")));
    }

    [Fact]
    public async Task MissingOutputPreventsOriginalRemoval()
    {
        var source = CreateFile("image.png");
        var service = new BatchConversionService(new FakeTranscoder());

        var result = await service.ConvertAsync(new BatchConversionRequest(
            [source],
            ImageFormat.Jpg,
            OutputMode.SameFolder,
            FileExistsPolicy.Skip,
            RemoveOriginal: true));

        var file = Assert.Single(result.Files);
        Assert.Equal(FileConversionStatus.Failed, file.Status);
        Assert.True(File.Exists(source));
        Assert.False(File.Exists(Path.Combine(_root, "image.jpg")));
    }

    [Fact]
    public async Task BatchSummaryCountsMixedResults()
    {
        var ok = CreateFile("ok.png");
        var same = CreateFile("same.jpg");
        var failing = CreateFile("fail.png");

        var service = new BatchConversionService(new FakeTranscoder(request =>
        {
            if (Path.GetFileNameWithoutExtension(request.SourcePath).Equals("fail", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("simulated-failure");
            }

            Directory.CreateDirectory(Path.GetDirectoryName(request.DestinationPath)!);
            File.WriteAllBytes(request.DestinationPath, [1]);
        }));

        var result = await service.ConvertAsync(new BatchConversionRequest(
            [ok, same, failing],
            ImageFormat.Jpg,
            OutputMode.SameFolder,
            FileExistsPolicy.Skip,
            RemoveOriginal: false));

        Assert.Equal(1, result.ConvertedCount);
        Assert.Equal(1, result.SkippedCount);
        Assert.Equal(1, result.FailedCount);
        Assert.Equal(1, result.ExitCode);
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

    private sealed class FakeTranscoder : IImageTranscoder
    {
        private readonly Action<TranscodeRequest>? _behavior;

        public FakeTranscoder(Action<TranscodeRequest>? behavior = null)
        {
            _behavior = behavior;
        }

        public Task TranscodeAsync(TranscodeRequest request, CancellationToken cancellationToken = default)
        {
            _behavior?.Invoke(request);
            return Task.CompletedTask;
        }
    }
}
