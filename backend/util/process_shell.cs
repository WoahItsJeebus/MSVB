using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text;

internal static class ProcessShell
{
    private const uint GenericAll = 0x10000000;
    private const uint CreateNewConsole = 0x00000010;
    private const uint CreateUnicodeEnvironment = 0x00000400;
    private const uint Infinite = 0xFFFFFFFF;
    private const uint StartfUseShowWindow = 0x00000001;
    private const uint StartfUseStdHandles = 0x00000100;
    private const short SwHide = 0;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct StartupInfo
    {
        public int cb;
        public string reserved;
        public string desktop;
        public string title;
        public int x;
        public int y;
        public int xSize;
        public int ySize;
        public int xCountChars;
        public int yCountChars;
        public int fillAttribute;
        public uint flags;
        public short showWindow;
        public short reserved2Size;
        public IntPtr reserved2;
        public IntPtr standardInput;
        public IntPtr standardOutput;
        public IntPtr standardError;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInformation
    {
        public IntPtr process;
        public IntPtr thread;
        public int processId;
        public int threadId;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateDesktop(
        string desktopName,
        IntPtr device,
        IntPtr deviceMode,
        uint flags,
        uint desiredAccess,
        IntPtr securityAttributes
    );

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseDesktop(IntPtr desktop);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CreateProcess(
        string applicationName,
        StringBuilder commandLine,
        IntPtr processAttributes,
        IntPtr threadAttributes,
        bool inheritHandles,
        uint creationFlags,
        IntPtr environment,
        string currentDirectory,
        ref StartupInfo startupInfo,
        out ProcessInformation processInformation
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(
        IntPtr handle,
        uint milliseconds
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetExitCodeProcess(
        IntPtr process,
        out uint exitCode
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    private static bool RequiresHiddenDesktop(string[] args)
    {
        for (var index = 0; index + 1 < args.Length; index += 1)
        {
            if (!string.Equals(
                args[index],
                "-RequestPath",
                StringComparison.OrdinalIgnoreCase
            ))
            {
                continue;
            }

            var requestPath = args[index + 1];
            if (!Path.IsPathRooted(requestPath) || !File.Exists(requestPath))
            {
                return false;
            }
            var fileInfo = new FileInfo(requestPath);
            if (fileInfo.Length <= 0 || fileInfo.Length > 65536)
            {
                return false;
            }
            var request = File.ReadAllText(requestPath);
            var compact = request
                .Replace(" ", "")
                .Replace("\t", "")
                .Replace("\r", "")
                .Replace("\n", "");
            return compact.IndexOf(
                "\"capture\":true",
                StringComparison.OrdinalIgnoreCase
            ) >= 0;
        }
        return false;
    }

    private static int RunOnHiddenDesktop(
        string executable,
        IList<string> arguments,
        string desktopName
    )
    {
        using (var stdoutPipe = new AnonymousPipeServerStream(
            PipeDirection.In,
            HandleInheritability.Inheritable
        ))
        using (var stderrPipe = new AnonymousPipeServerStream(
            PipeDirection.In,
            HandleInheritability.Inheritable
        ))
        {
            var stdoutHandle = new IntPtr(long.Parse(
                stdoutPipe.GetClientHandleAsString(),
                CultureInfo.InvariantCulture
            ));
            var stderrHandle = new IntPtr(long.Parse(
                stderrPipe.GetClientHandleAsString(),
                CultureInfo.InvariantCulture
            ));
            var commandLine = new StringBuilder();
            commandLine.Append(QuoteArgument(executable));
            foreach (var argument in arguments)
            {
                commandLine.Append(' ');
                commandLine.Append(QuoteArgument(argument));
            }

            var startup = new StartupInfo
            {
                cb = Marshal.SizeOf(typeof(StartupInfo)),
                desktop = desktopName,
                flags = StartfUseShowWindow + StartfUseStdHandles,
                showWindow = SwHide,
                standardInput = IntPtr.Zero,
                standardOutput = stdoutHandle,
                standardError = stderrHandle,
            };
            ProcessInformation processInformation;
            var created = CreateProcess(
                executable,
                commandLine,
                IntPtr.Zero,
                IntPtr.Zero,
                true,
                CreateNewConsole + CreateUnicodeEnvironment,
                IntPtr.Zero,
                null,
                ref startup,
                out processInformation
            );
            stdoutPipe.DisposeLocalCopyOfClientHandle();
            stderrPipe.DisposeLocalCopyOfClientHandle();
            if (!created)
            {
                return 1;
            }

            try
            {
                using (var stdoutReader = new StreamReader(
                    stdoutPipe,
                    new UTF8Encoding(false, true)
                ))
                using (var stderrReader = new StreamReader(
                    stderrPipe,
                    new UTF8Encoding(false, true)
                ))
                {
                    var stdoutTask = stdoutReader.ReadToEndAsync();
                    var stderrTask = stderrReader.ReadToEndAsync();
                    WaitForSingleObject(processInformation.process, Infinite);

                    var stdout = stdoutTask.GetAwaiter().GetResult();
                    var stderr = stderrTask.GetAwaiter().GetResult();
                    var stdoutBytes = Encoding.UTF8.GetBytes(stdout);
                    var stderrBytes = Encoding.UTF8.GetBytes(stderr);
                    using (var output = Console.OpenStandardOutput())
                    {
                        output.Write(stdoutBytes, 0, stdoutBytes.Length);
                        output.Flush();
                    }
                    using (var error = Console.OpenStandardError())
                    {
                        error.Write(stderrBytes, 0, stderrBytes.Length);
                        error.Flush();
                    }
                }

                uint exitCode;
                return GetExitCodeProcess(
                    processInformation.process,
                    out exitCode
                ) ? unchecked((int)exitCode) : 1;
            }
            finally
            {
                CloseHandle(processInformation.thread);
                CloseHandle(processInformation.process);
            }
        }
    }

    private static string QuoteArgument(string value)
    {
        if (value.Length == 0)
        {
            return "\"\"";
        }
        if (value.IndexOfAny(new[] { ' ', '\t', '"' }) < 0)
        {
            return value;
        }

        var output = new StringBuilder();
        output.Append('"');
        var backslashes = 0;
        foreach (var character in value)
        {
            if (character == '\\')
            {
                backslashes += 1;
            }
            else if (character == '"')
            {
                output.Append('\\', backslashes * 2 + 1);
                output.Append('"');
                backslashes = 0;
            }
            else
            {
                output.Append('\\', backslashes);
                backslashes = 0;
                output.Append(character);
            }
        }
        output.Append('\\', backslashes * 2);
        output.Append('"');
        return output.ToString();
    }

    private static int Main(string[] args)
    {
        var hiddenDesktop = IntPtr.Zero;
        try
        {
            var tracePath = Environment.GetEnvironmentVariable(
                "VLB_PROCESS_SHELL_TRACE"
            );
            if (!string.IsNullOrEmpty(tracePath))
            {
                File.WriteAllLines(tracePath, args);
            }

            var commandIndex = -1;
            for (var index = 0; index < args.Length; index += 1)
            {
                if (string.Equals(args[index], "/c", StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(args[index], "-c", StringComparison.OrdinalIgnoreCase))
                {
                    commandIndex = index + 1;
                    break;
                }
            }
            if (commandIndex < 0 || commandIndex >= args.Length)
            {
                return 87;
            }

            var executable = args[commandIndex];
            if (!Path.IsPathRooted(executable) || !File.Exists(executable))
            {
                return 2;
            }

            var useHiddenDesktop = RequiresHiddenDesktop(args);
            var desktopName = string.Empty;
            if (useHiddenDesktop)
            {
                desktopName =
                    "VortexLaunchBridge-" +
                    Process.GetCurrentProcess().Id.ToString() +
                    "-" +
                    Guid.NewGuid().ToString("N");
                hiddenDesktop = CreateDesktop(
                    desktopName,
                    IntPtr.Zero,
                    IntPtr.Zero,
                    0,
                    GenericAll,
                    IntPtr.Zero
                );
                if (hiddenDesktop == IntPtr.Zero)
                {
                    return 5;
                }
            }

            var arguments = new List<string>();
            for (var index = commandIndex + 1; index < args.Length; index += 1)
            {
                arguments.Add(args[index]);
            }

            if (useHiddenDesktop)
            {
                return RunOnHiddenDesktop(executable, arguments, desktopName);
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = executable,
                Arguments = string.Join(
                    " ",
                    arguments.ConvertAll(QuoteArgument)
                ),
                UseShellExecute = false,
                // The broker is a Windows-subsystem executable, and its
                // PowerShell runner is infrastructure rather than user-facing
                // UI. CREATE_NO_WINDOW prevents registry and process-state
                // requests from briefly allocating console windows on Steam's
                // desktop. Captured Vortex calls take the private-desktop path
                // above; interactive targets launched by the runner remain
                // independently visible.
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = new UTF8Encoding(false, true),
                StandardErrorEncoding = new UTF8Encoding(false, true),
            };
            using (var process = Process.Start(startInfo))
            {
                if (process == null)
                {
                    return 2;
                }
                var stdout = process.StandardOutput.ReadToEndAsync();
                var stderr = process.StandardError.ReadToEndAsync();
                process.WaitForExit();
                var stdoutBytes = Encoding.UTF8.GetBytes(stdout.GetAwaiter().GetResult());
                var stderrBytes = Encoding.UTF8.GetBytes(stderr.GetAwaiter().GetResult());
                using (var output = Console.OpenStandardOutput())
                {
                    output.Write(stdoutBytes, 0, stdoutBytes.Length);
                    output.Flush();
                }
                using (var error = Console.OpenStandardError())
                {
                    error.Write(stderrBytes, 0, stderrBytes.Length);
                    error.Flush();
                }
                return process.ExitCode;
            }
        }
        catch
        {
            return 1;
        }
        finally
        {
            if (hiddenDesktop != IntPtr.Zero)
            {
                CloseDesktop(hiddenDesktop);
            }
        }
    }
}
