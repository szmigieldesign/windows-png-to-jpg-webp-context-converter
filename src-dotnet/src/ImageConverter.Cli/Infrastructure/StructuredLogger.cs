namespace ImageConverter.Cli.Infrastructure;

internal sealed class StructuredLogger : IDisposable
{
    private readonly StreamWriter? _fileWriter;

    private StructuredLogger(StreamWriter? fileWriter)
    {
        _fileWriter = fileWriter;
    }

    public static StructuredLogger Create(bool enableFileLogging)
    {
        if (!enableFileLogging)
        {
            return new StructuredLogger(null);
        }

        var logDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "ImageConverter",
            "Logs");

        Directory.CreateDirectory(logDirectory);
        var logPath = Path.Combine(logDirectory, "image-converter.log");
        var fileWriter = new StreamWriter(new FileStream(logPath, FileMode.Append, FileAccess.Write, FileShare.ReadWrite))
        {
            AutoFlush = true
        };

        return new StructuredLogger(fileWriter);
    }

    public void Info(string eventName, IReadOnlyDictionary<string, string?> fields) => Write("info", eventName, fields);

    public void Error(string eventName, IReadOnlyDictionary<string, string?> fields) => Write("error", eventName, fields);

    public void Dispose()
    {
        _fileWriter?.Dispose();
    }

    private void Write(string level, string eventName, IReadOnlyDictionary<string, string?> fields)
    {
        var orderedFields = fields
            .Where(pair => pair.Value is not null)
            .OrderBy(pair => pair.Key, StringComparer.Ordinal)
            .Select(pair => $"{pair.Key}=\"{Escape(pair.Value!)}\"");

        var line = $"level={level} event={eventName}";
        if (orderedFields.Any())
        {
            line = $"{line} {string.Join(' ', orderedFields)}";
        }

        SafeWrite(Console.Out, line);
        if (_fileWriter is not null)
        {
            SafeWrite(_fileWriter, line);
        }
    }

    private static void SafeWrite(TextWriter writer, string line)
    {
        try
        {
            writer.WriteLine(line);
            writer.Flush();
        }
        catch
        {
            // No-op.
        }
    }

    private static string Escape(string value) => value.Replace("\\", "\\\\", StringComparison.Ordinal).Replace("\"", "\\\"", StringComparison.Ordinal);
}
