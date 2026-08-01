<p align="center">
   <a href="https://github.com/WoahItsJeebus/MSVB/releases/download/Installer/VortexLaunchBridgeInstaller.exe">
      <img alt="GitHub Release" src="https://img.shields.io/github/v/release/WoahItsJeebus/MSVB?sort=semver&filter=Installer&display_name=tag&style=for-the-badge&label=Download">
   </a>
</p>


# Vortex Launch Bridge

[![Version](https://img.shields.io/badge/version-1.0.5-2ea3f2)](CHANGELOG.md)
[![Platform](https://img.shields.io/badge/platform-Windows-0078d4)](#requirements)
[![Millennium](https://img.shields.io/badge/Millennium-plugin-6b5cff)](https://steambrew.app/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Vortex Launch Bridge is a [Millennium](https://steambrew.app/) plugin that coordinates Steam launches with Vortex-managed profiles. When you start an eligible game, it lets you activate a Vortex profile first, continue the original Steam launch, or cancel.

## Features

- Detects Vortex and reads its supported game/profile state without editing it.
- Warms a background cache at plugin startup so eligible launch prompts appear without a long lookup delay.
- Uses the game's Steam name and profile count in a native, theme-aware Steam confirmation dialog.
- Activates a selected Vortex profile in Vortex's minimized background mode and waits for deployment confirmation before starting the configured target.
- Preserves the exact intercepted Steam launch request when you choose **Continue launching with Steam...**
- Supports optional remembered choices, preferred profiles, custom executables, custom arguments, and exact Steam AppID-to-Vortex game mappings.
- Fails open before interception whenever eligibility cannot be established safely.
- Keeps settings and diagnostic data local and redacts paths and launch arguments from normal logs.

> [!IMPORTANT]
> **Continue launching with Steam... is not a "vanilla mode."** It replays Steam's original launch request, but it does not remove or change anything Vortex may already have deployed.

## Requirements

- Windows 10 or Windows 11
- Desktop Steam
- [Millennium](https://docs.steambrew.app/users/installing)
- [Vortex](https://www.nexusmods.com/about/vortex/)

The current release has been tested with Millennium 3.3.1 and Vortex 2.3.0.

## Installation

### Millennium plugin catalog

Once the plugin is listed in the Steam Homebrew plugin catalog:

1. Open **Steam > Millennium Settings > Plugins**.
2. Choose **Install a plugin**.
3. Enter the plugin ID `<Eventual_Steambrew_ID_Here>` and install it.
4. Restart Steam when prompted.

### Direct GitHub installer

For a direct installation that does not use the Steam Homebrew Plugin Database:

1. Download `VortexLaunchBridgeInstaller.exe` from the
   [latest GitHub release](https://github.com/WoahItsJeebus/MSVB/releases/latest).
2. Run the installer and confirm the detected Millennium directory.
3. Choose **Install/Repair**. The installer force-closes Steam and its web
   helpers first if they are running.
4. Restart Steam and enable the plugin in
   **Steam > Millennium Settings > Plugins** if necessary.

The installer downloads an immutable snapshot of the latest `main` commit,
installs the repository's pinned build dependencies in a temporary workspace,
runs the production build, validates the runtime package, and atomically
installs it under Millennium's user plugins directory. It also provides a
**Delete** action that removes only this plugin's installation folder.

### Development installation

Use this method for an unreleased build or local development.

1. Install [Node.js 20](https://nodejs.org/) and [pnpm 10](https://pnpm.io/installation):

   ```powershell
   npm install --global pnpm@10.34.5
   ```

2. Clone and build the repository:

   ```powershell
   git clone https://github.com/WoahItsJeebus/MSVB.git
   Set-Location MSVB
   pnpm install
   pnpm run build
   ```

3. Close Steam completely.
4. Open an elevated PowerShell window in the checkout and create a directory junction:

   ```powershell
   New-Item `
     -ItemType Junction `
     -Path 'C:\Program Files (x86)\Steam\millennium\plugins\vortex-launch-bridge' `
     -Target (Resolve-Path '.')
   ```

   Adjust the Steam path if your Millennium installation is elsewhere. The destination must not already exist.

5. Start Steam. Rebuild and restart Steam after changing plugin code.

The junction links the development checkout directly to Millennium; it does not duplicate the repository.

## Using the plugin

Vortex Launch Bridge scans Vortex's read-only state in the background when Steam starts. Launch a Steam game that Vortex manages and that has at least one valid Vortex profile. The prompt offers three actions:

- **Launch with Vortex** activates a profile, waits for deployment confirmation, and starts the configured launch target.
- **Continue launching with Steam...** replays the exact Steam request without changing Vortex state.
- **Cancel** abandons the intercepted request.

For the most reliable profile activation with Vortex 2.3.0, close Vortex before choosing **Launch with Vortex**. Vortex currently applies command-line profile selection during a cold start but may ignore those arguments when forwarding them to an already-running instance.

If activation times out, **Retry** force-closes all running Vortex instances and
repeats the same held profile activation as a cold start. Steam remains held
until the retried activation is confirmed, continued through Steam, or cancelled.

## Settings

Open **Steam > Millennium Settings > Plugins > Vortex Launch Bridge** to configure:

- whether every eligible launch asks first;
- opt-in remembered launch choices per game;
- diagnostic launch logging;
- the Vortex activation timeout;
- a preferred Vortex profile for each Steam AppID;
- an optional custom executable and arguments after activation;
- Vortex executable detection or an explicit override;
- read-only Vortex and game-matching diagnostics;
- exact Steam AppID-to-Vortex game-ID overrides.

Settings are stored locally at:

```text
%LOCALAPPDATA%\VortexLaunchBridge\settings.json
```

## Troubleshooting

### No launch prompt appears

- Confirm the plugin is enabled and Steam was restarted after installation.
- Open the plugin settings and run **Detect Vortex** and **Run read-only probe**.
- Confirm Vortex manages the game and has at least one valid profile for it.
- If automatic matching fails, configure an exact Steam AppID-to-Vortex game-ID override.

### Vortex activation times out

- Fully exit Vortex, including its notification-area process, and try again.
- Increase the activation timeout in the plugin settings, up to 25 seconds, if deployment normally takes longer.
- Verify the selected profile still exists and deploys successfully from Vortex itself.

### A terminal flashes while Vortex starts

Vortex 2.3.0 starts its bundled console-subsystem `.NET` probe, its
`fsutil dirty query` administrator check, and some shell-backed startup tools
without Node's `windowsHide` option. With Vortex fully exited, run the guarded
compatibility repair from an administrator PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\patch-vortex-dotnetprobe.ps1
```

The script validates Vortex's ASAR layout and affected file hashes, removes the
command shell from the administrator check, and creates a complete
hash-verified archive backup under
`%LOCALAPPDATA%\VortexLaunchBridge\Backups`, inserts the missing option without
changing any file size, updates the corresponding integrity hashes, and
verifies the result. Vortex's signed probe remains untouched. A later Vortex
update may restore the official files; rerun the repair only if the flash
returns.

### Logs

The backend log is normally written to:

```text
<Steam>\millennium\logs\vortex-launch-bridge_log.log
```

Millennium frontend output is written to:

```text
<Steam>\logs\webhelper_js.txt
```

Enable diagnostic launch logging only while investigating a problem. Before sharing logs, review them for information specific to your system.

If the issue persists, open a [bug report](https://github.com/WoahItsJeebus/MSVB/issues/new?template=bug_report.yml) with the plugin, Millennium, Vortex, and Windows versions plus the smallest relevant log excerpt.

## Safety and privacy

The plugin does not:

- edit Vortex's profile or deployment state directly;
- use Vortex state mutation commands;
- scan unrelated drives;
- inject into game processes;
- remove deployed mods when continuing through Steam;
- send telemetry or settings over the network.

The optional terminal-flash compatibility script changes Vortex's `app.asar`
renderer only when the user explicitly runs it and always retains the complete
original archive in the local backup directory above.

Process launches avoid a command shell, custom arguments use bounded parsing, settings are validated before use, and asynchronous work is bounded by explicit timeouts. See [Architecture](docs/architecture.md) for the design and trust boundaries.

## Development

Prerequisites are Node.js 20, pnpm 10, Windows PowerShell, and Lua 5.1 on `PATH`.

```powershell
pnpm install
pnpm run build
pnpm test
```

`pnpm test` runs the complete launch, activation, settings, parsing, caching, matching, and process-runner regression suite. If `backend/util/process_shell.cs` changes, rebuild its committed Windows-subsystem helper with:

```powershell
pnpm run build:process-shell
pnpm test
```

Additional references:

- [Architecture and safety boundaries](docs/architecture.md)
- [Testing guide](docs/testing.md)
- [Release checklist](docs/release-checklist.md)
- [Detailed implementation findings](docs/)
- [Changelog](CHANGELOG.md)

## Contributing

Bug reports and focused pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes. Please report security-sensitive issues according to [SECURITY.md](SECURITY.md).

## License

Vortex Launch Bridge is available under the [MIT License](LICENSE).

Steam, Valve, Nexus Mods, and Vortex are trademarks of their respective owners. This independent project is not affiliated with or endorsed by Valve Corporation or Nexus Mods.
