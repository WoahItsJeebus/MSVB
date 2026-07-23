# Phase 6 hardening and settings

Launch dialogs explicitly target Steam's desktop SharedJS window. This avoids
the gamepad-window auto-discovery path used by the modal helper, which is not
available for every desktop launch route. Frontend launch diagnostics are also
mirrored into Millennium's plugin log through a bounded backend RPC sink.

The launch, activation-progress, and recovery dialogs use Steam's native
confirmation modal. Settings fields place related inputs and actions inside one
full-width responsive child, wrap button rows when space is constrained, and
hide per-game detail fields until an AppID's settings have been loaded.

The plugin warms a memory-only Vortex discovered-game/profile snapshot after
startup and refreshes it every five minutes. Matching reads the last successful
snapshot immediately. Refresh failures preserve that snapshot, a Vortex
executable override invalidates it, and a successful read-only probe updates it.

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

The backend uses Millennium's supported `json` Lua module for decoding. The
Phase 6 runner rejects legacy `cjson` imports because they crash the current Lua
VM before plugin logging is initialized. Responses, logs, and settings use the
plugin's bounded pure-Lua JSON encoder to avoid the Millennium 3.3.1 native
encoder access violation observed after a successful nested game/profile match.
All JSON encoding and decoding performed by plugin RPC handlers is now bounded
pure Lua so nested Vortex state never crosses Millennium's native JSON module.

Millennium 3.3.1 passes Lua RPC request-object values positionally rather than binding them by key. Every parameterized bridge RPC therefore uses a single `request_json` envelope and validates/decodes it in the backend. The Phase 6 runner rejects multi-field callable contracts and handlers that bypass this envelope.

The backend also disables LuaJIT before loading plugin modules. The interpreter is sufficient for this event-driven workload and avoids the Millennium 3.3.1 `lj_vm_hotcall`/`lj_dispatch_call` access violation captured when repeatedly invoking backend RPC handlers.

Millennium 3.3.1's Windows LuaJIT FFI path can also clobber the nonvolatile
register holding `handle_evaluate`'s JSON return pointer. Process launch,
capture, timeout, process detection, and registry access therefore use the
packaged PowerShell/.NET runner. A small Windows-subsystem command broker is
temporarily selected as this Lua VM's `ComSpec`, allowing Lua's standard pipe
API to capture the runner without creating a console window. Delays and timing
use Millennium's utility module directly. Executable paths and arguments stay
in a JSON request file and are passed to `System.Diagnostics.Process`; they are
not interpolated into the shell command.
Startup verifies both process execution and registry isolation before launch
interception is enabled.
