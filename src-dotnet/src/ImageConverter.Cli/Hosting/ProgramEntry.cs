using System.Windows.Forms;
using ImageConverter.Cli.Infrastructure;
using ImageConverter.Core;
using ImageConverter.Shell;

namespace ImageConverter.Cli.Hosting;

internal static class ProgramEntry
{
    public static async Task<int> RunAsync(string[] args)
    {
        ConsoleHelper.Initialize();

        if (!CommandLineParser.TryParse(args, out var command, out var error))
        {
            WriteUsage(error);
            return 2;
        }

        try
        {
            return command switch
            {
                ConvertCommand convertCommand => await RunConvertAsync(convertCommand).ConfigureAwait(false),
                RegisterShellCommand registerShellCommand => RunRegisterShell(registerShellCommand),
                UnregisterShellCommand => RunUnregisterShell(),
                HelpCommand => WriteUsage(null),
                _ => 2
            };
        }
        catch (Exception exception)
        {
            SafeConsoleWrite(Console.Error, $"level=error event=unhandled message=\"{Escape(exception.Message)}\"");
            return command is RegisterShellCommand or UnregisterShellCommand ? 3 : 1;
        }
    }

    private static async Task<int> RunConvertAsync(ConvertCommand command)
    {
        using var shellBatchSession = command.FromShell
            ? await ShellBatchCoordinator.AcquireAsync(command).ConfigureAwait(false)
            : ShellBatchSession.Direct(command.Paths);

        if (!shellBatchSession.IsOwner)
        {
            return 0;
        }

        var logger = StructuredLogger.Create(command.FromShell);
        var request = new BatchConversionRequest(
            shellBatchSession.Paths,
            command.TargetFormat,
            command.OutputMode,
            command.FileExistsPolicy,
            command.RemoveOriginal,
            command.Quality);

        logger.Info("batch_started", new Dictionary<string, string?>
        {
            ["count"] = request.InputPaths.Count.ToString(),
            ["format"] = ImageFormatInfo.ToCliToken(request.TargetFormat),
            ["if_exists"] = command.FileExistsPolicy.ToString().ToLowerInvariant(),
            ["output"] = command.OutputMode == OutputMode.TargetSubfolder ? "new" : "same",
            ["remove_original"] = command.RemoveOriginal ? "true" : "false",
            ["shell"] = command.FromShell ? "true" : "false"
        });

        var service = new BatchConversionService(new MagickImageTranscoder());
        var result = await service.ConvertAsync(request).ConfigureAwait(false);

        foreach (var file in result.Files)
        {
            var fields = new Dictionary<string, string?>
            {
                ["source"] = file.SourcePath,
                ["target"] = file.TargetPath,
                ["status"] = file.Status.ToString().ToLowerInvariant(),
                ["message"] = file.Message
            };

            if (file.OriginalRemoved)
            {
                fields["removed_original"] = "true";
            }

            if (file.Status == FileConversionStatus.Failed)
            {
                logger.Error("file_processed", fields);
            }
            else
            {
                logger.Info("file_processed", fields);
            }
        }

        logger.Info("batch_completed", new Dictionary<string, string?>
        {
            ["converted"] = result.ConvertedCount.ToString(),
            ["skipped"] = result.SkippedCount.ToString(),
            ["failed"] = result.FailedCount.ToString(),
            ["removed"] = result.RemovedCount.ToString()
        });

        if (command.FromShell && result.Files.Count > 0)
        {
            var summary = result.ToNotificationSummary();
            MessageBox.Show(
                summary.Message,
                summary.Title,
                MessageBoxButtons.OK,
                result.FailedCount > 0 ? MessageBoxIcon.Warning : MessageBoxIcon.Information);
        }

        return result.ExitCode;
    }

    private static int RunRegisterShell(RegisterShellCommand command)
    {
        var executablePath = ResolveExecutablePath(command.InstallDirectory);
        var registrar = new WindowsShellRegistrar();
        registrar.Register(executablePath);
        SafeConsoleWrite(Console.Out, $"level=info event=shell_registered executable=\"{Escape(executablePath)}\"");
        return 0;
    }

    private static int RunUnregisterShell()
    {
        var registrar = new WindowsShellRegistrar();
        registrar.Unregister();
        SafeConsoleWrite(Console.Out, "level=info event=shell_unregistered");
        return 0;
    }

    private static string ResolveExecutablePath(string? installDirectory)
    {
        if (string.IsNullOrWhiteSpace(installDirectory))
        {
            return Environment.ProcessPath
                ?? throw new InvalidOperationException("Unable to determine the current executable path.");
        }

        var fullPath = Path.GetFullPath(installDirectory);
        if (File.Exists(fullPath))
        {
            return fullPath;
        }

        return Path.Combine(fullPath, "ImageConverter.exe");
    }

    private static int WriteUsage(string? error)
    {
        if (!string.IsNullOrWhiteSpace(error))
        {
            SafeConsoleWrite(Console.Error, $"error: {error}");
        }

        const string usage = """
Image Converter

Commands:
  convert --to <jpg|webp|avif|png> --output <same|new> --if-exists <skip|suffix|overwrite> --remove-original --quality <0-100> [--from-shell] <paths...>
  register-shell --install-dir <path>
  unregister-shell
""";

        SafeConsoleWrite(Console.Out, usage);
        return string.IsNullOrWhiteSpace(error) ? 0 : 2;
    }

    private static void SafeConsoleWrite(TextWriter writer, string message)
    {
        try
        {
            writer.WriteLine(message);
            writer.Flush();
        }
        catch
        {
            // Shell launches should not fail because stdout/stderr is unavailable.
        }
    }

    private static string Escape(string value) => value.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal);
}
