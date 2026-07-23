# Phase 3 game-matching findings

## Scope

Phase 3 resolves an installed Steam AppID, reads Vortex's approved discovered-game/profile state, and applies deterministic matching. It does not cancel, delay, resume, or initiate a Steam launch. It does not show a launch modal or activate Vortex profiles.

The frontend Phase 1 instrumentation remains observation-only.

## Steam installation resolution

The preferred source is the current typed Steam client API:

```text
SteamClient.InstallFolder.GetInstallFolders()
```

Each returned folder contains `strFolderPath` and `vecApps[].nAppID`. The frontend sends only the paths of folders that claim to contain the requested AppID. A client path is a hint, not proof: the backend still requires and parses the exact `steamapps\appmanifest_<appid>.acf`, verifies its `AppState.appid`, constructs `steamapps\common\<installdir>`, and verifies that directory exists.

If the Steam client lookup is unavailable, the Lua backend reads Steam's registry installation path and that installation's `steamapps\libraryfolders.vdf`. It checks only exact manifest filenames in those configured libraries. It does not recursively enumerate a library or scan a drive.

Resolution rejects:

- invalid or non-32-bit-positive AppIDs;
- malformed or oversized VDF files;
- manifests whose embedded AppID differs;
- absolute or escaping `installdir` values;
- install paths outside the library's `steamapps\common` directory;
- paths whose installation directory does not exist;
- two distinct valid installation paths for one AppID.

The result reports `steam-client`, `manifest`, or `none` as its source. Paths are returned to the calling frontend because matching needs them, but normal logs contain only redaction flags.

## Vortex discovered-game inputs

The matcher consumes the stable Phase 2 objects derived from:

```text
settings.gameMode.discovered
persistent.profiles
settings.profiles.lastActiveProfile
```

A discovered game currently has a required Vortex game ID and may have a name, installation path, store, executable, and an explicit Steam AppID. The Steam AppID is copied only when Vortex state actually supplies `steamAppId`, `steamAppID`, or a Steam-scoped `storeId`. It is never inferred from the game name.

The Phase 2 safety rule remains in effect: if Vortex is already running, the read-only CLI state query is skipped. Phase 3 then returns no match and a warning. No Vortex database or state file is read or changed directly.

## Matching order

The pure matcher stops at the first tier that produces a definitive result:

1. Configured Steam AppID to Vortex game-ID override.
2. Explicit Vortex-provided Steam/store AppID.
3. Exact normalized installation path.
4. Exact normalized executable path.
5. No match.

An explicit override is authoritative. If it points to a game absent from current discovered-game state, matching stops with no match rather than silently falling through to another game.

Every automatic tier requires exactly one candidate. Two or more candidates are rejected with a warning. A candidate is never selected by iteration order.

Executable matching accepts an optional dependable Steam executable path in the backend contract. The current typed Steam APIs expose launch-option labels but not a dependable executable path, so the Phase 3 frontend leaves that value empty. The tier is unit-tested and available when a verified source is added later.

Game titles are metadata only. There is no title equality, fuzzy title, punctuation-stripping, or title-based fallback in the matcher.

## Windows path rules

Comparison is lexical and Windows-specific:

- `/` and `\` are treated as separators;
- drive letters and path segments are compared case-insensitively;
- redundant separators, `.` segments, `..` segments, and trailing separators are normalized;
- drive-relative paths such as `C:game` and current-drive paths such as `\game` are rejected;
- UNC server/share roots are supported;
- no filesystem canonicalization is used, so the matcher makes no assumption about symlinks or junctions.

Relative Vortex executable values are resolved only against that discovered game's installation path.

## Overrides

Overrides are stored in:

```text
%LOCALAPPDATA%\VortexLaunchBridge\settings.json
```

The `steamAppIdOverrides` object maps canonical decimal AppID strings to Vortex game IDs:

```json
{
  "steamAppIdOverrides": {
    "1234": "example-game"
  }
}
```

Both keys and values are validated on load and save. The Phase 3 panel can load, save, and clear one mapping at a time.

## Result contract

The stable frontend result is:

```ts
interface VortexGameMatch {
    matched: boolean;
    confidence:
        | "configured"
        | "steam-id"
        | "exact-path"
        | "exact-executable"
        | "none";
    steamAppId: number;
    steamSource?: "steam-client" | "manifest" | "none";
    steamInstallPath?: string;
    vortexGameId?: string;
    vortexGamePath?: string;
    profiles: VortexProfile[];
    warning?: string;
}
```

Only profiles whose `gameId` exactly equals the matched Vortex game ID are returned. A valid game match may have zero profiles; later launch behavior must treat that as non-prompting.

## Automated coverage

Run:

```powershell
lua tests/vortex_parsers.lua
lua tests/game_matching.lua
```

The Phase 3 suite covers VDF parsing, library ordering, manifest AppID validation, Windows path normalization, configured matching, store-ID matching, exact-path matching, exact-executable matching, stable profile filtering, invalid overrides, ambiguous paths, and rejection of title-only matches.

## Manual Phase 3 checks

1. Close Vortex.
2. Enter an installed Steam AppID and select **Resolve Steam path**.
3. Confirm the panel reports `steam-client` when the typed API returns the library, or `manifest` when the backend fallback is used.
4. Select **Match Vortex game** and confirm an exact discovered path returns the expected Vortex game ID and profile count.
5. Configure a valid Vortex game-ID mapping, repeat the match, and confirm confidence is `configured`.
6. Configure a nonexistent Vortex game ID and confirm the match is rejected rather than falling through.
7. Clear the mapping and confirm path/store matching resumes.
8. Start Vortex and confirm matching returns a read-only-state warning without modifying Vortex.
9. Confirm normal logs contain AppIDs, sources, confidence, counts, and redaction markers—but no Steam paths, Vortex paths, game IDs, or profile names.
10. Launch a Steam game and confirm Phase 1 remains observation-only and Steam behavior is unchanged.

## Phase boundary

Phase 4 has not started. There is no launch cancellation, modal, preserved pending request, one-shot bypass, Steam continuation, or Vortex activation in this phase.
