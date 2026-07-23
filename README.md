# Vortex Launch Bridge

A Windows-first [Millennium](https://github.com/SteamClientHomebrew/Millennium) plugin for coordinating future Steam launches with Vortex.

The repository currently contains Phase 0 through Phase 2: the plugin scaffold, Lua backend lifecycle, frontend-to-backend health check, structured diagnostic logging, observation-only Steam launch instrumentation, and a read-only Vortex backend probe.

Phase 2 does not cancel, delay, continue, or initiate Steam launches. It shows no launch modal and does not activate games or profiles.

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

## Verify Phase 0 through Phase 2 manually

1. Run `bun run build` and confirm it exits successfully.
2. Start Steam and enable the plugin in Millennium.
3. Confirm the plugin appears as **Vortex Launch Bridge** version `0.3.0`.
4. In Steam's frontend developer console, find a `[VLB]` record with event `backend.health.ok`.
5. In the Millennium plugin log, confirm `backend.loaded`, `backend.health.requested`, and `frontend.loaded` records include component and version fields.
6. Confirm a `[VLB]` `launch.instrumentation.started` record lists the registered observation hooks.
7. Launch a Steam game and confirm behavior is unchanged while `launch.callback.observed` records are produced.
8. Disable or reload the plugin and confirm every observation handle produces `launch.hook.unregistered`.
9. Confirm `frontend.unloaded` and `backend.unloaded` are logged without an error.
10. Open the plugin panel and confirm **Vortex installation** reports either a detected source or a clear absent result.
11. If Vortex is in a custom location, enter the complete `Vortex.exe` path and select **Save override**. Clear it to return to registry/known-path detection.
12. Close Vortex, select **Run read-only probe**, and confirm the panel reports the installed version, captured state-output format, profile count, and discovered-game count.
13. Start Vortex and run the probe again. Confirm the version check is harmless and the state query is skipped rather than forwarded to the running Vortex instance.
14. Confirm normal `[VLB]` logs contain counts, exit codes, timeout flags, and redaction markers—but no executable paths, profile names, game paths, stdout, or stderr.

The health response is validated in TypeScript before use and reports the backend platform, architecture, plugin version, Millennium version, and backend start time.

The full route matrix and the fields to capture are in [docs/launch-hook-findings.md](docs/launch-hook-findings.md).
Vortex CLI findings, state shapes, safety rules, and the remaining runtime test are in [docs/vortex-probe-findings.md](docs/vortex-probe-findings.md).

## Phase 2 settings

The backend settings model is stored at `%LOCALAPPDATA%\VortexLaunchBridge\settings.json`. The Phase 2 panel exposes only the Vortex executable override. The model already reserves the later settings described in the project context, but Phase 2 does not use remembered choices, mappings, activation, or custom launch targets.

The probe launches Vortex directly with a Windows process API—never through `cmd.exe`—and enforces a timeout while separately capturing stdout and stderr. Its allowlist contains only:

```text
--version
--get persistent.profiles
--get settings.profiles.lastActiveProfile
--get settings.gameMode.discovered
```

There is no `--set`, `--del`, direct Vortex database access, recursive drive scan, or profile/game activation in Phase 2.

## Scope

Phase 3 Steam-to-Vortex game matching has intentionally not been started. Runtime launch order is not yet claimed or assumed. See [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) for the planned phases and required launch semantics.
