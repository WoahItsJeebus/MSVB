using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

internal static class ProcessShell
{
    private const uint GenericAll = 0x10000000;
    private const uint CreateNewConsole = 0x00000010;
    private const uint DetachedProcess = 0x00000008;
    private const uint CreateSuspended = 0x00000004;
    private const uint CreateUnicodeEnvironment = 0x00000400;
    private const uint CreateNoWindow = 0x08000000;
    private const uint Infinite = 0xFFFFFFFF;
    private const uint WaitObject0 = 0x00000000;
    private const uint EventModifyState = 0x0002;
    private const uint Th32csSnapProcess = 0x00000002;
    private const uint EventSystemForeground = 0x0003;
    private const uint EventObjectCreate = 0x8000;
    private const uint EventObjectShow = 0x8002;
    private const uint WineventOutOfContext = 0x0000;
    private const uint WineventSkipOwnProcess = 0x0002;
    private const uint PmRemove = 0x0001;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoZOrder = 0x0004;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpHideWindow = 0x0080;
    private const int ObjidWindow = 0;
    private const uint StartfUseShowWindow = 0x00000001;
    private const uint StartfUseStdHandles = 0x00000100;
    private const short SwHide = 0;
    private const int VortexConsoleGuardMilliseconds = 30000;

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

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct ProcessEntry
    {
        public uint size;
        public uint usage;
        public uint processId;
        public IntPtr defaultHeapId;
        public uint moduleId;
        public uint threads;
        public uint parentProcessId;
        public int basePriority;
        public uint flags;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string executableFile;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Message
    {
        public IntPtr window;
        public uint message;
        public UIntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public Point point;
        public uint privateValue;
    }

    private sealed class ProcessTreeEntry
    {
        public int ParentProcessId;
        public string ExecutableFile;
    }

    private delegate bool EnumWindowsCallback(IntPtr window, IntPtr parameter);
    private delegate void WinEventCallback(
        IntPtr hook,
        uint eventType,
        IntPtr window,
        int objectId,
        int childId,
        uint eventThread,
        uint eventTime
    );

    private static int guardedRootProcessId;
    private static IntPtr guardedPreviousForegroundWindow;
    private static WinEventCallback guardedWinEventCallback;

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

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateEvent(
        IntPtr eventAttributes,
        bool manualReset,
        bool initialState,
        string name
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenEvent(
        uint desiredAccess,
        bool inheritHandle,
        string name
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetEvent(IntPtr handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint ResumeThread(IntPtr thread);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool TerminateProcess(IntPtr process, uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateToolhelp32Snapshot(
        uint flags,
        uint processId
    );

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool Process32First(
        IntPtr snapshot,
        ref ProcessEntry entry
    );

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool Process32Next(
        IntPtr snapshot,
        ref ProcessEntry entry
    );

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(
        EnumWindowsCallback callback,
        IntPtr parameter
    );

    [DllImport("user32.dll")]
    private static extern bool GetWindowThreadProcessId(
        IntPtr window,
        out uint processId
    );

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(
        IntPtr window,
        StringBuilder className,
        int maximum
    );

    [DllImport("user32.dll")]
    private static extern bool ShowWindowAsync(IntPtr window, int command);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(
        IntPtr window,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags
    );

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern bool IsWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern IntPtr SetWinEventHook(
        uint eventMinimum,
        uint eventMaximum,
        IntPtr eventHookModule,
        WinEventCallback callback,
        uint processId,
        uint threadId,
        uint flags
    );

    [DllImport("user32.dll")]
    private static extern bool UnhookWinEvent(IntPtr hook);

    [DllImport("user32.dll")]
    private static extern bool PeekMessage(
        out Message message,
        IntPtr window,
        uint filterMinimum,
        uint filterMaximum,
        uint removeMessage
    );

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage(ref Message message);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref Message message);

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

    private static int RunNative(
        string executable,
        IList<string> arguments,
        string desktopName,
        uint creationFlags
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
                creationFlags,
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

    private static int RunOnHiddenDesktop(
        string executable,
        IList<string> arguments,
        string desktopName
    )
    {
        return RunNative(
            executable,
            arguments,
            desktopName,
            CreateNewConsole + CreateUnicodeEnvironment
        );
    }

    private static int RunWithoutConsole(
        string executable,
        IList<string> arguments
    )
    {
        return RunNative(
            executable,
            arguments,
            null,
            CreateNoWindow + CreateUnicodeEnvironment
        );
    }

    private static Dictionary<int, ProcessTreeEntry> CaptureProcessTree()
    {
        var processes = new Dictionary<int, ProcessTreeEntry>();
        var snapshot = CreateToolhelp32Snapshot(Th32csSnapProcess, 0);
        if (snapshot == IntPtr.Zero || snapshot.ToInt64() == -1)
        {
            return processes;
        }

        try
        {
            var entry = new ProcessEntry();
            entry.size = (uint)Marshal.SizeOf(typeof(ProcessEntry));
            if (!Process32First(snapshot, ref entry))
            {
                return processes;
            }

            do
            {
                processes[unchecked((int)entry.processId)] =
                    new ProcessTreeEntry
                    {
                        ParentProcessId =
                            unchecked((int)entry.parentProcessId),
                        ExecutableFile = entry.executableFile ?? string.Empty,
                    };
                entry.size = (uint)Marshal.SizeOf(typeof(ProcessEntry));
            }
            while (Process32Next(snapshot, ref entry));
        }
        finally
        {
            CloseHandle(snapshot);
        }

        return processes;
    }

    private static bool IsDescendantProcess(
        int processId,
        int rootProcessId,
        IDictionary<int, ProcessTreeEntry> processes
    )
    {
        var current = processId;
        var visited = new HashSet<int>();
        for (var depth = 0; depth < 64; depth += 1)
        {
            if (current == rootProcessId)
            {
                return true;
            }
            if (current <= 0 || !visited.Add(current))
            {
                return false;
            }

            ProcessTreeEntry entry;
            if (!processes.TryGetValue(current, out entry))
            {
                return false;
            }
            current = entry.ParentProcessId;
        }
        return false;
    }

    private static bool IsConsoleProcess(string executableFile)
    {
        return string.Equals(
                executableFile,
                "conhost.exe",
                StringComparison.OrdinalIgnoreCase
            ) ||
            string.Equals(
                executableFile,
                "OpenConsole.exe",
                StringComparison.OrdinalIgnoreCase
            ) ||
            string.Equals(
                executableFile,
                "cmd.exe",
                StringComparison.OrdinalIgnoreCase
            ) ||
            string.Equals(
                executableFile,
                "powershell.exe",
                StringComparison.OrdinalIgnoreCase
            ) ||
            string.Equals(
                executableFile,
                "pwsh.exe",
                StringComparison.OrdinalIgnoreCase
            ) ||
            string.Equals(
                executableFile,
                "dotnetprobe.exe",
                StringComparison.OrdinalIgnoreCase
            );
    }

    private static void HideDescendantConsoleWindow(
        IntPtr window,
        IDictionary<int, ProcessTreeEntry> processes
    )
    {
        if (window == IntPtr.Zero || guardedRootProcessId <= 0)
        {
            return;
        }

        uint rawProcessId;
        GetWindowThreadProcessId(window, out rawProcessId);
        var processId = unchecked((int)rawProcessId);
        if (!IsDescendantProcess(
            processId,
            guardedRootProcessId,
            processes
        ))
        {
            return;
        }

        ProcessTreeEntry process;
        processes.TryGetValue(processId, out process);
        var className = new StringBuilder(256);
        GetClassName(window, className, className.Capacity);
        var classValue = className.ToString();
        var isConsoleClass = string.Equals(
                classValue,
                "ConsoleWindowClass",
                StringComparison.OrdinalIgnoreCase
            ) ||
            string.Equals(
                classValue,
                "CASCADIA_HOSTING_WINDOW_CLASS",
                StringComparison.OrdinalIgnoreCase
            );
        if (!isConsoleClass &&
            (process == null || !IsConsoleProcess(process.ExecutableFile)))
        {
            return;
        }

        var wasForeground = GetForegroundWindow() == window;
        ShowWindowAsync(window, SwHide);
        SetWindowPos(
            window,
            IntPtr.Zero,
            0,
            0,
            0,
            0,
            SwpNoSize + SwpNoMove + SwpNoZOrder +
                SwpNoActivate + SwpHideWindow
        );
        if (wasForeground &&
            guardedPreviousForegroundWindow != IntPtr.Zero &&
            guardedPreviousForegroundWindow != window &&
            IsWindow(guardedPreviousForegroundWindow))
        {
            SetForegroundWindow(guardedPreviousForegroundWindow);
        }
    }

    private static void HideAllDescendantConsoleWindows()
    {
        var processes = CaptureProcessTree();
        EnumWindows(delegate(IntPtr window, IntPtr parameter)
        {
            HideDescendantConsoleWindow(window, processes);
            return true;
        }, IntPtr.Zero);
    }

    private static void HandleGuardedWindowEvent(
        IntPtr hook,
        uint eventType,
        IntPtr window,
        int objectId,
        int childId,
        uint eventThread,
        uint eventTime
    )
    {
        if (window == IntPtr.Zero ||
            (eventType != EventSystemForeground &&
                objectId != ObjidWindow))
        {
            return;
        }
        HideDescendantConsoleWindow(window, CaptureProcessTree());
    }

    private static bool IsProcessAlive(int processId)
    {
        try
        {
            using (var process = Process.GetProcessById(processId))
            {
                return !process.HasExited;
            }
        }
        catch
        {
            return false;
        }
    }

    private static int RunConsoleWindowGuard(
        int rootProcessId,
        string readyEventName,
        int durationMilliseconds
    )
    {
        if (rootProcessId <= 0 ||
            durationMilliseconds < 5000 ||
            durationMilliseconds > 60000 ||
            string.IsNullOrEmpty(readyEventName) ||
            readyEventName.Length > 240 ||
            !readyEventName.StartsWith(
                @"Local\VortexLaunchBridge-ConsoleGuard-",
                StringComparison.Ordinal
            ))
        {
            return 87;
        }

        var readyEvent = OpenEvent(
            EventModifyState,
            false,
            readyEventName
        );
        if (readyEvent == IntPtr.Zero)
        {
            return 2;
        }

        var objectHook = IntPtr.Zero;
        var foregroundHook = IntPtr.Zero;
        try
        {
            guardedRootProcessId = rootProcessId;
            guardedPreviousForegroundWindow = GetForegroundWindow();
            guardedWinEventCallback = HandleGuardedWindowEvent;
            objectHook = SetWinEventHook(
                EventObjectCreate,
                EventObjectShow,
                IntPtr.Zero,
                guardedWinEventCallback,
                0,
                0,
                WineventOutOfContext + WineventSkipOwnProcess
            );
            foregroundHook = SetWinEventHook(
                EventSystemForeground,
                EventSystemForeground,
                IntPtr.Zero,
                guardedWinEventCallback,
                0,
                0,
                WineventOutOfContext + WineventSkipOwnProcess
            );
            if (objectHook == IntPtr.Zero || foregroundHook == IntPtr.Zero)
            {
                return 5;
            }

            HideAllDescendantConsoleWindows();
            if (!SetEvent(readyEvent))
            {
                return 5;
            }

            var stopwatch = Stopwatch.StartNew();
            var nextFallbackScan = 0L;
            while (stopwatch.ElapsedMilliseconds < durationMilliseconds &&
                IsProcessAlive(rootProcessId))
            {
                Message message;
                while (PeekMessage(
                    out message,
                    IntPtr.Zero,
                    0,
                    0,
                    PmRemove
                ))
                {
                    TranslateMessage(ref message);
                    DispatchMessage(ref message);
                }

                if (stopwatch.ElapsedMilliseconds >= nextFallbackScan)
                {
                    HideAllDescendantConsoleWindows();
                    nextFallbackScan = stopwatch.ElapsedMilliseconds +
                        (stopwatch.ElapsedMilliseconds < 10000 ? 5 : 25);
                }
                Thread.Sleep(1);
            }
            return 0;
        }
        finally
        {
            if (foregroundHook != IntPtr.Zero)
            {
                UnhookWinEvent(foregroundHook);
            }
            if (objectHook != IntPtr.Zero)
            {
                UnhookWinEvent(objectHook);
            }
            CloseHandle(readyEvent);
            GC.KeepAlive(guardedWinEventCallback);
        }
    }

    private static bool StartConsoleWindowGuard(
        int rootProcessId,
        string readyEventName,
        out ProcessInformation processInformation
    )
    {
        processInformation = new ProcessInformation();
        var currentExecutable = Process.GetCurrentProcess().MainModule.FileName;
        if (string.IsNullOrEmpty(currentExecutable) ||
            !Path.IsPathRooted(currentExecutable) ||
            !File.Exists(currentExecutable))
        {
            return false;
        }

        var commandLine = new StringBuilder();
        commandLine.Append(QuoteArgument(currentExecutable));
        commandLine.Append(" /c --vlb-console-window-guard ");
        commandLine.Append(
            rootProcessId.ToString(CultureInfo.InvariantCulture)
        );
        commandLine.Append(' ');
        commandLine.Append(QuoteArgument(readyEventName));
        commandLine.Append(' ');
        commandLine.Append(
            VortexConsoleGuardMilliseconds.ToString(
                CultureInfo.InvariantCulture
            )
        );

        var startup = new StartupInfo
        {
            cb = Marshal.SizeOf(typeof(StartupInfo)),
            desktop = @"winsta0\default",
            flags = StartfUseShowWindow,
            showWindow = SwHide,
        };
        return CreateProcess(
            currentExecutable,
            commandLine,
            IntPtr.Zero,
            IntPtr.Zero,
            false,
            DetachedProcess + CreateUnicodeEnvironment,
            IntPtr.Zero,
            null,
            ref startup,
            out processInformation
        );
    }

    private static int RunGuardedDetachedVortex(
        string executable,
        IList<string> arguments
    )
    {
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
            desktop = @"winsta0\default",
            flags = StartfUseShowWindow,
            showWindow = SwHide,
        };
        ProcessInformation vortexProcess;
        var stopwatch = Stopwatch.StartNew();
        var created = CreateProcess(
            executable,
            commandLine,
            IntPtr.Zero,
            IntPtr.Zero,
            false,
            DetachedProcess + CreateSuspended + CreateUnicodeEnvironment,
            IntPtr.Zero,
            null,
            ref startup,
            out vortexProcess
        );
        if (!created)
        {
            var errorCode = Marshal.GetLastWin32Error();
            WriteStandardOutput(
                "{\"started\":false,\"errorCode\":" +
                errorCode.ToString(CultureInfo.InvariantCulture) +
                ",\"error\":\"CreateProcessW failed with Windows error " +
                errorCode.ToString(CultureInfo.InvariantCulture) +
                "\"}"
            );
            return 1;
        }

        var readyEvent = IntPtr.Zero;
        var guardProcess = new ProcessInformation();
        try
        {
            var readyEventName =
                @"Local\VortexLaunchBridge-ConsoleGuard-" +
                vortexProcess.processId.ToString(CultureInfo.InvariantCulture) +
                "-" + Guid.NewGuid().ToString("N");
            readyEvent = CreateEvent(
                IntPtr.Zero,
                true,
                false,
                readyEventName
            );
            var guardStarted = readyEvent != IntPtr.Zero &&
                StartConsoleWindowGuard(
                    vortexProcess.processId,
                    readyEventName,
                    out guardProcess
                );
            var guardReady = guardStarted &&
                WaitForSingleObject(readyEvent, 2000) == WaitObject0;
            if (!guardReady || ResumeThread(vortexProcess.thread) == uint.MaxValue)
            {
                TerminateProcess(vortexProcess.process, 1);
                if (guardProcess.process != IntPtr.Zero)
                {
                    TerminateProcess(guardProcess.process, 1);
                }
                WriteStandardOutput(
                    "{\"started\":false," +
                    "\"error\":\"The Vortex console-window guard could not start.\"}"
                );
                return 1;
            }

            stopwatch.Stop();
            WriteStandardOutput(
                "{\"started\":true,\"processId\":" +
                vortexProcess.processId.ToString(CultureInfo.InvariantCulture) +
                ",\"durationMs\":" +
                stopwatch.ElapsedMilliseconds.ToString(
                    CultureInfo.InvariantCulture
                ) +
                ",\"consoleWindowGuarded\":true}"
            );
            return 0;
        }
        finally
        {
            if (guardProcess.thread != IntPtr.Zero)
            {
                CloseHandle(guardProcess.thread);
            }
            if (guardProcess.process != IntPtr.Zero)
            {
                CloseHandle(guardProcess.process);
            }
            if (readyEvent != IntPtr.Zero)
            {
                CloseHandle(readyEvent);
            }
            CloseHandle(vortexProcess.thread);
            CloseHandle(vortexProcess.process);
        }
    }

    private static int RunDetached(
        string executable,
        IList<string> arguments,
        bool createHiddenConsole
    )
    {
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
            desktop = @"winsta0\default",
            flags = StartfUseShowWindow,
            showWindow = SwHide,
        };
        ProcessInformation processInformation;
        var stopwatch = Stopwatch.StartNew();
        var created = CreateProcess(
            executable,
            commandLine,
            IntPtr.Zero,
            IntPtr.Zero,
            false,
            (createHiddenConsole ? CreateNewConsole : DetachedProcess) +
                CreateUnicodeEnvironment,
            IntPtr.Zero,
            null,
            ref startup,
            out processInformation
        );
        stopwatch.Stop();

        if (!created)
        {
            var errorCode = Marshal.GetLastWin32Error();
            WriteStandardOutput(
                "{\"started\":false,\"errorCode\":" +
                errorCode.ToString(CultureInfo.InvariantCulture) +
                ",\"error\":\"CreateProcessW failed with Windows error " +
                errorCode.ToString(CultureInfo.InvariantCulture) +
                "\"}"
            );
            return 1;
        }

        try
        {
            WriteStandardOutput(
                "{\"started\":true,\"processId\":" +
                processInformation.processId.ToString(CultureInfo.InvariantCulture) +
                ",\"durationMs\":" +
                stopwatch.ElapsedMilliseconds.ToString(CultureInfo.InvariantCulture) +
                "}"
            );
            return 0;
        }
        finally
        {
            CloseHandle(processInformation.thread);
            CloseHandle(processInformation.process);
        }
    }

    private static void NormalizeChildEnvironment()
    {
        var systemDirectory = Environment.GetFolderPath(
            Environment.SpecialFolder.System
        );
        if (string.IsNullOrEmpty(systemDirectory))
        {
            return;
        }

        var commandProcessor = Path.Combine(systemDirectory, "cmd.exe");
        if (File.Exists(commandProcessor))
        {
            // Lua temporarily selects this executable as ComSpec so io.popen
            // reaches a Windows-subsystem broker. No child should inherit that
            // infrastructure override as its own command processor.
            Environment.SetEnvironmentVariable("ComSpec", commandProcessor);
        }
    }

    private static void WriteStandardOutput(string value)
    {
        var bytes = Encoding.UTF8.GetBytes(value);
        using (var output = Console.OpenStandardOutput())
        {
            output.Write(bytes, 0, bytes.Length);
            output.Flush();
        }
    }

    private static int RunIsProcessRunning(string executableName)
    {
        if (!string.Equals(
            Path.GetFileName(executableName),
            executableName,
            StringComparison.Ordinal
        ) || !string.Equals(
            Path.GetExtension(executableName),
            ".exe",
            StringComparison.OrdinalIgnoreCase
        ))
        {
            return 87;
        }

        var processName = Path.GetFileNameWithoutExtension(executableName);
        var processes = Process.GetProcessesByName(processName);
        try
        {
            WriteStandardOutput(
                "{\"ok\":true,\"running\":" +
                (processes.Length > 0 ? "true" : "false") +
                "}"
            );
            return 0;
        }
        finally
        {
            foreach (var process in processes)
            {
                process.Dispose();
            }
        }
    }

    private static bool IsVortexRunning()
    {
        var processes = Process.GetProcessesByName("Vortex");
        try
        {
            return processes.Length > 0;
        }
        finally
        {
            foreach (var process in processes)
            {
                process.Dispose();
            }
        }
    }

    private static bool TerminateVortexProcesses(
        HashSet<int> terminatedProcessIds
    )
    {
        var processes = Process.GetProcessesByName("Vortex");
        try
        {
            foreach (var process in processes)
            {
                try
                {
                    if (!process.HasExited)
                    {
                        var processId = process.Id;
                        process.Kill();
                        terminatedProcessIds.Add(processId);
                    }
                }
                catch (InvalidOperationException)
                {
                    // The process exited between enumeration and termination.
                }
                catch
                {
                    // The bounded verification below determines whether retrying
                    // is safe even if one process handle could not be terminated.
                }
            }
        }
        finally
        {
            foreach (var process in processes)
            {
                process.Dispose();
            }
        }

        return processes.Length > 0;
    }

    private static int RunTerminateVortex()
    {
        var found = false;
        var terminatedProcessIds = new HashSet<int>();

        var stopwatch = Stopwatch.StartNew();
        var running = true;
        while (running)
        {
            found = TerminateVortexProcesses(terminatedProcessIds) || found;
            running = IsVortexRunning();
            if (!running || stopwatch.ElapsedMilliseconds >= 2500)
            {
                break;
            }
            Thread.Sleep(50);
        }

        var ok = !running;
        WriteStandardOutput(
            "{\"ok\":" + (ok ? "true" : "false") +
            ",\"found\":" + (found ? "true" : "false") +
            ",\"terminatedCount\":" +
            terminatedProcessIds.Count.ToString(CultureInfo.InvariantCulture) +
            ",\"running\":" + (running ? "true" : "false") +
            (ok
                ? "}"
                : ",\"error\":\"Vortex did not exit after it was force-closed.\"}")
        );
        return ok ? 0 : 1;
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
            NormalizeChildEnvironment();

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

            var detachWithoutConsole = string.Equals(
                args[commandIndex],
                "--vlb-detach",
                StringComparison.OrdinalIgnoreCase
            );
            var detachWithHiddenConsole = string.Equals(
                args[commandIndex],
                "--vlb-detach-hidden-console",
                StringComparison.OrdinalIgnoreCase
            );
            var detachWithConsoleGuard = string.Equals(
                args[commandIndex],
                "--vlb-detach-vortex-guarded",
                StringComparison.OrdinalIgnoreCase
            );
            if (detachWithoutConsole || detachWithHiddenConsole ||
                detachWithConsoleGuard)
            {
                if (commandIndex + 1 >= args.Length)
                {
                    return 87;
                }

                var detachedExecutable = args[commandIndex + 1];
                if (!Path.IsPathRooted(detachedExecutable) ||
                    !File.Exists(detachedExecutable))
                {
                    return 2;
                }

                var detachedArguments = new List<string>();
                for (var index = commandIndex + 2; index < args.Length; index += 1)
                {
                    detachedArguments.Add(args[index]);
                }
                if (detachWithConsoleGuard)
                {
                    if (!string.Equals(
                        Path.GetFileName(detachedExecutable),
                        "Vortex.exe",
                        StringComparison.OrdinalIgnoreCase
                    ))
                    {
                        return 87;
                    }
                    return RunGuardedDetachedVortex(
                        detachedExecutable,
                        detachedArguments
                    );
                }
                return RunDetached(
                    detachedExecutable,
                    detachedArguments,
                    detachWithHiddenConsole
                );
            }

            if (string.Equals(
                args[commandIndex],
                "--vlb-console-window-guard",
                StringComparison.OrdinalIgnoreCase
            ))
            {
                int rootProcessId;
                int durationMilliseconds;
                if (commandIndex + 4 != args.Length ||
                    !int.TryParse(
                        args[commandIndex + 1],
                        NumberStyles.None,
                        CultureInfo.InvariantCulture,
                        out rootProcessId
                    ) ||
                    !int.TryParse(
                        args[commandIndex + 3],
                        NumberStyles.None,
                        CultureInfo.InvariantCulture,
                        out durationMilliseconds
                    ))
                {
                    return 87;
                }
                return RunConsoleWindowGuard(
                    rootProcessId,
                    args[commandIndex + 2],
                    durationMilliseconds
                );
            }

            if (string.Equals(
                args[commandIndex],
                "--vlb-is-running",
                StringComparison.OrdinalIgnoreCase
            ))
            {
                if (commandIndex + 2 != args.Length)
                {
                    return 87;
                }
                return RunIsProcessRunning(args[commandIndex + 1]);
            }

            if (string.Equals(
                args[commandIndex],
                "--vlb-terminate-vortex",
                StringComparison.OrdinalIgnoreCase
            ))
            {
                if (commandIndex + 1 != args.Length)
                {
                    return 87;
                }
                return RunTerminateVortex();
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

            // Invoke the infrastructure runner with Win32 directly. The
            // ProcessStartInfo convenience path can still allocate conhost.exe
            // before its hidden window state takes effect. CREATE_NO_WINDOW
            // prevents the console host from being created in the first place.
            return RunWithoutConsole(executable, arguments);
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
