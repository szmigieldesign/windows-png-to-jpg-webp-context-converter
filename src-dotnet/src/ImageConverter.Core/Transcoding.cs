using ImageMagick;

namespace ImageConverter.Core;

public interface IImageTranscoder
{
    Task TranscodeAsync(TranscodeRequest request, CancellationToken cancellationToken = default);
}

public sealed class MagickImageTranscoder : IImageTranscoder
{
    public Task TranscodeAsync(TranscodeRequest request, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        using var image = new MagickImage(request.SourcePath);
        image.AutoOrient();
        image.Strip();
        image.ColorSpace = ColorSpace.sRGB;
        image.Depth = 8;

        switch (request.TargetFormat)
        {
            case ImageFormat.Jpg:
                image.BackgroundColor = MagickColors.White;
                image.Alpha(AlphaOption.Remove);
                image.Quality = (uint)request.Quality;
                image.Format = MagickFormat.Jpg;
                break;

            case ImageFormat.Webp:
                image.Settings.SetDefine(MagickFormat.WebP, "method", "6");
                image.Settings.SetDefine(MagickFormat.WebP, "use-sharp-yuv", "true");
                image.Settings.SetDefine(MagickFormat.WebP, "alpha-quality", "90");
                image.Quality = (uint)request.Quality;
                image.Format = MagickFormat.WebP;
                break;

            case ImageFormat.Avif:
                image.Settings.SetDefine(MagickFormat.Heic, "speed", "6");
                image.Quality = (uint)request.Quality;
                image.Format = MagickFormat.Avif;
                break;

            case ImageFormat.Png:
                image.Settings.SetDefine(MagickFormat.Png, "compression-level", "9");
                image.Format = MagickFormat.Png;
                break;

            default:
                throw new ArgumentOutOfRangeException(nameof(request.TargetFormat), request.TargetFormat, null);
        }

        Directory.CreateDirectory(Path.GetDirectoryName(request.DestinationPath)!);
        image.Write(request.DestinationPath);
        return Task.CompletedTask;
    }
}
