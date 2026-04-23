namespace ImageConverter.Core;

public sealed class BatchConversionService
{
    private readonly IImageTranscoder _imageTranscoder;

    public BatchConversionService(IImageTranscoder imageTranscoder)
    {
        _imageTranscoder = imageTranscoder;
    }

    public async Task<BatchConversionResult> ConvertAsync(
        BatchConversionRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);

        if (request.Quality is < 0 or > 100)
        {
            throw new ArgumentOutOfRangeException(nameof(request), "Quality must be between 0 and 100.");
        }

        var files = InputPathResolver.ResolveFiles(request.InputPaths);
        var results = new List<FileConversionResult>(files.Count);

        foreach (var file in files)
        {
            cancellationToken.ThrowIfCancellationRequested();
            results.Add(await ConvertSingleAsync(file, request, cancellationToken).ConfigureAwait(false));
        }

        return new BatchConversionResult(results);
    }

    private async Task<FileConversionResult> ConvertSingleAsync(
        string sourcePath,
        BatchConversionRequest request,
        CancellationToken cancellationToken)
    {
        if (!ImageFormatInfo.TryGetFormatFromPath(sourcePath, out var sourceFormat))
        {
            return new FileConversionResult(
                sourcePath,
                null,
                null,
                request.TargetFormat,
                FileConversionStatus.Skipped,
                "unsupported-source-format");
        }

        var skipReason = ConversionSafetyRules.GetSkipReason(sourceFormat, request.TargetFormat);
        if (skipReason is not null)
        {
            return new FileConversionResult(
                sourcePath,
                null,
                sourceFormat,
                request.TargetFormat,
                FileConversionStatus.Skipped,
                skipReason);
        }

        var outputPath = OutputPathResolver.ResolveOutputPath(
            sourcePath,
            request.TargetFormat,
            request.OutputMode,
            request.FileExistsPolicy);

        if (outputPath is null)
        {
            return new FileConversionResult(
                sourcePath,
                null,
                sourceFormat,
                request.TargetFormat,
                FileConversionStatus.Skipped,
                "target-exists");
        }

        try
        {
            await _imageTranscoder.TranscodeAsync(
                new TranscodeRequest(sourcePath, outputPath, sourceFormat, request.TargetFormat, request.Quality),
                cancellationToken).ConfigureAwait(false);

            if (!OutputPathResolver.IsReadyOutput(outputPath))
            {
                throw new InvalidOperationException("Output file was not created or is empty.");
            }

            var removed = false;
            if (request.RemoveOriginal)
            {
                if (!OutputPathResolver.IsReadyOutput(outputPath))
                {
                    throw new InvalidOperationException("Original cannot be removed because the output file is not ready.");
                }

                File.Delete(sourcePath);
                removed = true;
            }

            return new FileConversionResult(
                sourcePath,
                outputPath,
                sourceFormat,
                request.TargetFormat,
                FileConversionStatus.Converted,
                "converted",
                removed);
        }
        catch (Exception exception)
        {
            return new FileConversionResult(
                sourcePath,
                outputPath,
                sourceFormat,
                request.TargetFormat,
                FileConversionStatus.Failed,
                exception.Message);
        }
    }
}
