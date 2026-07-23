# Phase 1 launch-hook findings

## Status

Phase 1 provides observation-only launch instrumentation in Steam's SharedJSContext. It does not cancel, continue, delay, or initiate a launch, and it does not display a modal.

Phase 4 implemented a deliberately narrow direct-`RunGame` continuation path. Phase 6 expands the safe direct-source allowlist without changing the unverified callback timing below; its final scope and manual matrix are documented in [phase6-hardening-settings.md](phase6-hardening-settings.md).

No live Steam launch traces were available while implementing this phase. The build-time API findings below are confirmed against the installed `@steambrew/client` package, but event order and route behavior remain explicitly unverified until the manual matrix is run.

Instrumentation is registered only after the Phase 0 backend health check succeeds. If the backend is unavailable or returns a mismatched plugin version, no launch observers are installed.

## Installed API surface

The project currently resolves:

- `@steambrew/api` 5.8.4
- `@steambrew/client` 5.8.5
- `@steambrew/ttc` 3.3.7
- `@steambrew/webkit` 5.8.4

The inspected declarations are in `node_modules/@steambrew/client/src/globals/steam-client/App.ts` and `shared.ts`. The scaffold remains based on official PluginTemplate commit `fbe04927f622cbb60909f269f687434574987ff3`.

The following members are typed on `SteamClient.Apps`:

| API | Installed TypeScript signature | Phase 1 use | Runtime uncertainty |
| --- | --- | --- | --- |
| `RegisterForGameActionUserRequest` | `(gameActionId, appId, action, requestedAction, appId2) => void` | Registered and unregistered | The meaning of `appId2` and actual timing are unknown. |
| `RegisterForGameActionStart` | `(gameActionId, appId, action, launchSource) => void` | Registered and unregistered | It is unknown whether the callback occurs before process creation. |
| `RegisterForGameActionTaskChange` | `(gameActionId, appId, action, requestedAction, param4) => void` | Registered and unregistered | The meaning of `param4` is unknown, so its value is always redacted. |
| `RegisterForGameActionEnd` | `(gameActionId) => void` | Registered and unregistered | It is unknown whether every route produces an end event. |
| `GetGameActionDetails` | `(appId: number, callback: (gameAction) => void) => void` | Called after a start event | The installed type names the argument `appId`; community assumptions that it may be an action ID require runtime verification. |
| `RunGame` | `(appId, launchOptions, param2, launchSource) => void` | One transparent `beforePatch` observer | Calls through a previously captured function reference or native-internal paths may bypass the patched property. |
| `CancelLaunch` | `(appId) => void` | **Not called** | Reserved for a later phase only after timing is proven safe. |
| `CancelGameAction` / `ContinueGameAction` | Typed | **Not called** | Reserved for later research and implementation. |

All registration methods are typed as returning an object with `unregister(): void`. Phase 1 validates each returned handle and disposes it during plugin unload. `RunGame` is the only method patched; the supported `beforePatch` helper forwards the original `this`, arguments, and return value unchanged.

## Diagnostic log format

Filter Steam's frontend console for `[VLB]`. Relevant structured events are:

- `launch.instrumentation.started`: runtime member availability and installed observers.
- `launch.callback.observed`: ordered callback or `RunGame` observations.
- `launch.callback.duplicates_suppressed`: identical callbacks suppressed inside a 750 ms window.
- `launch.hook.unregistered`: successful unload cleanup.
- `launch.instrumentation.stopped`: observation session ended.

Each observed callback includes:

- session ID and monotonically increasing sequence;
- correlated trace ID;
- capture timestamp and first-observed timestamp;
- AppID and game-action-ID presence flags;
- positional callback parameters;
- request state (`observed` or `completed`).

Launch options, task details, unknown string parameters, paths, and non-numeric identifiers are not logged. Diagnostics retain only presence, length, and a redaction marker. A non-cryptographic fingerprint is used in memory only for deduplication and is never logged.

## Current diagnostic summary

### Event order

Unknown. No live launch trace has been collected. Do not infer an order from the registration order in source code.

### Callback parameters

The compile-time signatures are documented above. Placeholder parameter names and `GetGameActionDetails` identifier semantics still require runtime probing.

### Is an AppID always present?

Unknown. Logs record `appIdPresent` separately and redact non-numeric identifiers so this can be answered after route testing.

### Is a game action ID always present?

Unknown. Registered action callbacks are typed with one; the `RunGame` call is not. Logs record `gameActionIdPresent` for every observation.

### Is `RunGame` directly invoked?

Unknown for every route. The single observation patch will report calls that resolve through the current `SteamClient.Apps.RunGame` property.

### Route behavior

| Launch route | Runtime result |
| --- | --- |
| Library Play button | Not tested |
| Double-click library entry | Not tested |
| Desktop Steam shortcut | Not tested |
| `steam://run/<appid>` | Not tested |
| System-tray recent game | Not tested |
| Big Picture mode | Not tested |
| Game with Steam launch-option dialog | Not tested |

### Recommended callback interception strategy

No callback interception point is recommended yet. Runtime logs must first demonstrate which callback is earliest, whether it consistently includes AppID/action ID data, and whether the process has already started. Phase 4 deliberately leaves these callbacks observation-only and instead holds one exact direct-`RunGame` source.

After the matrix is collected, prefer one stable action callback over patching several launch methods. A candidate is acceptable only if it is present across required routes, occurs before process creation, provides a stable request identity, and can be resumed without recursion.

### Unresolved risks

- Steam callbacks are undocumented and may change between client releases.
- A callback may be delivered after the game process has already started.
- Native or captured-reference launch paths may bypass the `RunGame` property observer.
- `GetGameActionDetails` may be mistyped or may return data too late to support interception.
- Rapid repeated actions may share AppID data while representing distinct requests.
- Launch-option dialogs may create additional tasks or callbacks.
- Big Picture and desktop shortcut routes may use different launch sources.
- Another plugin may patch `RunGame`; unload order and patch chaining must be verified in the live client.

## Manual test procedure

Use a short, harmless game that exits quickly. Do not use a game with unsaved work or an anti-cheat-sensitive test environment.

1. Build with `bun run build`, restart Steam, and enable Vortex Launch Bridge.
2. Open Steam's frontend developer console and filter for `[VLB]`.
3. Confirm `launch.instrumentation.started` reports all expected observers.
4. Clear the console before each route.
5. Launch and exit the test game once through each route in the table above.
6. For the launch-option-dialog case, record which option was selected.
7. Save all `[VLB]` records without editing their sequence or timestamp fields.
8. Rapidly double-click Play once and confirm duplicate summaries appear without changing Steam's behavior or emitting duplicate full-detail records.
9. Disable the plugin and confirm every observer reports `launch.hook.unregistered`.
10. Confirm subsequent Steam launches behave normally and produce no new `[VLB]` launch records.

Do not begin cancellation experiments from these logs alone. Review the full route matrix and update this document with observed order and timing first.
