using System.Collections.ObjectModel;

namespace ImageConverter.Core;

public static class ImageFormatInfo
{
    public static readonly ReadOnlyDictionary<string, ImageFormat> ExtensionMap =
        new(new Dictionary<string, ImageFormat>(StringComparer.OrdinalIgnoreCase)
        {
            [".png"] = ImageFormat.Png,
            [".jpg"] = ImageFormat.Jpg,
            [".jpeg"] = ImageFormat.Jpg,
            [".webp"] = ImageFormat.Webp,
            [".avif"] = ImageFormat.Avif
        });

    public static string GetDefaultExtension(ImageFormat format) =>
        format switch
        {
            ImageFormat.Png => ".png",
            ImageFormat.Jpg => ".jpg",
            ImageFormat.Webp => ".webp",
            ImageFormat.Avif => ".avif",
            _ => throw new ArgumentOutOfRangeException(nameof(format), format, null)
        };

    public static string GetTargetFolderName(ImageFormat format) =>
        format switch
        {
            ImageFormat.Png => "PNG",
            ImageFormat.Jpg => "JPEG",
            ImageFormat.Webp => "WEBP",
            ImageFormat.Avif => "AVIF",
            _ => throw new ArgumentOutOfRangeException(nameof(format), format, null)
        };

    public static string ToCliToken(ImageFormat format) =>
        format switch
        {
            ImageFormat.Png => "png",
            ImageFormat.Jpg => "jpg",
            ImageFormat.Webp => "webp",
            ImageFormat.Avif => "avif",
            _ => throw new ArgumentOutOfRangeException(nameof(format), format, null)
        };

    public static bool TryParseCliToken(string value, out ImageFormat format)
    {
        var normalized = value.Trim().ToLowerInvariant();
        format = normalized switch
        {
            "png" => ImageFormat.Png,
            "jpg" or "jpeg" => ImageFormat.Jpg,
            "webp" => ImageFormat.Webp,
            "avif" => ImageFormat.Avif,
            _ => default
        };

        return normalized is "png" or "jpg" or "jpeg" or "webp" or "avif";
    }

    public static bool TryGetFormatFromPath(string path, out ImageFormat format) =>
        ExtensionMap.TryGetValue(Path.GetExtension(path), out format);
}

public static class InputPathResolver
{
    public static IReadOnlyList<string> ResolveFiles(IEnumerable<string> rawPaths)
    {
        var resolved = new SortedSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var rawPath in rawPaths)
        {
            if (string.IsNullOrWhiteSpace(rawPath))
            {
                continue;
            }

            var trimmedPath = rawPath.Trim();
            if (trimmedPath == "--")
            {
                continue;
            }

            if (Directory.Exists(trimmedPath))
            {
                foreach (var file in Directory.EnumerateFiles(trimmedPath, "*", SearchOption.TopDirectoryOnly))
                {
                    if (ImageFormatInfo.TryGetFormatFromPath(file, out _))
                    {
                        resolved.Add(Path.GetFullPath(file));
                    }
                }

                continue;
            }

            if (File.Exists(trimmedPath) && ImageFormatInfo.TryGetFormatFromPath(trimmedPath, out _))
            {
                resolved.Add(Path.GetFullPath(trimmedPath));
            }
        }

        return resolved.ToArray();
    }
}

public static class OutputPathResolver
{
    public static string GetOutputDirectory(string sourcePath, ImageFormat targetFormat, OutputMode outputMode)
    {
        var sourceDirectory = Path.GetDirectoryName(sourcePath)
            ?? throw new InvalidOperationException($"Source path has no directory: {sourcePath}");

        return outputMode == OutputMode.SameFolder
            ? sourceDirectory
            : Path.Combine(sourceDirectory, ImageFormatInfo.GetTargetFolderName(targetFormat));
    }

    public static string? ResolveOutputPath(
        string sourcePath,
        ImageFormat targetFormat,
        OutputMode outputMode,
        FileExistsPolicy fileExistsPolicy)
    {
        var outputDirectory = GetOutputDirectory(sourcePath, targetFormat, outputMode);
        Directory.CreateDirectory(outputDirectory);

        var baseName = Path.GetFileNameWithoutExtension(sourcePath);
        var extension = ImageFormatInfo.GetDefaultExtension(targetFormat);
        var candidate = Path.Combine(outputDirectory, $"{baseName}{extension}");

        if (fileExistsPolicy == FileExistsPolicy.Overwrite || !File.Exists(candidate) || !IsReadyOutput(candidate))
        {
            return candidate;
        }

        if (fileExistsPolicy == FileExistsPolicy.Skip)
        {
            return null;
        }

        for (var index = 1; ; index++)
        {
            var suffixed = Path.Combine(outputDirectory, $"{baseName}-{index}{extension}");
            if (!File.Exists(suffixed) || !IsReadyOutput(suffixed))
            {
                return suffixed;
            }
        }
    }

    public static bool IsReadyOutput(string path)
    {
        if (!File.Exists(path))
        {
            return false;
        }

        var info = new FileInfo(path);
        return info.Exists && info.Length > 0;
    }
}

public static class ConversionSafetyRules
{
    public static bool IsLossy(ImageFormat format) =>
        format is ImageFormat.Jpg or ImageFormat.Webp or ImageFormat.Avif;

    public static bool IsLossless(ImageFormat format) => format == ImageFormat.Png;

    public static bool IsLossyToLosslessBlocked(ImageFormat sourceFormat, ImageFormat targetFormat) =>
        IsLossy(sourceFormat) && IsLossless(targetFormat);

    public static string? GetSkipReason(ImageFormat sourceFormat, ImageFormat targetFormat)
    {
        if (sourceFormat == targetFormat)
        {
            return "same-format";
        }

        if (IsLossyToLosslessBlocked(sourceFormat, targetFormat))
        {
            return "lossy-to-lossless-blocked";
        }

        return null;
    }
}
