using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

internal static class ProcessShell
{
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

            var arguments = new List<string>();
            for (var index = commandIndex + 1; index < args.Length; index += 1)
            {
                arguments.Add(QuoteArgument(args[index]));
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = executable,
                Arguments = string.Join(" ", arguments),
                UseShellExecute = false,
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
    }
}
