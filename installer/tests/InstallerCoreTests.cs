using System;
using System.IO;

namespace VortexLaunchBridge.Installer
{
    internal static class InstallerCoreTests
    {
        private static int failures;

        private static int Main()
        {
            string testRoot = Path.Combine(
                Path.GetTempPath(),
                "VortexLaunchBridgeInstallerTests",
                Guid.NewGuid().ToString("N"));

            try
            {
                Directory.CreateDirectory(testRoot);
                TestPathResolution(testRoot);
                TestUnsafePathRejection(testRoot);
                TestSafeDelete(testRoot);
                TestCommandLineQuoting();
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("Unexpected test failure: " + ex);
                failures++;
            }
            finally
            {
                try
                {
                    SafeFileSystem.DeleteDirectorySafely(testRoot);
                }
                catch
                {
                    failures++;
                }
            }

            if (failures == 0)
            {
                Console.WriteLine("Installer core tests passed.");
                return 0;
            }

            Console.Error.WriteLine(failures + " installer core test(s) failed.");
            return 1;
        }

        private static void TestPathResolution(string testRoot)
        {
            string steam = Path.Combine(testRoot, "Steam");
            string millennium = Path.Combine(steam, "millennium");
            string plugins = Path.Combine(millennium, "plugins");
            Directory.CreateDirectory(Path.Combine(millennium, "bin"));
            Directory.CreateDirectory(Path.Combine(millennium, "lib"));
            Directory.CreateDirectory(plugins);

            AssertResolves(steam, millennium, plugins, "Steam root");
            AssertResolves(millennium, millennium, plugins, "Millennium root");
            AssertResolves(plugins, millennium, plugins, "plugins root");
            AssertResolves(
                Path.Combine(plugins, InstallerConstants.PluginName),
                millennium,
                plugins,
                "plugin root");
        }

        private static void TestUnsafePathRejection(string testRoot)
        {
            string unrelated = Path.Combine(testRoot, "unrelated");
            Directory.CreateDirectory(unrelated);

            ResolvedInstallPaths resolved;
            string error;
            bool success = MillenniumPathResolver.TryResolve(unrelated, out resolved, out error);
            Assert(!success, "Unrelated folders must be rejected.");
            Assert(!String.IsNullOrWhiteSpace(error), "Rejected paths must include an explanation.");

            Assert(
                !MillenniumPathResolver.IsSafePluginTarget(
                    unrelated,
                    Path.Combine(testRoot, InstallerConstants.PluginName)),
                "Plugin targets outside the selected plugins directory must be rejected.");
        }

        private static void TestSafeDelete(string testRoot)
        {
            string parent = Path.Combine(testRoot, "delete-test");
            string plugin = Path.Combine(parent, InstallerConstants.PluginName);
            string sibling = Path.Combine(parent, "keep-me");
            Directory.CreateDirectory(Path.Combine(plugin, "nested"));
            Directory.CreateDirectory(sibling);
            File.WriteAllText(Path.Combine(plugin, "nested", "delete.txt"), "delete");
            File.WriteAllText(Path.Combine(sibling, "keep.txt"), "keep");

            SafeFileSystem.DeleteDirectorySafely(plugin);

            Assert(!Directory.Exists(plugin), "Safe delete must remove the selected plugin directory.");
            Assert(File.Exists(Path.Combine(sibling, "keep.txt")), "Safe delete must preserve sibling data.");
        }

        private static void TestCommandLineQuoting()
        {
            Assert(
                WindowsCommandLine.QuoteArgument("plain") == "plain",
                "Plain arguments should not be quoted.");
            Assert(
                WindowsCommandLine.QuoteArgument("two words") == "\"two words\"",
                "Arguments containing spaces should be quoted.");
            Assert(
                WindowsCommandLine.QuoteArgument(String.Empty) == "\"\"",
                "Empty arguments should be represented explicitly.");
            Assert(
                WindowsCommandLine.QuoteArgument("C:\\ends with slash\\")
                    == "\"C:\\ends with slash\\\\\"",
                "Trailing slashes in quoted arguments must be escaped.");
        }

        private static void AssertResolves(
            string selected,
            string expectedMillennium,
            string expectedPlugins,
            string description)
        {
            ResolvedInstallPaths resolved;
            string error;
            bool success = MillenniumPathResolver.TryResolve(selected, out resolved, out error);
            Assert(success, description + " should resolve. " + error);
            if (!success)
            {
                return;
            }

            Assert(
                String.Equals(
                    MillenniumPathResolver.NormalizeDirectory(expectedMillennium),
                    resolved.MillenniumDirectory,
                    StringComparison.OrdinalIgnoreCase),
                description + " resolved the wrong Millennium directory.");
            Assert(
                String.Equals(
                    MillenniumPathResolver.NormalizeDirectory(expectedPlugins),
                    resolved.PluginsDirectory,
                    StringComparison.OrdinalIgnoreCase),
                description + " resolved the wrong plugins directory.");
        }

        private static void Assert(bool condition, string message)
        {
            if (condition)
            {
                return;
            }

            Console.Error.WriteLine("FAIL: " + message);
            failures++;
        }
    }
}
