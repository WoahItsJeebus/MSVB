# Phase 5 Vortex profile activation findings

Phase 5 adds profile selection, starts or raises Vortex with the selected game/profile, waits for a dependable deployment-completion signal, and starts the preserved Steam launch only after confirmation.

It does not begin Phase 6. Interception remains limited to the confirmed Library Details `RunGame` source, and there are no remembered choices, preferred profiles, alternate tools, custom executables/arguments, additional launch routes, or settings UI.

## Vortex command behavior

Vortex's current CLI declares `--game <game id>` and `--profile <profile id>`; the profile option is described as starting Vortex with a specific profile active. See the official [CLI implementation](https://github.com/Nexus-Mods/Vortex/blob/master/src/main/src/cli.ts) and [command-line parameter guide](https://github.com/Nexus-Mods/Vortex/wiki/MODDINGWIKI-Users-Troubleshooting-Command-Line-Parameters).

The bridge constructs only this command:

```text
Vortex.exe --game <matched-game-id> --profile <selected-profile-id>
```

Both identifiers are validated as bounded, non-empty, non-option, control-character-free strings and passed separately to `CreateProcessW`. The shell is never involved. The executable path comes only from the existing validated Vortex detector.

The installed Vortex 2.3.0 renderer consumes a cold-start `--profile` by selecting the profile. Its profile-switch chain refreshes profile files, deploys the prior profile, deploys the selected profile, then logs `switched to profile` with the selected game/profile IDs before confirming the active profile. The same sequence is present in Vortex's profile-management source at [`profile_management/index.ts`](https://github.com/Nexus-Mods/Vortex/blob/master/src/renderer/src/extensions/profile_management/index.ts).

## Readiness contract

Process creation alone is not treated as successful activation.

Before starting Vortex, the backend records the current end of each supported Vortex log:

- `%APPDATA%\Vortex\vortex.log`
- `%ProgramData%\Vortex\vortex.log` for Vortex multi-user mode

It then reads only newly appended bytes. Success requires one complete `switched to profile` record containing exact JSON values for both the matched game ID and selected profile ID. That record occurs after both deployment steps in Vortex's profile-switch chain.

Vortex's file logger writes `vortex.log`, rotates it at a bounded size, and includes renderer metadata in each record; see its official [`logging.ts`](https://github.com/Nexus-Mods/Vortex/blob/master/src/main/src/logging.ts).

The bridge never returns or writes Vortex log contents. Normal plugin logs include only status flags, durations, AppIDs, the readiness-signal name, and redaction markers. No Vortex state file or database is opened or modified.

The existing `vortexActivationTimeoutMs` setting supplies the bounded wait and defaults to 30 seconds. Phase 5 does not add a settings UI.

## Already-running Vortex limitation

Vortex's current main-process `second-instance` handler parses forwarded arguments, but its non-download/install path only raises the main window. It does not forward `--game` or `--profile` into the renderer's cold-start command-line state. See the official [`Application.ts`](https://github.com/Nexus-Mods/Vortex/blob/master/src/main/src/Application.ts).

The installed Vortex 2.3.0 bundle matches that source behavior. Consequently:

- a normal Phase 5 activation starts a fresh Vortex process and can be confirmed;
- launching the executable while Vortex is already running raises the existing window;
- the bridge does not falsely report activation from process existence;
- if no exact completion event arrives, activation times out and the game is not started automatically.

The error dialog warns that Vortex may still finish a requested change and offers exactly:

- `Continue launching with Steam...`
- `Cancel`

This limitation is surfaced rather than bypassed with direct Vortex state edits.

## Frontend flow

For one matching profile, **Launch with Vortex** begins activation immediately. For several profiles, it opens a Steam-native list showing profile names plus available last-active/mod-count context.

The pending request states added in Phase 5 are:

```text
selecting-profile
activating-vortex
launching
```

During activation, dismissing the progress dialog cancels only the held Steam launch; Vortex may continue the requested profile change. An eventual backend result is ignored after cancellation.

After exact activation/deployment confirmation, the initial Phase 5 launch target is the preserved Steam `RunGame` tuple. It uses the existing one-shot bypass, so AppID, launch options, typed third parameter, and launch source are replayed exactly once without reopening the modal.

## Failure and unload behavior

- Invalid identifiers, missing Vortex, process-start failure, early Vortex exit, missing readiness location, timeout, or an unconfirmed result open the activation error dialog.
- A backend bridge exception also disables future interception for the session; the held request remains recoverable through the error dialog.
- Selecting Continue replays the original Steam tuple once.
- Selecting Cancel, closing, or pressing Escape cancels the held request.
- Plugin unload still fails an in-flight held request open once. Any later activation result is ignored because its pending token is gone.

## Automated checks

Run:

```powershell
lua tests/vortex_launcher.lua
npm.cmd run test:phase5
npm.cmd run test:phase4
npm.cmd run build
```

The launcher test rejects wrong game/profile IDs and non-completion log lines. The frontend contract test rejects unknown readiness signals. The Phase 4 suite continues to verify exact tuple replay and one-shot bypass behavior.

## Manual Phase 5 matrix

Use a short, harmless installed game and collect `[VLB]` records.

1. Close Vortex and launch a matching game with one profile from Library Details.
2. Select **Launch with Vortex**. Confirm Vortex starts and the progress dialog remains visible during deployment.
3. Confirm `vortex.activation.confirmed` occurs only after Vortex reports the selected profile active, followed by one `launch.post_activation_steam_target_started` and one bypass consumption.
4. Repeat with several profiles and confirm the selected profile—not merely the last-active profile—becomes active.
5. Dismiss the profile picker and confirm Steam does not start.
6. Dismiss the activation progress dialog and confirm Steam does not start even if Vortex later completes.
7. Start Vortex manually after the launch-choice modal appears, then choose Vortex. Confirm the request times out to the error dialog instead of starting Steam without confirmation.
8. Select `Continue launching with Steam...` and confirm the original request starts exactly once.
9. Repeat the failure and select Cancel, close, and Escape in turn; confirm none starts the game.
10. Disable the plugin during activation. Confirm the held request fails open once and a later activation result does not launch a second time.
11. Confirm normal logs contain no game/profile IDs, profile names, Vortex paths, or Vortex log contents.

Do not treat Phase 5 as runtime-confirmed until this matrix has been performed from the interactive Steam/Millennium user session.
