# Phase 6 hardening and settings

## Final phase boundary

Phase 6 completes the MVP with additional direct `RunGame` sources, explicit settings, opt-in remembered decisions, per-game launch targets, improved recovery, diagnostic-log control, and automated tests. It does not patch Steam action callbacks, edit Vortex state, purge deployed mods, or add non-Steam game support.

## Supported direct launch sources

The replacement still targets only `SteamClient.Apps.RunGame`, where the full typed tuple can be captured synchronously:

```text
AppID
launch options
typed third parameter
launch source
```

The eligible source allowlist is:

- `_2ftLibraryDetails`
- `_2ftLibraryListView`
- `_2ftLibraryGrid`
- `_2ftMiniModeList`
- `_10ft`
- `DashAppLaunchCmdLine`
- `DashGameIdLaunchCmdLine`
- `RunByGameDir`
- `SubCmdRunDashGame`
- `SteamURL_Launch`
- `SteamURL_Run`
- `SteamURL_RunGame`
- `SteamURL_RunGameIdOrJumplist`
- `SteamURL_RunSafe`
- `TrayIcon`
- `LibraryLeftColumnContextMenu`
- `LibraryLeftColumnDoubleClick`
- `AppPortraitContextMenu`

Install/download completion, remote streaming, lobby/party joins, internal launch engines, DRM/cloud recovery, Dota-specific, and already-running sources are intentionally excluded.

This allowlist does not claim that every named user route reaches the current SharedJSContext property. A native path or captured function reference can bypass the patch. Callback APIs remain diagnostic-only because their cancellation timing is still not runtime-confirmed.

Every supported source uses the same exact replay tuple and one-shot signature-bound bypass introduced in Phase 4.

## Remembered-choice policy

Defaults remain conservative:

- `alwaysAsk = true`
- `rememberChoicePerGame = false`
- no choice is persisted without explicit opt-in
- no match or no profiles produces no modal
- failures before a user decision fail open

When Always ask is enabled, saved choices are ignored. When Always ask is disabled and remembering is enabled:

- a remembered `steam` decision replays the exact request;
- a remembered `vortex` decision activates only the exact saved profile;
- a missing or stale saved profile shows the choice/profile flow instead of guessing.

A user-selected Steam decision is recorded when selected. A Vortex decision/profile is recorded only after activation and the configured launch target both succeed. Clearing remembered choices removes decisions while preserving preferred profiles, per-game custom target configuration, and Steam-to-Vortex ID overrides.

## Per-game launch targets

The default target is `steam`, which replays the preserved request exactly once after confirmed Vortex activation.

The `custom` target requires:

- a positive Steam AppID;
- an existing absolute `.exe` path;
- a command line no longer than the Windows limit;
- at most 128 parsed arguments;
- no NUL or line-break characters;
- balanced quotes.

The backend reads the saved target configuration by AppID. The frontend never sends an executable at launch time. The backend parses the saved argument string into an argument vector and passes it to the existing direct `CreateProcessW` helper. It does not invoke `cmd.exe`, PowerShell, a URL handler, or another shell.

Normal and diagnostic logs record only target type, argument count, process status/ID, and redaction flags. Executable paths and argument contents are never logged.

## Settings UI

The plugin panel exposes:

- Always ask;
- remember choices per game;
- diagnostic launch logging;
- Vortex activation timeout from 1 to 300 seconds;
- clear remembered choices;
- per-AppID preferred Vortex profile ID;
- Steam versus custom post-activation target;
- custom executable;
- custom arguments;
- the existing Vortex path override;
- the existing Steam AppID to Vortex game-ID override.

Settings are validated in both TypeScript response parsers and the Lua backend. Backend writes roll back the in-memory field values if persistence fails.

Detailed Phase 1 callback records use debug logging and appear only while diagnostic logging is enabled. Operational lifecycle, warning, and error records remain available.

## Recovery behavior

The original request stays pending after cancellation of the initial call.

- Matching/settings bridge failures fail open and suspend future interception for that plugin session.
- Vortex activation failure offers `Continue launching with Steam...` and `Cancel`.
- A missing, invalid, or failed custom target offers the same recovery actions.
- A thrown post-activation Steam replay offers retry or cancellation instead of silently discarding the request.
- Plugin unload attempts one exact Steam continuation for every pending request before removing the patch.

Explicit modal dismissal remains cancellation. It is never treated as choosing Steam.

## Automated verification

Run:

```powershell
npm.cmd run test:phase6
npm.cmd run build
```

The Phase 6 runner covers:

- exact four-value Steam replay and one-shot bypass;
- Vortex activation response parsing;
- remembered-choice precedence and stale-profile fallback;
- settings and custom-launch response parsing;
- Windows custom-argument tokenization and rejection cases;
- settings validation, opt-in remembering, clearing, and failed-write rollback;
- Vortex assignment-state parsing;
- deterministic matching order and ambiguity rejection;
- exact Vortex activation-log signal matching.

The repository's Lua sources also pass `luac -p` syntax validation. Live Steam/Vortex behavior still requires the manual matrix in the README because the desktop host and Vortex process are unavailable to automated unit tests.
