# Vortex Launch Bridge installer

`VortexLaunchBridgeInstaller.exe` is a small Windows Forms bootstrap installer
for users who want to install the plugin directly from its GitHub repository
instead of the Steam Homebrew Plugin Database.

## Behavior

- Detects Steam through the current-user and machine registry locations.
- Resolves Millennium 3.x plugins to `<Steam>\millennium\plugins`.
- Accepts a selected Steam directory, Millennium directory, plugins directory,
  or existing `vortex-launch-bridge` directory.
- Downloads an immutable snapshot of the current `main` commit from
  `WoahItsJeebus/MSVB`.
- Uses a compatible system Node.js installation when one is available.
- Otherwise downloads the latest Node.js 20 Windows archive from
  `nodejs.org`, verifies it against the published SHA-256 checksum, and caches
  the extracted portable toolchain under
  `%LOCALAPPDATA%\VortexLaunchBridge\InstallerCache`.
- Installs the exact `pnpm` version pinned by `package.json`, runs
  `pnpm install --frozen-lockfile`, and runs the repository's production build.
- Validates the plugin ID and required runtime files before changing the
  installed plugin.
- Stages and swaps the plugin directory so a download or build failure leaves
  the existing installation unchanged.
- Deletes only
  `<Millennium>\plugins\vortex-launch-bridge`; locally stored plugin settings
  are intentionally preserved.

Steam must be fully closed before Install/Repair or Delete. Current Millennium
installations grant users access to their plugin directory, so the installer
runs with the caller's normal Windows permissions instead of elevating the
download and build toolchain.

## Build

From a Windows PowerShell prompt at the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-installer.ps1
```

The release-ready executable is written to:

```text
artifacts\VortexLaunchBridgeInstaller.exe
```

The build uses the .NET Framework compiler included with Windows/.NET
Framework 4.8 and runs the path-safety test suite unless `-SkipTests` is
provided.

An optional end-to-end test downloads and builds the current repository into an
isolated temporary Millennium layout:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-installer-integration.ps1
```

## Release notes

The generated executable is not code-signed. Windows SmartScreen may therefore
warn users, especially for a newly published release. Authenticode signing is
recommended before broad distribution.
