# Vortex Launch Bridge

A Windows-first [Millennium](https://github.com/SteamClientHomebrew/Millennium) plugin for coordinating Steam launches with Vortex-managed games.

The repository contains the complete Phase 0 through Phase 6 MVP: plugin lifecycle and health checks, redacted diagnostics, read-only Vortex probing, deterministic matching, exact Steam continuation, confirmed profile activation, additional direct Steam routes, opt-in remembered choices, per-game custom launch tools, recovery dialogs, settings UI, and automated pure-module tests.

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

## Phase 6 MVP behavior

The bridge intercepts only direct `SteamClient.Apps.RunGame` calls. It supports Library Details, list/grid/minimode, Big Picture, command-line, Steam URL run/launch, tray, library context-menu/double-click, and portrait-context-menu source values. Automatic/internal sources such as install completion, downloads, remote streaming, lobby/party joins, DRM recovery, and already-running discovery pass through unchanged.

Callback-based Steam action APIs remain observation-only because their pre-process timing has not been established. A source is supported only when it reaches the patched `RunGame` property; routes that bypass it remain untouched.

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

Choosing **Launch with Vortex** activates the only matching profile directly or opens a profile picker when several profiles exist. The backend starts Vortex with fixed `--game` and `--profile` arguments, then tails only newly written Vortex log data for the exact selected game/profile completion event. Vortex emits that event after its profile deployment chain completes. Only then does the frontend start the configured per-game target.

The settings panel can opt in to remembered per-game decisions. **Always ask** is enabled by default and overrides every saved decision. With remembering enabled and Always ask disabled, a saved Steam choice replays the request; a saved Vortex choice runs only when its exact saved profile is still available. A stale profile returns to the modal instead of guessing.

Each Steam AppID can use the preserved Steam request or an existing absolute `.exe` after confirmed Vortex activation. Custom arguments are parsed into separate `CreateProcessW` arguments without a command shell. Paths and arguments are redacted from normal and diagnostic logs. If the custom target or post-activation Steam target fails, the request remains recoverable through `Continue launching with Steam...` or `Cancel`.

While activation is pending, a progress dialog can cancel the held Steam launch. If activation exits early or times out, the error dialog offers exactly:

- `Continue launching with Steam...`
- `Cancel`

The timeout path warns that Vortex may still finish the requested profile change. The modal does not claim that continuing with Steam changes or disables anything Vortex may already have deployed.

Current Vortex 2.3.0 accepts `--profile` on a cold start, but its second-instance handler does not apply profile/game arguments to an already-running primary instance. The bridge therefore requires a fresh Vortex start for a confirmed activation. If Vortex starts in the gap between matching and activation, the request times out safely into the error dialog instead of starting the game without confirmation.

See [vortex-activation-findings.md](docs/vortex-activation-findings.md) for the readiness contract and current Vortex limitation.

## Verify the Phase 6 MVP manually

1. Run `bun run build` and confirm it exits successfully.
2. Start Steam and enable the plugin.
3. Confirm the plugin appears as **Vortex Launch Bridge** version `0.7.0`.
4. Confirm backend health succeeds and Phase 1 observers register.
5. Confirm Vortex detection and the read-only probe behave as documented in [vortex-probe-findings.md](docs/vortex-probe-findings.md).
6. Confirm Steam path resolution and deterministic matching behave as documented in [game-matching-findings.md](docs/game-matching-findings.md).
7. Confirm `launch.interception.started` reports phase `6`, route `RunGame`, and the supported source list.
8. From Library Details, launch a game without matching Vortex profiles. Confirm no modal appears and Steam starts it once.
9. Launch a matching game with profiles. Confirm exactly one modal appears.
10. Select **Continue launching with Steam...** and confirm Steam starts the game exactly once.
11. Repeat and dismiss with the close icon, then with Escape. Confirm the pending launch is cancelled.
12. With Vortex closed and the default Steam target configured, repeat and select **Launch with Vortex** for a game with one profile. Confirm Vortex starts, the progress dialog remains until deployment confirmation, and Steam starts the preserved request exactly once.
13. Repeat with several profiles. Confirm the profile picker appears and the selected profile becomes active before the configured target starts.
14. Start Vortex manually while the initial launch-choice modal is open, then select **Launch with Vortex**. Confirm the activation times out into the error dialog with `Continue launching with Steam...` and `Cancel`.
15. Test each error choice. Confirm Continue replays once and Cancel does not start the game.
16. Dismiss the profile picker and progress dialog. Confirm each dismissal cancels the pending Steam launch.
17. Rapidly click Play twice and confirm only one modal appears.
18. Disable the plugin while a request is checking, prompting, or activating. Confirm the held request fails open once and every hook unregisters.
19. Test each supported direct route and confirm matching games receive one prompt while unmatched games start once without a prompt.
20. Confirm install-complete, download, streaming, lobby/party, DRM, and already-running sources pass through.
21. Enable remembering, disable Always ask, save Steam and Vortex choices in turn, and confirm each applies only to its AppID.
22. Remove or rename a remembered Vortex profile and confirm the next launch prompts instead of selecting another profile.
23. Configure a harmless custom `.exe` with quoted arguments. Confirm it starts only after Vortex activation and Steam is not replayed.
24. Make the custom executable unavailable after saving. Confirm the recovery dialog offers `Continue launching with Steam...` and `Cancel`.
25. Enable diagnostic logging and confirm detailed callback records appear; disable it and confirm they stop while operational warnings/errors remain.

The final route, settings, launch-target, and recovery contracts are in [phase6-hardening-settings.md](docs/phase6-hardening-settings.md).

## Vortex state and matching

The backend settings model is stored at `%LOCALAPPDATA%\VortexLaunchBridge\settings.json`. The panel exposes the Vortex executable override and a validated `steamAppIdOverrides` mapping.

The read-only Vortex command allowlist remains:

```text
--version
--get persistent.profiles
--get settings.profiles.lastActiveProfile
--get settings.gameMode.discovered
```

Profile activation uses one fixed command shape:

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
npm.cmd run test:phase6
```

`test:phase6` runs exact replay, activation, remembered-policy, custom argument parsing, Vortex-state parsing, deterministic matching, and activation-signal coverage. The TypeScript runner compiles only pure modules into the ignored `.millennium` build directory before executing them with Node.

## Scope

The MVP is complete through the final phase. It still does not purge or disable deployed mods, edit Vortex state, manage profiles or downloads, support non-Steam games, inject into processes, or claim that a Steam continuation changes the modded state on disk.
