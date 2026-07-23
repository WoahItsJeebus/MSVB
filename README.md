# Vortex Launch Bridge

A Windows-first [Millennium](https://github.com/SteamClientHomebrew/Millennium) plugin for coordinating future Steam launches with Vortex.

The repository currently contains Phase 0 through Phase 3: the plugin scaffold, Lua backend lifecycle, frontend-to-backend health check, structured diagnostic logging, observation-only Steam launch instrumentation, a read-only Vortex backend probe, Steam manifest resolution, and deterministic Steam-to-Vortex game matching.

Phase 3 does not cancel, delay, continue, or initiate Steam launches. It shows no launch modal and does not activate games or profiles.

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

## Verify Phase 0 through Phase 3 manually

1. Run `bun run build` and confirm it exits successfully.
2. Start Steam and enable the plugin in Millennium.
3. Confirm the plugin appears as **Vortex Launch Bridge** version `0.4.0`.
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
15. Close Vortex, enter an installed Steam AppID in **Phase 3 game matching**, and select **Resolve Steam path**.
16. Confirm the panel reports `steam-client` when Steam exposes the containing library, or `manifest` when the registry/library-folder fallback resolves it.
17. Select **Match Vortex game** and confirm an exact discovered path returns the expected Vortex game ID and profile count.
18. Save a valid Steam AppID to Vortex game-ID mapping and confirm matching reports `configured`.
19. Save an invalid Vortex game ID and confirm the match is rejected instead of guessing another game, then clear the mapping.
20. Start Vortex and confirm matching fails safely because the read-only state query is skipped.
21. Launch a Steam game and confirm the existing Phase 1 instrumentation remains observation-only.

The health response is validated in TypeScript before use and reports the backend platform, architecture, plugin version, Millennium version, and backend start time.

The full route matrix and the fields to capture are in [docs/launch-hook-findings.md](docs/launch-hook-findings.md).
Vortex CLI findings, state shapes, safety rules, and the remaining runtime test are in [docs/vortex-probe-findings.md](docs/vortex-probe-findings.md).
Steam resolution, path normalization, matching order, ambiguity handling, and Phase 3 manual checks are in [docs/game-matching-findings.md](docs/game-matching-findings.md).

## Phase 3 settings

The backend settings model is stored at `%LOCALAPPDATA%\VortexLaunchBridge\settings.json`. The panel exposes the Vortex executable override and a validated `steamAppIdOverrides` mapping. Other later settings remain reserved and unused; Phase 3 does not use remembered launch choices, activation, or custom launch targets.

The probe launches Vortex directly with a Windows process API—never through `cmd.exe`—and enforces a timeout while separately capturing stdout and stderr. Its allowlist contains only:

```text
--version
--get persistent.profiles
--get settings.profiles.lastActiveProfile
--get settings.gameMode.discovered
```

There is no `--set`, `--del`, direct Vortex database access, recursive drive scan, or profile/game activation.

Phase 3 prefers `SteamClient.InstallFolder.GetInstallFolders()` as a library hint and validates the exact app manifest in Lua. Its fallback reads only Steam's configured library folders and exact `appmanifest_<appid>.acf` filenames. Matching order is configured override, explicit Vortex Steam ID, exact installation path, exact executable path, then no match. Ambiguous candidates and title-only matches are rejected.

## Tests

```powershell
lua tests/vortex_parsers.lua
lua tests/game_matching.lua
```

## Scope

Phase 4 Steam modal and safe continuation work has intentionally not been started. Runtime launch order is not yet claimed or assumed. There is no launch cancellation, prompt, continuation bypass, or Vortex activation. See [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) for the planned phases and required launch semantics.
