namespace ImageConverter.Core;

public enum ImageFormat
{
    Png,
    Jpg,
    Webp,
    Avif
}

public enum OutputMode
{
    SameFolder,
    TargetSubfolder
}

public enum FileExistsPolicy
{
    Skip,
    Suffix,
    Overwrite
}

public enum FileConversionStatus
{
    Converted,
    Skipped,
    Failed
}

public sealed record BatchConversionRequest(
    IReadOnlyCollection<string> InputPaths,
    ImageFormat TargetFormat,
    OutputMode OutputMode,
    FileExistsPolicy FileExistsPolicy,
    bool RemoveOriginal,
    int Quality = 80);

public sealed record FileConversionResult(
    string SourcePath,
    string? TargetPath,
    ImageFormat? SourceFormat,
    ImageFormat TargetFormat,
    FileConversionStatus Status,
    string Message,
    bool OriginalRemoved = false);

public sealed class BatchConversionResult
{
    public BatchConversionResult(IReadOnlyList<FileConversionResult> files)
    {
        Files = files;
    }

    public IReadOnlyList<FileConversionResult> Files { get; }

    public int ConvertedCount => Files.Count(file => file.Status == FileConversionStatus.Converted);

    public int SkippedCount => Files.Count(file => file.Status == FileConversionStatus.Skipped);

    public int FailedCount => Files.Count(file => file.Status == FileConversionStatus.Failed);

    public int RemovedCount => Files.Count(file => file.OriginalRemoved);

    public int ExitCode => FailedCount > 0 ? 1 : 0;

    public NotificationSummary ToNotificationSummary()
    {
        var message = FailedCount switch
        {
            > 0 => $"Done with errors. Converted: {ConvertedCount}, Skipped: {SkippedCount}, Failed: {FailedCount}",
            0 when ConvertedCount > 0 => $"Done. Converted: {ConvertedCount}, Skipped: {SkippedCount}",
            _ => $"Done. Skipped: {SkippedCount}"
        };

        return new NotificationSummary("Image Converter", message, ConvertedCount, SkippedCount, FailedCount, RemovedCount);
    }
}

public sealed record NotificationSummary(
    string Title,
    string Message,
    int Converted,
    int Skipped,
    int Failed,
    int Removed);

public sealed record TranscodeRequest(
    string SourcePath,
    string DestinationPath,
    ImageFormat SourceFormat,
    ImageFormat TargetFormat,
    int Quality);
