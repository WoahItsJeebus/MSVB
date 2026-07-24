# Vortex Launch Bridge

[![Version](https://img.shields.io/badge/version-0.7.15-2ea3f2)](CHANGELOG.md)
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
3. Enter the plugin ID `vortex-launch-bridge` and install it.
4. Restart Steam when prompted.

### Development installation

Use this method for an unreleased build or local development.

1. Install [Node.js 20](https://nodejs.org/) and pnpm 10:

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
- Increase the activation timeout in the plugin settings if deployment normally takes longer.
- Verify the selected profile still exists and deploys successfully from Vortex itself.

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
