param(
	[Parameter(Mandatory = $true)]
	[string]$OutputPath,
	[int]$DurationSeconds = 180
)

$ErrorActionPreference = 'Stop'
$DurationSeconds = [Math]::Max(10, [Math]::Min(600, $DurationSeconds))
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutput
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
	New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
if (Test-Path -LiteralPath $resolvedOutput) {
	throw "Trace output already exists: $resolvedOutput"
}

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public sealed class VlbWindowSnapshot
{
    public long Handle;
    public int ProcessId;
    public string Title;
    public string ClassName;
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
    public int ShowCommand;
    public long Style;
    public long ExtendedStyle;
    public bool Cloaked;
}

public sealed class VlbProcessSnapshot
{
    public int ProcessId;
    public int ParentProcessId;
    public string ProcessName;
    public string CommandLine;
}

public static class VlbWindowEnumerator
{
    private const int GwlStyle = -16;
    private const int GwlExtendedStyle = -20;
    private const int DwmwaCloaked = 14;
    private const uint Th32csSnapProcess = 0x00000002;
    private const uint ProcessQueryLimitedInformation = 0x00001000;
    private const int ProcessCommandLineInformation = 60;

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WindowPlacement
    {
        public int Length;
        public int Flags;
        public int ShowCommand;
        public int MinX;
        public int MinY;
        public int MaxX;
        public int MaxY;
        public Rect NormalPosition;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct ProcessEntry
    {
        public uint Size;
        public uint Usage;
        public uint ProcessId;
        public IntPtr DefaultHeapId;
        public uint ModuleId;
        public uint Threads;
        public uint ParentProcessId;
        public int BasePriority;
        public uint Flags;

        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)]
        public string ExecutableFile;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct UnicodeString
    {
        public ushort Length;
        public ushort MaximumLength;
        public IntPtr Buffer;
    }

    private delegate bool EnumWindowsCallback(IntPtr window, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr window);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr window, out Rect rectangle);

    [DllImport("user32.dll")]
    private static extern bool GetWindowPlacement(IntPtr window, ref WindowPlacement placement);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr window, StringBuilder text, int maximum);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr window, StringBuilder text, int maximum);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr64(IntPtr window, int index);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong32(IntPtr window, int index);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(
        IntPtr window,
        int attribute,
        out int value,
        int valueSize
    );

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint processId);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool Process32First(IntPtr snapshot, ref ProcessEntry entry);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool Process32Next(IntPtr snapshot, ref ProcessEntry entry);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(
        uint desiredAccess,
        bool inheritHandle,
        uint processId
    );

    [DllImport("ntdll.dll")]
    private static extern int NtQueryInformationProcess(
        IntPtr process,
        int informationClass,
        IntPtr information,
        int informationLength,
        out int returnLength
    );

    private static long GetWindowLong(IntPtr window, int index)
    {
        return IntPtr.Size == 8
            ? GetWindowLongPtr64(window, index).ToInt64()
            : GetWindowLong32(window, index);
    }

    private static string GetCommandLine(uint processId, string processName)
    {
        switch ((processName ?? string.Empty).ToLowerInvariant())
        {
            case "cmd.exe":
            case "powershell.exe":
            case "pwsh.exe":
            case "dotnetprobe.exe":
            case "process_shell.exe":
            case "vortex.exe":
                break;
            default:
                return null;
        }

        var process = OpenProcess(
            ProcessQueryLimitedInformation,
            false,
            processId
        );
        if (process == IntPtr.Zero)
        {
            return null;
        }

        try
        {
            int required;
            NtQueryInformationProcess(
                process,
                ProcessCommandLineInformation,
                IntPtr.Zero,
                0,
                out required
            );
            if (required <= Marshal.SizeOf(typeof(UnicodeString)) ||
                required > 32768)
            {
                return null;
            }

            var buffer = Marshal.AllocHGlobal(required);
            try
            {
                if (NtQueryInformationProcess(
                    process,
                    ProcessCommandLineInformation,
                    buffer,
                    required,
                    out required
                ) != 0)
                {
                    return null;
                }
                var commandLine = (UnicodeString)Marshal.PtrToStructure(
                    buffer,
                    typeof(UnicodeString)
                );
                return commandLine.Buffer == IntPtr.Zero
                    ? null
                    : Marshal.PtrToStringUni(
                        commandLine.Buffer,
                        commandLine.Length / 2
                    );
            }
            finally
            {
                Marshal.FreeHGlobal(buffer);
            }
        }
        finally
        {
            CloseHandle(process);
        }
    }

    public static VlbWindowSnapshot[] CaptureVisible()
    {
        var snapshots = new List<VlbWindowSnapshot>();
        EnumWindows(delegate(IntPtr window, IntPtr parameter)
        {
            if (!IsWindowVisible(window))
            {
                return true;
            }

            uint processId;
            GetWindowThreadProcessId(window, out processId);
            Rect rectangle;
            GetWindowRect(window, out rectangle);
            var placement = new WindowPlacement();
            placement.Length = Marshal.SizeOf(typeof(WindowPlacement));
            GetWindowPlacement(window, ref placement);
            var title = new StringBuilder(1024);
            GetWindowText(window, title, title.Capacity);
            var className = new StringBuilder(512);
            GetClassName(window, className, className.Capacity);
            int cloaked;
            var cloakedOk = DwmGetWindowAttribute(
                window,
                DwmwaCloaked,
                out cloaked,
                sizeof(int)
            ) == 0;

            snapshots.Add(new VlbWindowSnapshot
            {
                Handle = window.ToInt64(),
                ProcessId = unchecked((int)processId),
                Title = title.ToString(),
                ClassName = className.ToString(),
                Left = rectangle.Left,
                Top = rectangle.Top,
                Right = rectangle.Right,
                Bottom = rectangle.Bottom,
                ShowCommand = placement.ShowCommand,
                Style = GetWindowLong(window, GwlStyle),
                ExtendedStyle = GetWindowLong(window, GwlExtendedStyle),
                Cloaked = cloakedOk && cloaked != 0,
            });
            return true;
        }, IntPtr.Zero);
        return snapshots.ToArray();
    }

    public static VlbProcessSnapshot[] CaptureProcesses()
    {
        var processes = new List<VlbProcessSnapshot>();
        var snapshot = CreateToolhelp32Snapshot(Th32csSnapProcess, 0);
        if (snapshot == IntPtr.Zero || snapshot.ToInt64() == -1)
        {
            return processes.ToArray();
        }

        try
        {
            var entry = new ProcessEntry();
            entry.Size = (uint)Marshal.SizeOf(typeof(ProcessEntry));
            if (!Process32First(snapshot, ref entry))
            {
                return processes.ToArray();
            }
            do
            {
                processes.Add(new VlbProcessSnapshot
                {
                    ProcessId = unchecked((int)entry.ProcessId),
                    ParentProcessId = unchecked((int)entry.ParentProcessId),
                    ProcessName = entry.ExecutableFile ?? string.Empty,
                    CommandLine = GetCommandLine(
                        entry.ProcessId,
                        entry.ExecutableFile
                    ),
                });
                entry.Size = (uint)Marshal.SizeOf(typeof(ProcessEntry));
            }
            while (Process32Next(snapshot, ref entry));
            return processes.ToArray();
        }
        finally
        {
            CloseHandle(snapshot);
        }
    }
}
'@

function Get-ProcessName {
	param([int]$ProcessId)
	try {
		return [System.Diagnostics.Process]::GetProcessById($ProcessId).ProcessName
	}
	catch {
		return $null
	}
}

function Get-WindowRecord {
	param(
		[VlbWindowSnapshot]$Window,
		[string]$Event,
		[long]$ElapsedMilliseconds,
		[long]$ForegroundHandle
	)
	return [ordered]@{
		timestamp = [DateTime]::UtcNow.ToString('o')
		elapsedMs = $ElapsedMilliseconds
		event = $Event
		handle = ('0x{0:X}' -f $Window.Handle)
		processId = $Window.ProcessId
		processName = Get-ProcessName $Window.ProcessId
		title = $Window.Title
		className = $Window.ClassName
		left = $Window.Left
		top = $Window.Top
		right = $Window.Right
		bottom = $Window.Bottom
		width = $Window.Right - $Window.Left
		height = $Window.Bottom - $Window.Top
		showCommand = $Window.ShowCommand
		style = ('0x{0:X}' -f $Window.Style)
		extendedStyle = ('0x{0:X}' -f $Window.ExtendedStyle)
		cloaked = $Window.Cloaked
		foreground = $Window.Handle -eq $ForegroundHandle
	}
}

$writer = New-Object System.IO.StreamWriter(
	$resolvedOutput,
	$false,
	(New-Object System.Text.UTF8Encoding($false))
)
$writer.AutoFlush = $true
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$knownWindows = @{}
$visibleWindows = @{}
$knownProcesses = @{}
$lastForeground = 0L

try {
	$writer.WriteLine((ConvertTo-Json -Compress -InputObject ([ordered]@{
		timestamp = [DateTime]::UtcNow.ToString('o')
		elapsedMs = 0
		event = 'trace_started'
		durationSeconds = $DurationSeconds
		processId = $PID
	})))

	foreach ($window in [VlbWindowEnumerator]::CaptureVisible()) {
		$knownWindows[$window.Handle] = $true
		$visibleWindows[$window.Handle] = $true
	}
	foreach ($process in [VlbWindowEnumerator]::CaptureProcesses()) {
		$knownProcesses[$process.ProcessId] = $true
	}

	while ($stopwatch.Elapsed.TotalSeconds -lt $DurationSeconds) {
		foreach ($process in [VlbWindowEnumerator]::CaptureProcesses()) {
			if (-not $knownProcesses.ContainsKey($process.ProcessId)) {
				$knownProcesses[$process.ProcessId] = $true
				$writer.WriteLine((ConvertTo-Json -Compress -InputObject ([ordered]@{
					timestamp = [DateTime]::UtcNow.ToString('o')
					elapsedMs = $stopwatch.ElapsedMilliseconds
					event = 'process_started'
					processId = $process.ProcessId
					parentProcessId = $process.ParentProcessId
					processName = $process.ProcessName
					commandLine = $process.CommandLine
				})))
			}
		}

		$foreground = [VlbWindowEnumerator]::GetForegroundWindow().ToInt64()
		$currentVisible = @{}
		foreach ($window in [VlbWindowEnumerator]::CaptureVisible()) {
			$currentVisible[$window.Handle] = $true
			if (-not $knownWindows.ContainsKey($window.Handle)) {
				$knownWindows[$window.Handle] = $true
				$record = Get-WindowRecord `
					-Window $window `
					-Event 'window_became_visible' `
					-ElapsedMilliseconds $stopwatch.ElapsedMilliseconds `
					-ForegroundHandle $foreground
				$writer.WriteLine((ConvertTo-Json -Compress -InputObject $record))
			}
		}

		foreach ($handle in @($visibleWindows.Keys)) {
			if (-not $currentVisible.ContainsKey($handle)) {
				$writer.WriteLine((ConvertTo-Json -Compress -InputObject ([ordered]@{
					timestamp = [DateTime]::UtcNow.ToString('o')
					elapsedMs = $stopwatch.ElapsedMilliseconds
					event = 'window_became_hidden_or_closed'
					handle = ('0x{0:X}' -f $handle)
				})))
			}
		}
		$visibleWindows = $currentVisible

		if ($foreground -ne 0 -and $foreground -ne $lastForeground) {
			$foregroundWindow = [VlbWindowEnumerator]::CaptureVisible() |
				Where-Object { $_.Handle -eq $foreground } |
				Select-Object -First 1
			if ($null -ne $foregroundWindow) {
				$record = Get-WindowRecord `
					-Window $foregroundWindow `
					-Event 'foreground_changed' `
					-ElapsedMilliseconds $stopwatch.ElapsedMilliseconds `
					-ForegroundHandle $foreground
				$writer.WriteLine((ConvertTo-Json -Compress -InputObject $record))
			}
			$lastForeground = $foreground
		}

		Start-Sleep -Milliseconds 5
	}
}
finally {
	$stopwatch.Stop()
	$writer.WriteLine((ConvertTo-Json -Compress -InputObject ([ordered]@{
		timestamp = [DateTime]::UtcNow.ToString('o')
		elapsedMs = $stopwatch.ElapsedMilliseconds
		event = 'trace_stopped'
	})))
	$writer.Dispose()
}
