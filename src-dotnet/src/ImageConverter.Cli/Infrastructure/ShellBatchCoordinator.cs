using System.IO.Pipes;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using ImageConverter.Cli.Hosting;
using ImageConverter.Core;

namespace ImageConverter.Cli.Infrastructure;

internal sealed class ShellBatchSession : IDisposable
{
    private readonly Mutex? _mutex;

    private ShellBatchSession(bool isOwner, IReadOnlyList<string> paths, Mutex? mutex)
    {
        IsOwner = isOwner;
        Paths = paths;
        _mutex = mutex;
    }

    public bool IsOwner { get; }

    public IReadOnlyList<string> Paths { get; }

    public static ShellBatchSession Direct(IReadOnlyList<string> paths) => new(true, paths, null);

    public static ShellBatchSession Owner(IReadOnlyList<string> paths, Mutex mutex) => new(true, paths, mutex);

    public static ShellBatchSession Forwarded() => new(false, Array.Empty<string>(), null);

    public void Dispose()
    {
        _mutex?.ReleaseMutex();
        _mutex?.Dispose();
    }
}

internal sealed record ShellBatchMessage(IReadOnlyList<string> Paths);

internal static class ShellBatchCoordinator
{
    private static readonly TimeSpan QuietPeriod = TimeSpan.FromMilliseconds(900);
    private static readonly TimeSpan ClientConnectTimeout = TimeSpan.FromMilliseconds(250);

    public static async Task<ShellBatchSession> AcquireAsync(ConvertCommand command)
    {
        var channel = BuildChannel(command);
        var mutexName = $@"Local\ImageConverter.ShellBatch.{channel}";
        var pipeName = $"ImageConverter-{channel}";

        if (TryBecomeOwner(mutexName, out var mutex))
        {
            var collected = await CollectAsOwnerAsync(pipeName, command.Paths).ConfigureAwait(false);
            return ShellBatchSession.Owner(collected, mutex!);
        }

        if (await TrySendToOwnerAsync(pipeName, command.Paths).ConfigureAwait(false))
        {
            return ShellBatchSession.Forwarded();
        }

        if (TryBecomeOwner(mutexName, out mutex))
        {
            var collected = await CollectAsOwnerAsync(pipeName, command.Paths).ConfigureAwait(false);
            return ShellBatchSession.Owner(collected, mutex!);
        }

        return ShellBatchSession.Direct(command.Paths);
    }

    private static bool TryBecomeOwner(string mutexName, out Mutex? mutex)
    {
        mutex = new Mutex(false, mutexName);

        try
        {
            if (mutex.WaitOne(0))
            {
                return true;
            }
        }
        catch (AbandonedMutexException)
        {
            return true;
        }

        mutex.Dispose();
        mutex = null;
        return false;
    }

    private static async Task<IReadOnlyList<string>> CollectAsOwnerAsync(string pipeName, IReadOnlyList<string> initialPaths)
    {
        var collected = new HashSet<string>(initialPaths, StringComparer.OrdinalIgnoreCase);

        while (true)
        {
            using var server = new NamedPipeServerStream(
                pipeName,
                PipeDirection.In,
                1,
                PipeTransmissionMode.Byte,
                PipeOptions.Asynchronous);

            var waitTask = server.WaitForConnectionAsync();
            var completed = await Task.WhenAny(waitTask, Task.Delay(QuietPeriod)).ConfigureAwait(false);
            if (!ReferenceEquals(completed, waitTask))
            {
                break;
            }

            await waitTask.ConfigureAwait(false);
            using var reader = new StreamReader(server, Encoding.UTF8);
            var payload = await reader.ReadToEndAsync().ConfigureAwait(false);

            if (JsonSerializer.Deserialize<ShellBatchMessage>(payload) is { } message)
            {
                foreach (var path in message.Paths)
                {
                    collected.Add(path);
                }
            }
        }

        return collected.OrderBy(path => path, StringComparer.OrdinalIgnoreCase).ToArray();
    }

    private static async Task<bool> TrySendToOwnerAsync(string pipeName, IReadOnlyList<string> paths)
    {
        for (var attempt = 0; attempt < 8; attempt++)
        {
            try
            {
                using var client = new NamedPipeClientStream(".", pipeName, PipeDirection.Out, PipeOptions.Asynchronous);
                await client.ConnectAsync((int)ClientConnectTimeout.TotalMilliseconds).ConfigureAwait(false);
                await JsonSerializer.SerializeAsync(client, new ShellBatchMessage(paths)).ConfigureAwait(false);
                await client.FlushAsync().ConfigureAwait(false);
                return true;
            }
            catch (TimeoutException)
            {
                await Task.Delay(100).ConfigureAwait(false);
            }
            catch (IOException)
            {
                await Task.Delay(100).ConfigureAwait(false);
            }
        }

        return false;
    }

    private static string BuildChannel(ConvertCommand command)
    {
        var seed = string.Join('|',
            Environment.ProcessPath ?? "ImageConverter",
            ImageFormatInfo.ToCliToken(command.TargetFormat),
            command.OutputMode,
            command.FileExistsPolicy,
            command.RemoveOriginal,
            command.Quality);

        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(seed));
        return Convert.ToHexString(hash[..10]);
    }
}
