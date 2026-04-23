using ImageConverter.Core;

namespace ImageConverter.Tests;

public sealed class SafetyRuleTests
{
    [Theory]
    [InlineData(ImageFormat.Jpg, ImageFormat.Png, true)]
    [InlineData(ImageFormat.Webp, ImageFormat.Png, true)]
    [InlineData(ImageFormat.Avif, ImageFormat.Png, true)]
    [InlineData(ImageFormat.Png, ImageFormat.Webp, false)]
    [InlineData(ImageFormat.Png, ImageFormat.Jpg, false)]
    public void LossyToLosslessRuleMatchesExpectedCases(ImageFormat source, ImageFormat target, bool expected)
    {
        Assert.Equal(expected, ConversionSafetyRules.IsLossyToLosslessBlocked(source, target));
    }
}
