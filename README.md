# Vortex Launch Bridge

A Windows-first [Millennium](https://github.com/SteamClientHomebrew/Millennium) plugin for coordinating future Steam launches with Vortex.

The repository currently contains Phase 0 only: the plugin scaffold, Lua backend lifecycle, frontend-to-backend health check, and structured diagnostic logging. It does not inspect, delay, cancel, or replace Steam launches, and it does not interact with Vortex yet.

## Requirements

- Windows 10 or newer
- The desktop Steam client with Millennium installed
- [Git](https://git-scm.com/downloads)
- [Bun](https://bun.sh/)

This scaffold is based on the official Millennium PluginTemplate at commit `fbe04927f622cbb60909f269f687434574987ff3` (2026-06-08).

## Install dependencies

From PowerShell in the repository root:

```powershell
bun install
```

## Build

Create a development or production bundle:

```powershell
bun run dev
bun run build
```

Build output is written to `.millennium/Dist`.

## Link the development checkout to Millennium

Millennium accepts a directory junction from Steam's `plugins` directory to this checkout. Run PowerShell as a user permitted to create the junction:

```powershell
$steamPath = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam').InstallPath
$pluginsPath = Join-Path $steamPath 'plugins'
$checkoutPath = (Get-Location).Path
$linkPath = Join-Path $pluginsPath 'vortex-launch-bridge'

New-Item -ItemType Directory -Force -Path $pluginsPath
New-Item -ItemType Junction -Path $linkPath -Target $checkoutPath
```

If Steam is installed elsewhere, replace `$steamPath` with that installation directory. Restart Steam after creating the link, then enable **Vortex Launch Bridge** in Millennium.

## Verify Phase 0 manually

1. Run `bun run build` and confirm it exits successfully.
2. Start Steam and enable the plugin in Millennium.
3. Confirm the plugin appears as **Vortex Launch Bridge** version `0.1.0`.
4. In Steam's frontend developer console, find a `[VLB]` record with event `backend.health.ok`.
5. In the Millennium plugin log, confirm `backend.loaded`, `backend.health.requested`, and `frontend.loaded` records include component and version fields.
6. Disable or reload the plugin and confirm `frontend.unloaded` and `backend.unloaded` are logged without an error.
7. Launch a Steam game and confirm behavior is unchanged. Phase 0 registers no Steam launch hooks.

The health response is validated in TypeScript before use and reports the backend platform, architecture, plugin version, Millennium version, and backend start time.

## Scope

Phase 1 launch-hook instrumentation has intentionally not been started. See [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) for the planned phases and required launch semantics.
