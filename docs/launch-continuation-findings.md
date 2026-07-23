# Phase 4 launch-continuation findings

## Scope

Phase 4 adds one narrow interception route, a Steam-native choice modal, exact Steam continuation, dismissal-as-cancellation, duplicate suppression, and fail-open behavior.

This document records the Phase 4 boundary. Phase 5 now extends the Vortex choice with the activation flow documented in [vortex-activation-findings.md](vortex-activation-findings.md); the continuation and interception safety properties below remain unchanged.

## Supported route

The only intercepted request is a direct call through the current SharedJSContext property:

```text
SteamClient.Apps.RunGame
```

with:

```text
launchSource === ELaunchSource._2ftLibraryDetails
```

Every other launch source immediately invokes the original function. Phase 4 does not intercept action callbacks, patch another launch method, or call:

```text
CancelLaunch
CancelGameAction
ContinueGameAction
```

The Phase 1 runtime route matrix is still unfilled. Therefore this phase does not claim that desktop shortcuts, protocol URLs, double-clicks, tray launches, Big Picture, or launch-option dialogs reach the supported route. Those sources remain unchanged unless a live trace later proves they use this exact `RunGame` source.

## Why this route can be continued exactly

`RunGame` supplies the complete invocation that Phase 4 replays:

```ts
[
    appId: string,
    launchOptions: string,
    parameter3: number,
    launchSource: ELaunchSource,
]
```

The replacement patch withholds the original call synchronously. It does not start and then cancel a Steam action. If matching fails or finds no profiles, the frontend invokes `RunGame` again with the exact stored tuple.

The original AppID string is retained alongside a validated numeric AppID used for backend matching. Launch options remain in memory, are never persisted, and are represented in normal logs only by presence and redaction fields.

## One-shot bypass

Before replay, the frontend issues a short-lived token bound to the complete request signature. The nested `RunGame` call consumes exactly one matching token, and the replacement patch returns Millennium's `callOriginal` marker.

The bypass:

- compares AppID, launch options, the typed third parameter, and launch source;
- is consumed once;
- expires after five seconds;
- is revoked if invoking `RunGame` throws;
- is cleared on plugin unload.

Interception is never disabled globally while a request is replayed.

## Decision flow

```text
RunGame(_2ftLibraryDetails)
  -> validate and capture exact tuple
  -> suppress an identical pending duplicate
  -> check Phase 3 Vortex match
     -> error or timeout: replay once, suspend interception for this session
     -> no match: replay once
     -> match with zero profiles: replay once
     -> match with profiles: show one modal
        -> Continue launching with Steam...: replay once
        -> close / Escape / cancel gesture: cancel pending request
        -> Launch with Vortex: cancel pending request; activation deferred to Phase 5
```

The matching decision has a 20-second frontend deadline. A frontend/backend bridge error fails open for the current request and makes future supported calls pass through for the rest of that plugin session.

## Modal semantics

The modal uses the current Steam `ModalRoot`, `showModal`, and `DialogButton` components. Its only action buttons are exactly:

- `Launch with Vortex`
- `Continue launching with Steam...`

The modal explicitly states that continuing through Steam does not change anything Vortex may already have deployed.

Background dismissal is disabled. The close icon, Escape, controller cancel, and other explicit cancel callbacks all cancel the pending request. None of them are interpreted as choosing Steam.

The modal handle's `Close()` method is used after a settled choice because the installed API documents that it does not invoke modal callbacks.

## Request state and races

Each pending request records:

- a generated request ID;
- Steam AppID;
- exact `RunGame` tuple;
- capture time;
- state;
- duplicate count.

Phase 4 states are:

```text
checking-vortex
awaiting-user
continuing-steam
cancelled
completed
failed
```

Only one request is held at a time:

- an identical request while checking or prompting is suppressed and counted;
- a same-AppID request with changed optional fields is also correlated and suppressed while that AppID is pending;
- a different request while one is pending passes through unchanged;
- any same-AppID Steam retry after a recently dismissed request is suppressed for five seconds;
- a modal cannot be created after its pending request has settled;
- asynchronous matching completion is ignored after unload;
- unload closes any modal and replays each still-held request once before unpatching.

## Phase 1 diagnostics interaction

Phase 1 callback observers remain registered and unregisterable. Its older `RunGame.beforePatch` sits inside the Phase 4 replacement:

- unsupported launch sources pass through and remain observable;
- a Steam continuation becomes observable when its bypass reaches the original;
- a request cancelled before the original call does not produce the old `RunGame` observation.

Phase 4 adds dedicated structured events for interception, bypass consumption, continuation, modal display, duplicate suppression, cancellation, suspension, and cleanup.

## Automated checks

`tests/launch_continuation.ts` verifies:

- exact four-argument replay;
- one `RunGame` call per continuation;
- one-shot token consumption;
- signature mismatch rejection;
- token expiry;
- rejection of invalid AppIDs.

Run it with:

```powershell
npm.cmd run test:phase4
```

The runner compiles only the pure continuation modules into the ignored `.millennium` build directory, then executes them with Node.

The production TypeScript build validates the interceptor and modal against the installed `@steambrew/client` API.

## Manual Phase 4 matrix

Use a short, harmless installed game and collect `[VLB]` records.

1. Confirm `launch.interception.started` reports `RunGame`, `_2ftLibraryDetails`, and phase `4`.
2. Launch a game with no deterministic Vortex match or no profiles from its Library Details Play button. Confirm no modal appears and the game starts once.
3. Launch a game with a deterministic Vortex match and at least one profile. Confirm exactly one modal appears.
4. Select **Continue launching with Steam...**. Confirm the game starts exactly once and one `launch.bypass.consumed` event appears.
5. Repeat, then close the modal with its close icon. Confirm the game does not start.
6. Repeat, then press Escape. Confirm the game does not start.
7. Repeat, then select **Launch with Vortex**. Confirm the held Steam request is cancelled and no Vortex activation occurs in Phase 4.
8. Rapidly click Play twice. Confirm one modal and a `launch.pending_duplicate_suppressed` event.
9. While a modal is open, launch a different game. Confirm the second request passes through and the first modal remains.
10. While matching or prompting, disable the plugin. Confirm the held request is replayed once and all hooks unregister.
11. Test each unsupported route from the Phase 1 matrix. Confirm no Phase 4 modal is shown unless its live trace proves it is the exact supported source.
12. Simulate a backend failure. Confirm the current request continues and later requests pass through for that session.

Do not mark the Library Details route runtime-confirmed until steps 1–12 have been performed against the installed Steam client.

## Phase boundary

There is no Vortex `--game` or `--profile` invocation, profile picker, activation wait, deployment wait, Vortex process start/focus operation, alternate tool selection, or post-activation game launch in Phase 4.
