# Phase 2 Vortex backend probe findings

Phase 2 detects Vortex and probes its supported read-only CLI. It does not match Steam games, activate Vortex games or profiles, cancel Steam launches, show a launch-choice modal, or begin Phase 3.

## Upstream behavior confirmed

The current Vortex CLI declares `--version` and repeatable `--get <path>` options. It also declares mutating options such as `--set` and `--del`; this plugin never constructs or accepts those arguments. See Vortex's current [`cli.ts`](https://github.com/Nexus-Mods/Vortex/blob/master/src/main/src/cli.ts).

Vortex 2.x does not emit one JSON document for a `--get` request. Its read handler walks matching persisted keys and writes one line per value:

```text
state.path = <JSON value>
```

The handler uses read operations (`getAllKeys` and `getItem`) and closes the persistence layer afterward. See Vortex's current [`Application.ts`](https://github.com/Nexus-Mods/Vortex/blob/master/src/main/src/Application.ts).

The probed paths are grounded in current Vortex state definitions:

- `persistent.profiles` contains profiles keyed by profile ID. A valid profile has `id`, `gameId`, `name`, `modState`, and `lastActivated`; see [`IProfile.ts`](https://github.com/Nexus-Mods/Vortex/blob/master/src/renderer/src/extensions/profile_management/types/IProfile.ts).
- `settings.profiles.lastActiveProfile` maps a Vortex game ID to its last active profile ID; see the profile [`settings.ts`](https://github.com/Nexus-Mods/Vortex/blob/master/src/renderer/src/extensions/profile_management/reducers/settings.ts).
- `settings.gameMode.discovered` contains discovered game records, including optional path, store, executable, name, and manual-path state; see the game-mode [`settings.ts`](https://github.com/Nexus-Mods/Vortex/blob/master/src/renderer/src/extensions/gamemode_management/reducers/settings.ts) and [`IDiscoveryResult.ts`](https://github.com/Nexus-Mods/Vortex/blob/master/src/renderer/src/extensions/gamemode_management/types/IDiscoveryResult.ts).

The parser also accepts a whole JSON object for compatibility with older or alternate Vortex output, but it does not assume that format.

## Local probe observation

Observed on 2026-07-23 with installed Vortex 2.3.0:

| Command | Exit | stdout | stderr | Vortex left running |
| --- | ---: | --- | --- | --- |
| `Vortex.exe --version` | 0 | `2.3.0` | empty | no |
| approved `--get` paths | 0 | startup diagnostic noise, no state assignments | Electron singleton lock diagnostic | no |

The local command runner executes under an isolated identity rather than the interactive desktop user who owns the Vortex state. It therefore could not validate that user's profile payload. This is recorded as an unresolved runtime test, not treated as an empty profile database.

The implemented parser was verified with a synthetic Vortex 2.x assignment stream. It reconstructs the requested state and converts valid profile records to stable objects:

```ts
interface VortexProfile {
    id: string;
    name: string;
    gameId: string;
    enabledModCount?: number;
    isLastActive?: boolean;
}
```

Malformed profiles are omitted and counted. Profiles are sorted deterministically by game ID, name, and profile ID.

## Detection behavior

Detection order is:

1. saved user override;
2. Windows uninstall registry entries in current-user and local-machine, 32-bit and 64-bit views;
3. a fixed list under LocalAppData, Program Files, and Program Files (x86).

A candidate must be a non-empty existing file named `Vortex.exe`. Detection never recursively scans a drive. A successful result is cached in memory and revalidated before reuse. Saving or clearing the override invalidates the cache.

Normal logs record only whether a path was present, its detection source, and version metadata. Executable paths and registry values are not logged.

## Process and output safety

- Vortex is created directly with `CreateProcessW`; no shell is involved.
- Windows command arguments use the documented backslash-and-quote rules.
- stdout and stderr use separate inherited pipes and are drained while the process runs.
- Every invocation has a timeout; a timed-out child is terminated and reported.
- Output is capped, byte counts and truncation flags are retained, and UTF-8 validity is recorded.
- Raw stdout/stderr are returned only in the explicit probe response. The frontend never writes them to normal logs or displays their contents.
- The state query is skipped when Vortex is already running because `--get` is a startup mode and a second instance may forward arguments to the primary process.
- The probe records whether Vortex was running before and after each command and whether a new process remains.

The only constructed commands are `--version` and the three approved `--get` paths. No Vortex state files or databases are opened by the plugin.

## Manual runtime workflow still required

Run this from the actual Steam/Millennium user session:

1. Close Vortex.
2. Open the Vortex Launch Bridge plugin panel.
3. Confirm detection reports the expected source and version.
4. Select **Run read-only probe**.
5. Confirm the version command exits 0 without leaving Vortex running.
6. Confirm the state command reports `assignments` (or a documented compatible format), with exit code 0 and no timeout.
7. Confirm profile and discovered-game counts agree with Vortex.
8. Confirm no profile names, paths, stdout, or stderr appear in normal frontend/backend logs.
9. Start Vortex and run the probe again; confirm the state command reports `vortex-already-running` and is not executed.
10. If an invocation times out, confirm the timeout flag is set and no probe-created Vortex process remains.

Phase 3 must not begin until the state shape is observed in the actual desktop-user context and reviewed.
