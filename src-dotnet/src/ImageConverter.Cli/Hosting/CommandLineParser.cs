using ImageConverter.Core;

namespace ImageConverter.Cli.Hosting;

internal abstract record CliCommand;

internal sealed record HelpCommand : CliCommand;

internal sealed record RegisterShellCommand(string? InstallDirectory) : CliCommand;

internal sealed record UnregisterShellCommand : CliCommand;

internal sealed record ConvertCommand(
    IReadOnlyList<string> Paths,
    ImageFormat TargetFormat,
    OutputMode OutputMode,
    FileExistsPolicy FileExistsPolicy,
    bool RemoveOriginal,
    bool FromShell,
    int Quality) : CliCommand;

internal static class CommandLineParser
{
    public static bool TryParse(string[] args, out CliCommand command, out string? error)
    {
        command = new HelpCommand();
        error = null;

        if (args.Length == 0 || args[0] is "-h" or "--help" or "help")
        {
            return true;
        }

        return args[0].ToLowerInvariant() switch
        {
            "convert" => TryParseConvert(args[1..], out command, out error),
            "register-shell" => TryParseRegisterShell(args[1..], out command, out error),
            "unregister-shell" => TryParseUnregisterShell(args[1..], out command, out error),
            _ => Fail("Unknown command.", out command, out error)
        };
    }

    private static bool TryParseConvert(string[] args, out CliCommand command, out string? error)
    {
        var paths = new List<string>();
        var outputMode = OutputMode.SameFolder;
        var fileExistsPolicy = FileExistsPolicy.Skip;
        var removeOriginal = false;
        var fromShell = false;
        var quality = 80;
        ImageFormat? targetFormat = null;

        for (var index = 0; index < args.Length; index++)
        {
            var token = args[index];
            switch (token)
            {
                case "--to":
                    if (!TryGetValue(args, ref index, out var formatToken) ||
                        !ImageFormatInfo.TryParseCliToken(formatToken, out var parsedFormat))
                    {
                        return Fail("Missing or invalid value for --to.", out command, out error);
                    }

                    targetFormat = parsedFormat;
                    break;

                case "--output":
                    if (!TryGetValue(args, ref index, out var outputToken))
                    {
                        return Fail("Missing value for --output.", out command, out error);
                    }

                    outputMode = outputToken.ToLowerInvariant() switch
                    {
                        "same" => OutputMode.SameFolder,
                        "new" => OutputMode.TargetSubfolder,
                        _ => throw new InvalidOperationException("Invalid output mode.")
                    };
                    break;

                case "--if-exists":
                    if (!TryGetValue(args, ref index, out var policyToken))
                    {
                        return Fail("Missing value for --if-exists.", out command, out error);
                    }

                    fileExistsPolicy = policyToken.ToLowerInvariant() switch
                    {
                        "skip" => FileExistsPolicy.Skip,
                        "suffix" => FileExistsPolicy.Suffix,
                        "overwrite" => FileExistsPolicy.Overwrite,
                        _ => throw new InvalidOperationException("Invalid file exists policy.")
                    };
                    break;

                case "--remove-original":
                    removeOriginal = true;
                    break;

                case "--from-shell":
                    fromShell = true;
                    break;

                case "--quality":
                    if (!TryGetValue(args, ref index, out var qualityToken) ||
                        !int.TryParse(qualityToken, out quality) ||
                        quality is < 0 or > 100)
                    {
                        return Fail("Missing or invalid value for --quality.", out command, out error);
                    }
                    break;

                case "--overwrite":
                    fileExistsPolicy = FileExistsPolicy.Overwrite;
                    break;

                default:
                    paths.Add(token);
                    break;
            }
        }

        if (targetFormat is null)
        {
            return Fail("The convert command requires --to.", out command, out error);
        }

        if (paths.Count == 0)
        {
            return Fail("The convert command requires at least one input path.", out command, out error);
        }

        command = new ConvertCommand(paths, targetFormat.Value, outputMode, fileExistsPolicy, removeOriginal, fromShell, quality);
        error = null;
        return true;
    }

    private static bool TryParseRegisterShell(string[] args, out CliCommand command, out string? error)
    {
        string? installDirectory = null;

        for (var index = 0; index < args.Length; index++)
        {
            var token = args[index];
            if (token != "--install-dir")
            {
                return Fail($"Unknown register-shell option: {token}", out command, out error);
            }

            if (!TryGetValue(args, ref index, out installDirectory))
            {
                return Fail("Missing value for --install-dir.", out command, out error);
            }
        }

        command = new RegisterShellCommand(installDirectory);
        error = null;
        return true;
    }

    private static bool TryParseUnregisterShell(string[] args, out CliCommand command, out string? error)
    {
        if (args.Length != 0)
        {
            return Fail("unregister-shell does not accept arguments.", out command, out error);
        }

        command = new UnregisterShellCommand();
        error = null;
        return true;
    }

    private static bool TryGetValue(string[] args, ref int index, out string value)
    {
        var nextIndex = index + 1;
        if (nextIndex >= args.Length)
        {
            value = string.Empty;
            return false;
        }

        index = nextIndex;
        value = args[nextIndex];
        return true;
    }

    private static bool Fail(string message, out CliCommand command, out string? error)
    {
        command = new HelpCommand();
        error = message;
        return false;
    }
}
