using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace VortexLaunchBridge.Installer
{
    internal sealed class InstallerProgressInfo
    {
        public InstallerProgressInfo(string message, int percent, bool indeterminate)
        {
            Message = message;
            Percent = Math.Max(0, Math.Min(100, percent));
            IsIndeterminate = indeterminate;
        }

        public string Message { get; private set; }
        public int Percent { get; private set; }
        public bool IsIndeterminate { get; private set; }
    }

    internal sealed class InstallOperationResult
    {
        public string PluginVersion { get; set; }
        public string Commit { get; set; }
        public string PluginDirectory { get; set; }
    }

    internal sealed class NodeToolchain
    {
        public string NodeExecutable { get; set; }
        public string NpmCliScript { get; set; }
        public string Description { get; set; }
    }

    internal sealed class VortexPluginInstallerService : IDisposable
    {
        private readonly HttpClient httpClient;
        private readonly IProgress<InstallerProgressInfo> progress;

        public VortexPluginInstallerService(IProgress<InstallerProgressInfo> progress)
        {
            this.progress = progress;

            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
            HttpClientHandler handler = new HttpClientHandler();
            handler.AllowAutoRedirect = true;
            handler.AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate;

            httpClient = new HttpClient(handler);
            httpClient.Timeout = TimeSpan.FromMinutes(30);
            httpClient.DefaultRequestHeaders.UserAgent.ParseAdd(
                "VortexLaunchBridgeInstaller/" + InstallerConstants.InstallerVersion);
            httpClient.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        }

        public async Task<InstallOperationResult> InstallOrRepairAsync(
            ResolvedInstallPaths paths,
            CancellationToken cancellationToken)
        {
            return await InstallOrRepairAsync(paths, cancellationToken, true).ConfigureAwait(false);
        }

        internal async Task<InstallOperationResult> InstallOrRepairAsync(
            ResolvedInstallPaths paths,
            CancellationToken cancellationToken,
            bool requireSteamClosed)
        {
            if (paths == null)
            {
                throw new ArgumentNullException("paths");
            }

            if (!MillenniumPathResolver.IsSafePluginTarget(paths.PluginsDirectory, paths.PluginDirectory))
            {
                throw new InvalidOperationException("The plugin destination failed its safety check.");
            }

            string operationRoot = Path.Combine(
                Path.GetTempPath(),
                "VortexLaunchBridgeInstaller",
                Guid.NewGuid().ToString("N"));

            Directory.CreateDirectory(operationRoot);
            Report("Preparing installation workspace...", 2, false);

            try
            {
                string commit = await ResolveSourceCommitAsync(cancellationToken).ConfigureAwait(false);
                string archivePath = Path.Combine(operationRoot, "source.zip");
                string archiveUrl = "https://codeload.github.com/"
                    + InstallerConstants.RepositoryOwner + "/"
                    + InstallerConstants.RepositoryName + "/zip/" + commit;

                Report("Downloading source from " + InstallerConstants.RepositoryUrl + "...", 5, false);
                await DownloadFileAsync(
                    archiveUrl,
                    archivePath,
                    5,
                    22,
                    cancellationToken).ConfigureAwait(false);

                string extractedRoot = Path.Combine(operationRoot, "source");
                Report("Extracting source snapshot...", 24, true);
                ExtractZipSafely(archivePath, extractedRoot, cancellationToken);
                string sourceDirectory = FindSourceDirectory(extractedRoot);
                ValidateSourceCheckout(sourceDirectory);

                string packageManagerVersion = ReadPnpmVersion(sourceDirectory);
                string pluginVersion = ReadAndValidatePluginVersion(sourceDirectory);

                NodeToolchain node = await FindOrAcquireNodeAsync(
                    operationRoot,
                    cancellationToken).ConfigureAwait(false);
                Report("Using " + node.Description + ".", 32, false);

                string pnpmScript = await InstallPnpmAsync(
                    node,
                    packageManagerVersion,
                    operationRoot,
                    cancellationToken).ConfigureAwait(false);

                await BuildPluginAsync(
                    node,
                    pnpmScript,
                    sourceDirectory,
                    operationRoot,
                    cancellationToken).ConfigureAwait(false);

                string runtimePackage = Path.Combine(operationRoot, "runtime-package");
                Report("Preparing validated runtime package...", 82, false);
                CreateRuntimePackage(sourceDirectory, runtimePackage);
                ValidateRuntimePackage(runtimePackage);

                cancellationToken.ThrowIfCancellationRequested();
                if (requireSteamClosed && SafeFileSystem.IsSteamRunning())
                {
                    throw new InvalidOperationException(
                        "Steam was started while the plugin was building. Fully exit Steam and run Install/Repair again.");
                }

                Report("Installing plugin into Millennium...", 88, false);
                DeployAtomically(runtimePackage, paths, cancellationToken);

                Report("Installation completed successfully.", 100, false);
                InstallOperationResult result = new InstallOperationResult();
                result.PluginVersion = pluginVersion;
                result.Commit = commit;
                result.PluginDirectory = paths.PluginDirectory;
                return result;
            }
            finally
            {
                try
                {
                    SafeFileSystem.DeleteDirectorySafely(operationRoot);
                }
                catch
                {
                    // Temporary cleanup must not mask the real operation result.
                }
            }
        }

        public void DeletePlugin(ResolvedInstallPaths paths)
        {
            if (paths == null)
            {
                throw new ArgumentNullException("paths");
            }

            if (!MillenniumPathResolver.IsSafePluginTarget(paths.PluginsDirectory, paths.PluginDirectory))
            {
                throw new InvalidOperationException("The plugin destination failed its safety check.");
            }

            if (!Directory.Exists(paths.PluginDirectory))
            {
                return;
            }

            SafeFileSystem.DeleteDirectorySafely(paths.PluginDirectory);
        }

        public void Dispose()
        {
            httpClient.Dispose();
        }

        private async Task<string> ResolveSourceCommitAsync(CancellationToken cancellationToken)
        {
            Report("Resolving the latest repository commit...", 3, true);
            string apiUrl = "https://api.github.com/repos/"
                + InstallerConstants.RepositoryOwner + "/"
                + InstallerConstants.RepositoryName + "/commits/"
                + InstallerConstants.RepositoryBranch;

            using (HttpResponseMessage response = await httpClient.GetAsync(apiUrl, cancellationToken).ConfigureAwait(false))
            {
                response.EnsureSuccessStatusCode();
                string json = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                JavaScriptSerializer serializer = new JavaScriptSerializer();
                Dictionary<string, object> root = serializer.DeserializeObject(json) as Dictionary<string, object>;
                object shaValue;
                string sha = root != null && root.TryGetValue("sha", out shaValue) ? shaValue as string : null;

                if (String.IsNullOrWhiteSpace(sha) || !Regex.IsMatch(sha, "^[0-9a-fA-F]{40}$"))
                {
                    throw new InvalidDataException("GitHub returned an invalid source commit.");
                }

                Report("Source commit: " + sha.Substring(0, 12), 4, false);
                return sha.ToLowerInvariant();
            }
        }

        private async Task DownloadFileAsync(
            string url,
            string destination,
            int startPercent,
            int endPercent,
            CancellationToken cancellationToken)
        {
            using (HttpResponseMessage response = await httpClient.GetAsync(
                url,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken).ConfigureAwait(false))
            {
                response.EnsureSuccessStatusCode();
                long? total = response.Content.Headers.ContentLength;

                using (Stream input = await response.Content.ReadAsStreamAsync().ConfigureAwait(false))
                using (FileStream output = new FileStream(
                    destination,
                    FileMode.CreateNew,
                    FileAccess.Write,
                    FileShare.None,
                    81920,
                    true))
                {
                    byte[] buffer = new byte[81920];
                    long received = 0;
                    int lastReported = -1;
                    long lastReportedBytes = 0;

                    while (true)
                    {
                        int read = await input.ReadAsync(buffer, 0, buffer.Length, cancellationToken).ConfigureAwait(false);
                        if (read == 0)
                        {
                            break;
                        }

                        await output.WriteAsync(buffer, 0, read, cancellationToken).ConfigureAwait(false);
                        received += read;

                        if (total.HasValue && total.Value > 0)
                        {
                            int range = endPercent - startPercent;
                            int percent = startPercent + (int)Math.Min(
                                range,
                                (received * range) / total.Value);

                            if (percent != lastReported)
                            {
                                lastReported = percent;
                                Report("Downloading... " + FormatBytes(received)
                                    + " / " + FormatBytes(total.Value), percent, false);
                            }
                        }
                        else
                        {
                            if (received - lastReportedBytes >= 1024L * 1024L)
                            {
                                lastReportedBytes = received;
                                Report("Downloading... " + FormatBytes(received), startPercent, true);
                            }
                        }
                    }

                    Report("Download complete (" + FormatBytes(received) + ").", endPercent, false);
                }
            }
        }

        private static void ExtractZipSafely(
            string archivePath,
            string destinationDirectory,
            CancellationToken cancellationToken)
        {
            Directory.CreateDirectory(destinationDirectory);
            string destinationRoot = MillenniumPathResolver.NormalizeDirectory(destinationDirectory)
                + Path.DirectorySeparatorChar;
            long totalUncompressedBytes = 0;
            int entryCount = 0;

            using (FileStream stream = File.OpenRead(archivePath))
            using (ZipArchive archive = new ZipArchive(stream, ZipArchiveMode.Read, false))
            {
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    entryCount++;
                    totalUncompressedBytes += entry.Length;

                    if (entryCount > 20000 || totalUncompressedBytes > 1024L * 1024L * 1024L)
                    {
                        throw new InvalidDataException("The downloaded source archive exceeds the installer safety limits.");
                    }

                    string relative = entry.FullName.Replace('/', Path.DirectorySeparatorChar);
                    string outputPath = Path.GetFullPath(Path.Combine(destinationDirectory, relative));
                    if (!outputPath.StartsWith(destinationRoot, StringComparison.OrdinalIgnoreCase))
                    {
                        throw new InvalidDataException("The source archive contains an unsafe path.");
                    }

                    if (String.IsNullOrEmpty(entry.Name))
                    {
                        Directory.CreateDirectory(outputPath);
                        continue;
                    }

                    string parent = Path.GetDirectoryName(outputPath);
                    if (!String.IsNullOrEmpty(parent))
                    {
                        Directory.CreateDirectory(parent);
                    }

                    using (Stream input = entry.Open())
                    using (FileStream output = new FileStream(outputPath, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                    {
                        byte[] buffer = new byte[81920];
                        while (true)
                        {
                            cancellationToken.ThrowIfCancellationRequested();
                            int read = input.Read(buffer, 0, buffer.Length);
                            if (read == 0)
                            {
                                break;
                            }
                            output.Write(buffer, 0, read);
                        }
                    }
                }
            }
        }

        private static string FindSourceDirectory(string extractedRoot)
        {
            foreach (string directory in Directory.GetDirectories(extractedRoot))
            {
                if (File.Exists(Path.Combine(directory, "package.json"))
                    && File.Exists(Path.Combine(directory, "plugin.json"))
                    && File.Exists(Path.Combine(directory, "pnpm-lock.yaml")))
                {
                    return directory;
                }
            }

            throw new InvalidDataException("The downloaded archive does not contain the expected repository root.");
        }

        private static void ValidateSourceCheckout(string sourceDirectory)
        {
            string[] requiredFiles =
            {
                "package.json",
                "plugin.json",
                "pnpm-lock.yaml",
                Path.Combine("frontend", "index.tsx"),
                Path.Combine("backend", "main.lua"),
                Path.Combine("backend", "util", "process_shell.exe")
            };

            foreach (string relativePath in requiredFiles)
            {
                string fullPath = Path.Combine(sourceDirectory, relativePath);
                if (!File.Exists(fullPath))
                {
                    throw new InvalidDataException("Repository source is missing required file: " + relativePath);
                }
            }
        }

        private static string ReadPnpmVersion(string sourceDirectory)
        {
            Dictionary<string, object> package = ReadJsonObject(Path.Combine(sourceDirectory, "package.json"));
            object packageManagerValue;
            string packageManager = package.TryGetValue("packageManager", out packageManagerValue)
                ? packageManagerValue as string
                : null;

            Match match = Regex.Match(packageManager ?? String.Empty, "^pnpm@([0-9]+\\.[0-9]+\\.[0-9]+)$");
            if (!match.Success)
            {
                throw new InvalidDataException("package.json does not pin a valid pnpm version.");
            }

            return match.Groups[1].Value;
        }

        private static string ReadAndValidatePluginVersion(string sourceDirectory)
        {
            Dictionary<string, object> plugin = ReadJsonObject(Path.Combine(sourceDirectory, "plugin.json"));
            object nameValue;
            string name = plugin.TryGetValue("name", out nameValue) ? nameValue as string : null;
            if (!String.Equals(name, InstallerConstants.PluginName, StringComparison.Ordinal))
            {
                throw new InvalidDataException("The downloaded repository has an unexpected plugin name.");
            }

            object versionValue;
            string version = plugin.TryGetValue("version", out versionValue) ? versionValue as string : null;
            if (String.IsNullOrWhiteSpace(version))
            {
                throw new InvalidDataException("plugin.json does not contain a version.");
            }

            return version;
        }

        private static Dictionary<string, object> ReadJsonObject(string path)
        {
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            Dictionary<string, object> value = serializer.DeserializeObject(File.ReadAllText(path)) as Dictionary<string, object>;
            if (value == null)
            {
                throw new InvalidDataException(Path.GetFileName(path) + " is not a JSON object.");
            }
            return value;
        }

        private async Task<NodeToolchain> FindOrAcquireNodeAsync(
            string operationRoot,
            CancellationToken cancellationToken)
        {
            NodeToolchain systemNode = FindSystemNode();
            if (systemNode != null)
            {
                return systemNode;
            }

            Report("Node.js 20+ was not found; preparing a portable Node.js toolchain...", 34, true);
            return await AcquirePortableNodeAsync(operationRoot, cancellationToken).ConfigureAwait(false);
        }

        private static NodeToolchain FindSystemNode()
        {
            List<string> candidates = new List<string>();
            string pathValue = Environment.GetEnvironmentVariable("PATH") ?? String.Empty;
            foreach (string pathEntry in pathValue.Split(Path.PathSeparator))
            {
                string cleaned = pathEntry.Trim().Trim('"');
                if (cleaned.Length > 0)
                {
                    candidates.Add(Path.Combine(cleaned, "node.exe"));
                }
            }

            string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            candidates.Add(Path.Combine(programFiles, "nodejs", "node.exe"));

            foreach (string candidate in candidates)
            {
                try
                {
                    if (!File.Exists(candidate))
                    {
                        continue;
                    }

                    int major = GetNodeMajorVersion(candidate);
                    if (major < 20)
                    {
                        continue;
                    }

                    string nodeDirectory = Path.GetDirectoryName(candidate);
                    string npmCli = Path.Combine(nodeDirectory, "node_modules", "npm", "bin", "npm-cli.js");
                    if (!File.Exists(npmCli))
                    {
                        continue;
                    }

                    NodeToolchain toolchain = new NodeToolchain();
                    toolchain.NodeExecutable = candidate;
                    toolchain.NpmCliScript = npmCli;
                    toolchain.Description = "system Node.js " + major.ToString(CultureInfo.InvariantCulture);
                    return toolchain;
                }
                catch
                {
                    // Try the next candidate.
                }
            }

            return null;
        }

        private static int GetNodeMajorVersion(string nodeExecutable)
        {
            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = nodeExecutable;
            startInfo.Arguments = "--version";
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.RedirectStandardOutput = true;
            startInfo.RedirectStandardError = true;

            using (Process process = Process.Start(startInfo))
            {
                string output = process.StandardOutput.ReadToEnd();
                process.WaitForExit(5000);
                if (!process.HasExited || process.ExitCode != 0)
                {
                    try { process.Kill(); } catch { }
                    return 0;
                }

                Match match = Regex.Match(output.Trim(), "^v([0-9]+)\\.");
                int major;
                return match.Success
                    && Int32.TryParse(match.Groups[1].Value, NumberStyles.None, CultureInfo.InvariantCulture, out major)
                    ? major
                    : 0;
            }
        }

        private async Task<NodeToolchain> AcquirePortableNodeAsync(
            string operationRoot,
            CancellationToken cancellationToken)
        {
            string architecture = GetNodeArchitecture();
            string cacheRoot = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "VortexLaunchBridge",
                "InstallerCache",
                "node");

            NodeToolchain cached = FindCachedNode(cacheRoot, architecture);
            if (cached != null)
            {
                cached.Description = "cached portable Node.js";
                return cached;
            }

            string checksumsUrl = "https://nodejs.org/dist/latest-v20.x/SHASUMS256.txt";
            using (HttpResponseMessage response = await httpClient.GetAsync(checksumsUrl, cancellationToken).ConfigureAwait(false))
            {
                response.EnsureSuccessStatusCode();
                string checksums = await response.Content.ReadAsStringAsync().ConfigureAwait(false);
                string pattern = "(?im)^([0-9a-f]{64})\\s+\\*?(node-v20\\.[^\\s]+-win-"
                    + Regex.Escape(architecture) + "\\.zip)\\s*$";
                Match match = Regex.Match(checksums, pattern);
                if (!match.Success)
                {
                    throw new InvalidDataException("Could not find a supported Node.js 20 Windows archive.");
                }

                string expectedHash = match.Groups[1].Value.ToLowerInvariant();
                string archiveName = match.Groups[2].Value;
                string archiveUrl = "https://nodejs.org/dist/latest-v20.x/" + archiveName;
                string archivePath = Path.Combine(operationRoot, archiveName);

                Report("Downloading portable Node.js from nodejs.org...", 35, true);
                await DownloadFileAsync(
                    archiveUrl,
                    archivePath,
                    35,
                    45,
                    cancellationToken).ConfigureAwait(false);

                string actualHash = ComputeSha256(archivePath);
                if (!String.Equals(actualHash, expectedHash, StringComparison.OrdinalIgnoreCase))
                {
                    throw new InvalidDataException("Portable Node.js failed its SHA-256 verification.");
                }

                string cacheStaging = Path.Combine(cacheRoot, ".install-" + Guid.NewGuid().ToString("N"));
                string extracted = Path.Combine(operationRoot, "node-extracted");
                ExtractZipSafely(archivePath, extracted, cancellationToken);

                string[] nodeExecutables = Directory.GetFiles(extracted, "node.exe", SearchOption.AllDirectories);
                if (nodeExecutables.Length != 1)
                {
                    throw new InvalidDataException("Portable Node.js archive has an unexpected layout.");
                }

                string extractedNodeRoot = Path.GetDirectoryName(nodeExecutables[0]);
                Directory.CreateDirectory(cacheRoot);
                SafeFileSystem.CopyDirectory(extractedNodeRoot, cacheStaging);

                string finalCache = Path.Combine(cacheRoot, Path.GetFileNameWithoutExtension(archiveName));
                if (Directory.Exists(finalCache))
                {
                    SafeFileSystem.DeleteDirectorySafely(cacheStaging);
                }
                else
                {
                    Directory.Move(cacheStaging, finalCache);
                }

                NodeToolchain result = CreateNodeToolchain(finalCache, "portable Node.js " + archiveName);
                if (result == null)
                {
                    throw new InvalidDataException("Portable Node.js is missing npm.");
                }
                return result;
            }
        }

        private static string GetNodeArchitecture()
        {
            if (!Environment.Is64BitOperatingSystem)
            {
                throw new PlatformNotSupportedException("Millennium 3.x and this plugin require 64-bit Windows.");
            }

            string architecture = Environment.GetEnvironmentVariable("PROCESSOR_ARCHITEW6432");
            if (String.IsNullOrWhiteSpace(architecture))
            {
                architecture = Environment.GetEnvironmentVariable("PROCESSOR_ARCHITECTURE");
            }

            return !String.IsNullOrWhiteSpace(architecture)
                && architecture.IndexOf("ARM64", StringComparison.OrdinalIgnoreCase) >= 0
                ? "arm64"
                : "x64";
        }

        private static NodeToolchain FindCachedNode(string cacheRoot, string architecture)
        {
            if (!Directory.Exists(cacheRoot))
            {
                return null;
            }

            string[] directories = Directory.GetDirectories(cacheRoot, "node-v20*-win-" + architecture);
            Array.Sort(directories, StringComparer.OrdinalIgnoreCase);
            Array.Reverse(directories);
            foreach (string directory in directories)
            {
                NodeToolchain candidate = CreateNodeToolchain(directory, "cached portable Node.js");
                if (candidate != null && GetNodeMajorVersion(candidate.NodeExecutable) >= 20)
                {
                    return candidate;
                }
            }

            return null;
        }

        private static NodeToolchain CreateNodeToolchain(string nodeRoot, string description)
        {
            string nodeExecutable = Path.Combine(nodeRoot, "node.exe");
            string npmCli = Path.Combine(nodeRoot, "node_modules", "npm", "bin", "npm-cli.js");
            if (!File.Exists(nodeExecutable) || !File.Exists(npmCli))
            {
                return null;
            }

            NodeToolchain result = new NodeToolchain();
            result.NodeExecutable = nodeExecutable;
            result.NpmCliScript = npmCli;
            result.Description = description;
            return result;
        }

        private async Task<string> InstallPnpmAsync(
            NodeToolchain node,
            string pnpmVersion,
            string operationRoot,
            CancellationToken cancellationToken)
        {
            string pnpmRoot = Path.Combine(operationRoot, "pnpm");
            string npmCache = Path.Combine(operationRoot, "npm-cache");
            Report("Preparing pnpm " + pnpmVersion + "...", 47, true);

            List<string> arguments = new List<string>();
            arguments.Add(node.NpmCliScript);
            arguments.Add("install");
            arguments.Add("--global");
            arguments.Add("--prefix");
            arguments.Add(pnpmRoot);
            arguments.Add("--no-audit");
            arguments.Add("--no-fund");
            arguments.Add("pnpm@" + pnpmVersion);

            Dictionary<string, string> environment = CreateBuildEnvironment(operationRoot);
            environment["npm_config_cache"] = npmCache;

            await RunProcessAsync(
                node.NodeExecutable,
                arguments,
                operationRoot,
                environment,
                cancellationToken).ConfigureAwait(false);

            string pnpmScript = Path.Combine(pnpmRoot, "node_modules", "pnpm", "bin", "pnpm.cjs");
            if (!File.Exists(pnpmScript))
            {
                throw new InvalidDataException("The pinned pnpm installation did not produce pnpm.cjs.");
            }

            return pnpmScript;
        }

        private async Task BuildPluginAsync(
            NodeToolchain node,
            string pnpmScript,
            string sourceDirectory,
            string operationRoot,
            CancellationToken cancellationToken)
        {
            Dictionary<string, string> environment = CreateBuildEnvironment(operationRoot);
            string storeDirectory = Path.Combine(operationRoot, "pnpm-store");

            Report("Installing pinned repository dependencies...", 52, true);
            await RunProcessAsync(
                node.NodeExecutable,
                new List<string>
                {
                    pnpmScript,
                    "install",
                    "--frozen-lockfile",
                    "--store-dir",
                    storeDirectory
                },
                sourceDirectory,
                environment,
                cancellationToken).ConfigureAwait(false);

            Report("Building the production Millennium plugin...", 70, true);
            await RunProcessAsync(
                node.NodeExecutable,
                new List<string>
                {
                    pnpmScript,
                    "run",
                    "build"
                },
                sourceDirectory,
                environment,
                cancellationToken).ConfigureAwait(false);
        }

        private static Dictionary<string, string> CreateBuildEnvironment(string operationRoot)
        {
            Dictionary<string, string> environment = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            environment["CI"] = "true";
            environment["NODE_ENV"] = "production";
            environment["COREPACK_ENABLE_DOWNLOAD_PROMPT"] = "0";
            environment["npm_config_update_notifier"] = "false";
            environment["npm_config_cache"] = Path.Combine(operationRoot, "npm-cache");
            return environment;
        }

        private async Task RunProcessAsync(
            string executable,
            IList<string> arguments,
            string workingDirectory,
            IDictionary<string, string> environment,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = executable;
            startInfo.Arguments = WindowsCommandLine.JoinArguments(arguments);
            startInfo.WorkingDirectory = workingDirectory;
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.RedirectStandardOutput = true;
            startInfo.RedirectStandardError = true;

            foreach (KeyValuePair<string, string> item in environment)
            {
                startInfo.EnvironmentVariables[item.Key] = item.Value;
            }

            using (Process process = new Process())
            {
                process.StartInfo = startInfo;
                process.OutputDataReceived += delegate(object sender, DataReceivedEventArgs args)
                {
                    if (!String.IsNullOrWhiteSpace(args.Data))
                    {
                        Report("  " + args.Data, 0, true);
                    }
                };
                process.ErrorDataReceived += delegate(object sender, DataReceivedEventArgs args)
                {
                    if (!String.IsNullOrWhiteSpace(args.Data))
                    {
                        Report("  " + args.Data, 0, true);
                    }
                };

                if (!process.Start())
                {
                    throw new InvalidOperationException("Failed to start build process: " + executable);
                }

                process.BeginOutputReadLine();
                process.BeginErrorReadLine();

                using (CancellationTokenRegistration registration = cancellationToken.Register(delegate
                    {
                        try
                        {
                            if (!process.HasExited)
                            {
                                process.Kill();
                            }
                        }
                        catch
                        {
                            // The process may have exited concurrently.
                        }
                    }))
                {
                    await Task.Run(delegate { process.WaitForExit(); }).ConfigureAwait(false);
                    process.WaitForExit();
                }

                cancellationToken.ThrowIfCancellationRequested();
                if (process.ExitCode != 0)
                {
                    throw new InvalidOperationException(
                        "Build command failed with exit code "
                        + process.ExitCode.ToString(CultureInfo.InvariantCulture) + ".");
                }
            }
        }

        private static void CreateRuntimePackage(string sourceDirectory, string packageDirectory)
        {
            Directory.CreateDirectory(packageDirectory);

            string[] rootFiles =
            {
                "plugin.json",
                "README.md",
                "LICENSE",
                "CHANGELOG.md"
            };

            foreach (string rootFile in rootFiles)
            {
                string source = Path.Combine(sourceDirectory, rootFile);
                if (File.Exists(source))
                {
                    File.Copy(source, Path.Combine(packageDirectory, rootFile), false);
                }
            }

            CopyRequiredDirectory(sourceDirectory, packageDirectory, "backend");
            CopyRequiredDirectory(
                sourceDirectory,
                packageDirectory,
                Path.Combine(".millennium", "Dist"));

            string generatedAssets = Path.Combine(sourceDirectory, "dist");
            if (Directory.Exists(generatedAssets))
            {
                SafeFileSystem.CopyDirectory(generatedAssets, Path.Combine(packageDirectory, "dist"));
            }
        }

        private static void CopyRequiredDirectory(
            string sourceDirectory,
            string packageDirectory,
            string relativeDirectory)
        {
            string source = Path.Combine(sourceDirectory, relativeDirectory);
            if (!Directory.Exists(source))
            {
                throw new InvalidDataException("Build output is missing directory: " + relativeDirectory);
            }

            SafeFileSystem.CopyDirectory(source, Path.Combine(packageDirectory, relativeDirectory));
        }

        private static void ValidateRuntimePackage(string packageDirectory)
        {
            ReadAndValidatePluginVersion(packageDirectory);

            string[] requiredFiles =
            {
                Path.Combine(".millennium", "Dist", "index.js"),
                Path.Combine(".millennium", "Dist", "webkit.js"),
                Path.Combine("backend", "main.lua"),
                Path.Combine("backend", "util", "process_shell.exe")
            };

            foreach (string relativePath in requiredFiles)
            {
                string fullPath = Path.Combine(packageDirectory, relativePath);
                FileInfo file = new FileInfo(fullPath);
                if (!file.Exists || file.Length == 0)
                {
                    throw new InvalidDataException("Runtime package is missing required file: " + relativePath);
                }
            }

            FileInfo frontend = new FileInfo(Path.Combine(packageDirectory, ".millennium", "Dist", "index.js"));
            if (frontend.Length < 1024)
            {
                throw new InvalidDataException("The compiled frontend is unexpectedly small.");
            }
        }

        private static void DeployAtomically(
            string runtimePackage,
            ResolvedInstallPaths paths,
            CancellationToken cancellationToken)
        {
            Directory.CreateDirectory(paths.PluginsDirectory);
            string suffix = Guid.NewGuid().ToString("N");
            string stagedTarget = Path.Combine(
                paths.PluginsDirectory,
                "." + InstallerConstants.PluginName + ".install-" + suffix);
            string backupTarget = Path.Combine(
                paths.PluginsDirectory,
                "." + InstallerConstants.PluginName + ".backup-" + suffix);

            bool existingMoved = false;
            bool stagedMoved = false;

            try
            {
                SafeFileSystem.CopyDirectory(runtimePackage, stagedTarget);
                ValidateRuntimePackage(stagedTarget);
                cancellationToken.ThrowIfCancellationRequested();

                if (Directory.Exists(paths.PluginDirectory))
                {
                    Directory.Move(paths.PluginDirectory, backupTarget);
                    existingMoved = true;
                }

                Directory.Move(stagedTarget, paths.PluginDirectory);
                stagedMoved = true;
            }
            catch
            {
                try
                {
                    if (stagedMoved && Directory.Exists(paths.PluginDirectory))
                    {
                        SafeFileSystem.DeleteDirectorySafely(paths.PluginDirectory);
                    }
                    else if (Directory.Exists(stagedTarget))
                    {
                        SafeFileSystem.DeleteDirectorySafely(stagedTarget);
                    }

                    if (existingMoved && Directory.Exists(backupTarget) && !Directory.Exists(paths.PluginDirectory))
                    {
                        Directory.Move(backupTarget, paths.PluginDirectory);
                    }
                }
                catch
                {
                    // Preserve the original exception; the backup remains beside the target.
                }

                throw;
            }

            if (stagedMoved && existingMoved && Directory.Exists(backupTarget))
            {
                try
                {
                    SafeFileSystem.DeleteDirectorySafely(backupTarget);
                }
                catch
                {
                    // Installation is already complete. Leave a recoverable backup
                    // rather than rolling back after a cleanup-only failure.
                }
            }
        }

        private static string ComputeSha256(string filePath)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream stream = File.OpenRead(filePath))
            {
                byte[] hash = sha.ComputeHash(stream);
                StringBuilder builder = new StringBuilder(hash.Length * 2);
                foreach (byte value in hash)
                {
                    builder.Append(value.ToString("x2", CultureInfo.InvariantCulture));
                }
                return builder.ToString();
            }
        }

        private static string FormatBytes(long bytes)
        {
            if (bytes >= 1024L * 1024L)
            {
                return (bytes / (1024d * 1024d)).ToString("0.0", CultureInfo.InvariantCulture) + " MB";
            }
            if (bytes >= 1024L)
            {
                return (bytes / 1024d).ToString("0.0", CultureInfo.InvariantCulture) + " KB";
            }
            return bytes.ToString(CultureInfo.InvariantCulture) + " bytes";
        }

        private void Report(string message, int percent, bool indeterminate)
        {
            if (progress != null)
            {
                progress.Report(new InstallerProgressInfo(message, percent, indeterminate));
            }
        }
    }
}
