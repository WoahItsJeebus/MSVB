# Vortex Launch Bridge

A Windows-first [Millennium](https://github.com/SteamClientHomebrew/Millennium) plugin for coordinating Steam launches with Vortex-managed games.

The repository currently contains Phase 0 through Phase 5: plugin lifecycle and health checks, structured logging, Steam launch diagnostics, read-only Vortex detection/state probing, deterministic Steam-to-Vortex matching, one narrow Steam modal/continuation route, profile selection, confirmed Vortex activation, and post-activation Steam launch.

Phase 6 has not started. The plugin does not support additional interception routes, remembered choices, custom launch tools, or a settings UI.

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

## Phase 5 behavior

Phase 5 retains the deliberately narrow Phase 4 interception boundary: only direct `SteamClient.Apps.RunGame` calls whose launch source is `_2ftLibraryDetails` are eligible. All other launch sources pass through unchanged.

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

Choosing Steam replays the request once. Closing the launch-choice modal, pressing Escape, or using another cancel gesture cancels the pending request.

Choosing **Launch with Vortex** activates the only matching profile directly or opens a profile picker when several profiles exist. The backend starts Vortex with fixed `--game` and `--profile` arguments, then tails only newly written Vortex log data for the exact selected game/profile completion event. Vortex emits that event after its profile deployment chain completes. Only then does the frontend replay the preserved Steam request through the one-shot bypass.

While activation is pending, a progress dialog can cancel the held Steam launch. If activation exits early or times out, the error dialog offers exactly:

- `Continue launching with Steam...`
- `Cancel`

The timeout path warns that Vortex may still finish the requested profile change. The modal does not claim that continuing with Steam changes or disables anything Vortex may already have deployed.

Current Vortex 2.3.0 accepts `--profile` on a cold start, but its second-instance handler does not apply profile/game arguments to an already-running primary instance. The bridge therefore requires a fresh Vortex start for a confirmed activation. If Vortex starts in the gap between matching and activation, the request times out safely into the error dialog instead of starting the game without confirmation.

See [vortex-activation-findings.md](docs/vortex-activation-findings.md) for the readiness contract and current Vortex limitation.

## Verify Phase 0 through Phase 5 manually

1. Run `bun run build` and confirm it exits successfully.
2. Start Steam and enable the plugin.
3. Confirm the plugin appears as **Vortex Launch Bridge** version `0.6.0`.
4. Confirm backend health succeeds and Phase 1 observers register.
5. Confirm Vortex detection and the read-only probe behave as documented in [vortex-probe-findings.md](docs/vortex-probe-findings.md).
6. Confirm Steam path resolution and deterministic matching behave as documented in [game-matching-findings.md](docs/game-matching-findings.md).
7. Confirm `launch.interception.started` reports phase `5`, route `RunGame`, and source `_2ftLibraryDetails`.
8. From Library Details, launch a game without matching Vortex profiles. Confirm no modal appears and Steam starts it once.
9. Launch a matching game with profiles. Confirm exactly one modal appears.
10. Select **Continue launching with Steam...** and confirm Steam starts the game exactly once.
11. Repeat and dismiss with the close icon, then with Escape. Confirm the pending launch is cancelled.
12. With Vortex closed, repeat and select **Launch with Vortex** for a game with one profile. Confirm Vortex starts, the progress dialog remains until deployment confirmation, and Steam starts the preserved request exactly once.
13. Repeat with several profiles. Confirm the profile picker appears and the selected profile becomes active before Steam starts the game.
14. Start Vortex manually while the initial launch-choice modal is open, then select **Launch with Vortex**. Confirm the activation times out into the error dialog with `Continue launching with Steam...` and `Cancel`.
15. Test each error choice. Confirm Continue replays once and Cancel does not start the game.
16. Dismiss the profile picker and progress dialog. Confirm each dismissal cancels the pending Steam launch.
17. Rapidly click Play twice and confirm only one modal appears.
18. Disable the plugin while a request is checking, prompting, or activating. Confirm the held request fails open once and every hook unregisters.
19. Test the other Phase 1 launch routes and confirm Phase 5 leaves unsupported sources unchanged.

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

Phase 5 adds one fixed activation command shape:

```text
--game <matched-game-id> --profile <selected-profile-id>
```

Identifiers are validated and passed as separate `CreateProcessW` arguments. There is no shell, `--set`, `--del`, direct Vortex database access, recursive drive scan, or direct Vortex state edit. Normal logs redact game/profile IDs and never include Vortex log contents.

Phase 3 matching order remains configured override, explicit Vortex Steam ID, exact installation path, exact executable path, then no match. Ambiguous candidates and title-only matches are rejected.

## Tests

```powershell
lua tests/vortex_parsers.lua
lua tests/game_matching.lua
lua tests/vortex_launcher.lua
npm.cmd run test:phase4
npm.cmd run test:phase5
```

`tests/launch_continuation.ts` covers exact replay and one-shot bypass behavior. `tests/vortex_launcher.lua` covers exact readiness-event matching, and `tests/vortex_activation.ts` validates the frontend activation contract. The TypeScript runners compile only the relevant pure modules into the ignored `.millennium` build directory before executing them with Node.

## Scope

Phase 6 has intentionally not been started. There are no additional Steam launch routes, remembered decisions, preferred profiles, custom tools/executables, custom arguments, expanded recovery behavior, or settings UI. See [PROJECT_CONTEXT.md](PROJECT_CONTEXT.md) for the remaining phase.
