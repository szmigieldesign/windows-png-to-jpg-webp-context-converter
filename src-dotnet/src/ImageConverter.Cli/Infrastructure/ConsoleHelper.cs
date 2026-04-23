using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace ImageConverter.Cli.Infrastructure;

internal static class ConsoleHelper
{
    private const int AttachParentProcess = -1;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AttachConsole(int dwProcessId);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetStdHandle(int nStdHandle);

    public static void Initialize()
    {
        if (!AttachConsole(AttachParentProcess))
        {
            return;
        }

        Console.SetOut(CreateWriter(-11, Console.Out));
        Console.SetError(CreateWriter(-12, Console.Error));
    }

    private static TextWriter CreateWriter(int handleId, TextWriter fallback)
    {
        try
        {
            var handle = GetStdHandle(handleId);
            if (handle == IntPtr.Zero || handle == new IntPtr(-1))
            {
                return fallback;
            }

            var stream = new FileStream(new SafeFileHandle(handle, ownsHandle: false), FileAccess.Write);
            return new StreamWriter(stream) { AutoFlush = true };
        }
        catch
        {
            return fallback;
        }
    }
}
