using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace VortexLaunchBridge.Installer
{
    internal static class InstallerIntegrationTests
    {
        private static int Main()
        {
            try
            {
                RunAsync().GetAwaiter().GetResult();
                Console.WriteLine("Installer integration test passed.");
                return 0;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("Installer integration test failed:");
                Console.Error.WriteLine(ex);
                return 1;
            }
        }

        private static async Task RunAsync()
        {
            string testRoot = Path.Combine(
                Path.GetTempPath(),
                "VortexLaunchBridgeInstallerIntegration",
                Guid.NewGuid().ToString("N"));
            string millennium = Path.Combine(testRoot, "millennium");
            string plugins = Path.Combine(millennium, "plugins");
            string sibling = Path.Combine(plugins, "preserve-sibling");

            Directory.CreateDirectory(Path.Combine(millennium, "bin"));
            Directory.CreateDirectory(Path.Combine(millennium, "lib"));
            Directory.CreateDirectory(plugins);
            Directory.CreateDirectory(sibling);
            File.WriteAllText(Path.Combine(sibling, "keep.txt"), "keep");

            try
            {
                ResolvedInstallPaths paths;
                string error;
                if (!MillenniumPathResolver.TryResolve(millennium, out paths, out error))
                {
                    throw new InvalidOperationException(error);
                }

                Progress<InstallerProgressInfo> progress = new Progress<InstallerProgressInfo>(
                    delegate(InstallerProgressInfo info)
                    {
                        if (info != null && !String.IsNullOrWhiteSpace(info.Message))
                        {
                            Console.WriteLine(info.Message);
                        }
                    });

                using (VortexPluginInstallerService service = new VortexPluginInstallerService(progress))
                {
                    InstallOperationResult result = await service.InstallOrRepairAsync(
                        paths,
                        CancellationToken.None,
                        false);

                    Assert(!String.IsNullOrWhiteSpace(result.PluginVersion), "Installed version is missing.");
                    Assert(result.Commit != null && result.Commit.Length == 40, "Source commit is invalid.");
                    Assert(File.Exists(Path.Combine(
                        paths.PluginDirectory,
                        ".millennium",
                        "Dist",
                        "index.js")), "Compiled frontend was not deployed.");
                    Assert(File.Exists(Path.Combine(
                        paths.PluginDirectory,
                        "backend",
                        "main.lua")), "Backend was not deployed.");
                    Assert(File.Exists(Path.Combine(
                        paths.PluginDirectory,
                        "scripts",
                        "patch-vortex-dotnetprobe.ps1")), "Terminal repair was not deployed.");
                    Assert(File.Exists(Path.Combine(sibling, "keep.txt")), "Install modified a sibling plugin.");

                    service.DeletePlugin(paths);
                    Assert(!Directory.Exists(paths.PluginDirectory), "Delete did not remove the plugin.");
                    Assert(File.Exists(Path.Combine(sibling, "keep.txt")), "Delete modified a sibling plugin.");
                }
            }
            finally
            {
                if (Directory.Exists(testRoot))
                {
                    SafeFileSystem.DeleteDirectorySafely(testRoot);
                }
            }
        }

        private static void Assert(bool condition, string message)
        {
            if (!condition)
            {
                throw new InvalidOperationException(message);
            }
        }
    }
}
