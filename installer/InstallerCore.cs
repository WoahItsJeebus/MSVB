using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using Microsoft.Win32;

namespace VortexLaunchBridge.Installer
{
    internal static class InstallerConstants
    {
        public const string ProductName = "Vortex Launch Bridge";
        public const string PluginName = "vortex-launch-bridge";
        public const string RepositoryOwner = "WoahItsJeebus";
        public const string RepositoryName = "MSVB";
        public const string RepositoryBranch = "main";
        public const string RepositoryUrl = "https://github.com/WoahItsJeebus/MSVB";
        public const string InstallerVersion = "1.0.4";
    }

    internal sealed class ResolvedInstallPaths
    {
        public ResolvedInstallPaths(string millenniumDirectory, string pluginsDirectory)
        {
            MillenniumDirectory = millenniumDirectory;
            PluginsDirectory = pluginsDirectory;
            PluginDirectory = Path.Combine(pluginsDirectory, InstallerConstants.PluginName);
        }

        public string MillenniumDirectory { get; private set; }
        public string PluginsDirectory { get; private set; }
        public string PluginDirectory { get; private set; }
    }

    internal static class MillenniumPathResolver
    {
        public static string DiscoverMillenniumDirectory()
        {
            List<string> candidates = new List<string>();

            AddEnvironmentCandidates(candidates);
            AddRegistryCandidates(candidates);

            string programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
            string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            AddCandidate(candidates, Path.Combine(programFilesX86, "Steam"));
            AddCandidate(candidates, Path.Combine(programFiles, "Steam"));

            foreach (string candidate in candidates)
            {
                ResolvedInstallPaths resolved;
                string error;
                if (TryResolve(candidate, out resolved, out error))
                {
                    return resolved.MillenniumDirectory;
                }
            }

            return null;
        }

        public static bool TryResolve(string selectedDirectory, out ResolvedInstallPaths resolved, out string error)
        {
            resolved = null;
            error = null;

            if (String.IsNullOrWhiteSpace(selectedDirectory))
            {
                error = "Select the Millennium installation directory.";
                return false;
            }

            string selected;
            try
            {
                selected = NormalizeDirectory(selectedDirectory);
            }
            catch (Exception ex)
            {
                error = "The selected path is invalid: " + ex.Message;
                return false;
            }

            string leaf = Path.GetFileName(selected);
            string millenniumDirectory = null;
            string pluginsDirectory = null;

            if (String.Equals(leaf, InstallerConstants.PluginName, StringComparison.OrdinalIgnoreCase))
            {
                pluginsDirectory = Path.GetDirectoryName(selected);
                millenniumDirectory = pluginsDirectory == null ? null : Path.GetDirectoryName(pluginsDirectory);
            }
            else if (String.Equals(leaf, "plugins", StringComparison.OrdinalIgnoreCase))
            {
                pluginsDirectory = selected;
                millenniumDirectory = Path.GetDirectoryName(selected);
            }
            else if (IsMillenniumDirectory(selected))
            {
                millenniumDirectory = selected;
                pluginsDirectory = Path.Combine(selected, "plugins");
            }
            else
            {
                string nestedMillennium = Path.Combine(selected, "millennium");
                if (IsMillenniumDirectory(nestedMillennium))
                {
                    millenniumDirectory = nestedMillennium;
                    pluginsDirectory = Path.Combine(nestedMillennium, "plugins");
                }
            }

            if (millenniumDirectory == null || pluginsDirectory == null || !IsMillenniumDirectory(millenniumDirectory))
            {
                error = "This folder does not look like a Millennium installation. Select the folder containing Millennium's bin, lib, and plugins folders.";
                return false;
            }

            millenniumDirectory = NormalizeDirectory(millenniumDirectory);
            pluginsDirectory = NormalizeDirectory(pluginsDirectory);
            resolved = new ResolvedInstallPaths(millenniumDirectory, pluginsDirectory);

            if (!IsSafePluginTarget(resolved.PluginsDirectory, resolved.PluginDirectory))
            {
                resolved = null;
                error = "The resolved plugin destination failed its safety check.";
                return false;
            }

            return true;
        }

        public static bool IsMillenniumDirectory(string path)
        {
            if (String.IsNullOrWhiteSpace(path) || !Directory.Exists(path))
            {
                return false;
            }

            return Directory.Exists(Path.Combine(path, "bin"))
                && Directory.Exists(Path.Combine(path, "lib"));
        }

        public static bool IsSafePluginTarget(string pluginsDirectory, string pluginDirectory)
        {
            if (String.IsNullOrWhiteSpace(pluginsDirectory) || String.IsNullOrWhiteSpace(pluginDirectory))
            {
                return false;
            }

            string normalizedPlugins = NormalizeDirectory(pluginsDirectory);
            string normalizedPlugin = NormalizeDirectory(pluginDirectory);
            string expected = NormalizeDirectory(Path.Combine(normalizedPlugins, InstallerConstants.PluginName));

            return String.Equals(normalizedPlugin, expected, StringComparison.OrdinalIgnoreCase)
                && String.Equals(Path.GetDirectoryName(normalizedPlugin), normalizedPlugins, StringComparison.OrdinalIgnoreCase)
                && String.Equals(Path.GetFileName(normalizedPlugin), InstallerConstants.PluginName, StringComparison.OrdinalIgnoreCase);
        }

        public static string NormalizeDirectory(string path)
        {
            string full = Path.GetFullPath(Environment.ExpandEnvironmentVariables(path.Trim().Trim('"')));
            string root = Path.GetPathRoot(full);
            if (!String.Equals(full, root, StringComparison.OrdinalIgnoreCase))
            {
                full = full.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
            }

            return full;
        }

        private static void AddEnvironmentCandidates(List<string> candidates)
        {
            string pluginPath = Environment.GetEnvironmentVariable("MILLENNIUM__PLUGINS_PATH");
            if (!String.IsNullOrWhiteSpace(pluginPath))
            {
                AddCandidate(candidates, pluginPath);
            }

            string steamPath = Environment.GetEnvironmentVariable("MILLENNIUM__STEAM_PATH");
            if (!String.IsNullOrWhiteSpace(steamPath))
            {
                AddCandidate(candidates, steamPath);
            }
        }

        private static void AddRegistryCandidates(List<string> candidates)
        {
            AddRegistryValue(candidates, RegistryHive.CurrentUser, RegistryView.Default, @"Software\Valve\Steam", "SteamPath");
            AddRegistryValue(candidates, RegistryHive.CurrentUser, RegistryView.Default, @"Software\Valve\Steam", "SteamExe");
            AddRegistryValue(candidates, RegistryHive.LocalMachine, RegistryView.Registry32, @"SOFTWARE\Valve\Steam", "InstallPath");
            AddRegistryValue(candidates, RegistryHive.LocalMachine, RegistryView.Registry64, @"SOFTWARE\Valve\Steam", "InstallPath");
        }

        private static void AddRegistryValue(List<string> candidates, RegistryHive hive, RegistryView view, string keyName, string valueName)
        {
            try
            {
                using (RegistryKey baseKey = RegistryKey.OpenBaseKey(hive, view))
                using (RegistryKey key = baseKey.OpenSubKey(keyName))
                {
                    if (key == null)
                    {
                        return;
                    }

                    string value = key.GetValue(valueName) as string;
                    if (String.IsNullOrWhiteSpace(value))
                    {
                        return;
                    }

                    if (String.Equals(Path.GetExtension(value), ".exe", StringComparison.OrdinalIgnoreCase))
                    {
                        value = Path.GetDirectoryName(value);
                    }

                    AddCandidate(candidates, value);
                }
            }
            catch
            {
                // Registry discovery is best effort; the UI will allow browsing.
            }
        }

        private static void AddCandidate(List<string> candidates, string path)
        {
            if (String.IsNullOrWhiteSpace(path))
            {
                return;
            }

            try
            {
                string normalized = NormalizeDirectory(path);
                if (!candidates.Exists(delegate(string existing)
                    {
                        return String.Equals(existing, normalized, StringComparison.OrdinalIgnoreCase);
                    }))
                {
                    candidates.Add(normalized);
                }
            }
            catch
            {
                // Ignore malformed discovery candidates.
            }
        }
    }

    internal static class SafeFileSystem
    {
        public static void CopyDirectory(string sourceDirectory, string destinationDirectory)
        {
            string source = MillenniumPathResolver.NormalizeDirectory(sourceDirectory);
            string destination = MillenniumPathResolver.NormalizeDirectory(destinationDirectory);

            if (!Directory.Exists(source))
            {
                throw new DirectoryNotFoundException("Source directory not found: " + source);
            }

            FileAttributes sourceAttributes = File.GetAttributes(source);
            if ((sourceAttributes & FileAttributes.ReparsePoint) != 0)
            {
                throw new IOException("Refusing to copy a reparse-point source directory: " + source);
            }

            Directory.CreateDirectory(destination);

            foreach (string file in Directory.GetFiles(source))
            {
                FileAttributes attributes = File.GetAttributes(file);
                if ((attributes & FileAttributes.ReparsePoint) != 0)
                {
                    throw new IOException("Refusing to copy a reparse-point file: " + file);
                }

                File.Copy(file, Path.Combine(destination, Path.GetFileName(file)), false);
            }

            foreach (string directory in Directory.GetDirectories(source))
            {
                FileAttributes attributes = File.GetAttributes(directory);
                if ((attributes & FileAttributes.ReparsePoint) != 0)
                {
                    throw new IOException("Refusing to copy a reparse-point directory: " + directory);
                }

                CopyDirectory(directory, Path.Combine(destination, Path.GetFileName(directory)));
            }
        }

        public static void DeleteDirectorySafely(string directory)
        {
            if (String.IsNullOrWhiteSpace(directory) || !Directory.Exists(directory))
            {
                return;
            }

            FileAttributes rootAttributes = File.GetAttributes(directory);
            if ((rootAttributes & FileAttributes.ReparsePoint) != 0)
            {
                Directory.Delete(directory, false);
                return;
            }

            foreach (string file in Directory.GetFiles(directory))
            {
                FileAttributes attributes = File.GetAttributes(file);
                if ((attributes & FileAttributes.ReadOnly) != 0)
                {
                    File.SetAttributes(file, attributes & ~FileAttributes.ReadOnly);
                }

                File.Delete(file);
            }

            foreach (string child in Directory.GetDirectories(directory))
            {
                FileAttributes attributes = File.GetAttributes(child);
                if ((attributes & FileAttributes.ReparsePoint) != 0)
                {
                    Directory.Delete(child, false);
                }
                else
                {
                    DeleteDirectorySafely(child);
                }
            }

            Directory.Delete(directory, false);
        }

        public static bool IsSteamRunning()
        {
            try
            {
                Process[] processes = Process.GetProcessesByName("steam");
                try
                {
                    return processes.Length > 0;
                }
                finally
                {
                    foreach (Process process in processes)
                    {
                        process.Dispose();
                    }
                }
            }
            catch
            {
                return false;
            }
        }
    }

    internal static class WindowsCommandLine
    {
        public static string JoinArguments(IList<string> arguments)
        {
            List<string> quoted = new List<string>();
            foreach (string argument in arguments)
            {
                quoted.Add(QuoteArgument(argument));
            }

            return String.Join(" ", quoted.ToArray());
        }

        public static string QuoteArgument(string argument)
        {
            if (argument == null)
            {
                return "\"\"";
            }

            if (argument.Length > 0
                && argument.IndexOfAny(new char[] { ' ', '\t', '\n', '\v', '"' }) < 0)
            {
                return argument;
            }

            System.Text.StringBuilder result = new System.Text.StringBuilder();
            result.Append('"');
            int backslashes = 0;

            foreach (char character in argument)
            {
                if (character == '\\')
                {
                    backslashes++;
                    continue;
                }

                if (character == '"')
                {
                    result.Append('\\', backslashes * 2 + 1);
                    result.Append('"');
                    backslashes = 0;
                    continue;
                }

                result.Append('\\', backslashes);
                backslashes = 0;
                result.Append(character);
            }

            result.Append('\\', backslashes * 2);
            result.Append('"');
            return result.ToString();
        }
    }
}
