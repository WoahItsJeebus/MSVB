# Vortex Launch Bridge

A Windows-first [Millennium](https://github.com/SteamClientHomebrew/Millennium) plugin for coordinating Steam launches with Vortex-managed games.

The repository currently contains Phase 0 through Phase 4: plugin lifecycle and health checks, structured logging, Steam launch diagnostics, read-only Vortex detection/state probing, deterministic Steam-to-Vortex matching, and one narrow Steam modal/continuation route.

Phase 5 has not started. The plugin does not activate Vortex games or profiles, wait for deployment, or launch a game through Vortex.

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

## Phase 4 behavior

Phase 4 intercepts only direct `SteamClient.Apps.RunGame` calls whose launch source is `_2ftLibraryDetails`. All other launch sources pass through unchanged.

The complete original tuple is held in memory:

```text
Steam AppID
launch options
typed third RunGame parameter
launch source
```

When no Vortex profiles match—or when checking fails—the exact tuple is replayed once through a short-lived, one-shot bypass.

When profiles match, the Steam-native modal offers exactly:

- `Launch with Vortex`
- `Continue launching with Steam...`

Choosing Steam replays the request once. Closing the modal, pressing Escape, or using another cancel gesture cancels the pending request. Selecting **Launch with Vortex** also cancels the held Steam request in Phase 4; Vortex activation is intentionally deferred to Phase 5.

The modal does not claim that continuing with Steam changes or disables anything Vortex may already have deployed.

## Verify Phase 0 through Phase 4 manually

1. Run `bun run build` and confirm it exits successfully.
2. Start Steam and enable the plugin.
3. Confirm the plugin appears as **Vortex Launch Bridge** version `0.5.0`.
4. Confirm backend health succeeds and Phase 1 observers register.
5. Confirm Vortex detection and the read-only probe behave as documented in [vortex-probe-findings.md](docs/vortex-probe-findings.md).
6. Confirm Steam path resolution and deterministic matching behave as documented in [game-matching-findings.md](docs/game-matching-findings.md).
7. Confirm `launch.interception.started` reports phase `4`, route `RunGame`, and source `_2ftLibraryDetails`.
8. From Library Details, launch a game without matching Vortex profiles. Confirm no modal appears and Steam starts it once.
9. Launch a matching game with profiles. Confirm exactly one modal appears.
10. Select **Continue launching with Steam...** and confirm Steam starts the game exactly once.
11. Repeat and dismiss with the close icon, then with Escape. Confirm the pending launch is cancelled.
12. Repeat and select **Launch with Vortex**. Confirm no Steam launch or Vortex activation occurs in Phase 4.
13. Rapidly click Play twice and confirm only one modal appears.
14. Disable the plugin while a request is checking or prompting. Confirm the held request fails open once and every hook unregisters.
15. Test the other Phase 1 launch routes and confirm Phase 4 leaves unsupported sources unchanged.

The full Phase 4 state machine, safety rules, structured events, and manual route matrix are in [launch-continuation-findings.md](docs/launch-continuation-findings.md).

## Vortex state and matching

The backend settings model is stored at `%LOCALAPPDATA%\VortexLaunchBridge\settings.json`. The panel exposes the Vortex executable override and a validated `steamAppIdOverrides` mapping.

The read-only Vortex command allowlist remains:

```text
--version
--get persistent.profiles
--get settings.profiles.lastActiveProfile
--get settings.gameMode.discovered
```

There is no `--set`, `--del`, direct Vortex database access, recursive drive scan, or profile/game activation.

Phase 3 matching order remains configured override, explicit Vortex Steam ID, exact installation path, exact executable path, then no match. Ambiguous candidates and title-only matches are rejected.

## Tests

```powershell
lua tests/vortex_parsers.lua
lua tests/game_matching.lua
npm.cmd run test:phase4
```

`tests/launch_continuation.ts` covers exact replay and one-shot bypass behavior. Its runner compiles only the pure continuation modules into the ignored `.millennium` build directory before executing them with Node.

## Scope

Phase 5 Vortex profile activation has intentionally not been started. There is no profile picker, Vortex `--game`/`--profile` command, activation or deployment wait, Vortex launch target, or post-activation game launch. See [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) for the remaining phases and required launch semantics.
