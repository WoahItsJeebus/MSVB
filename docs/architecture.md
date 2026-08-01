# Architecture

Vortex Launch Bridge is a Millennium plugin with a TypeScript/React frontend and a Lua backend. Its central design rule is simple: never withhold a Steam launch unless the plugin already has enough local, validated information to offer a safe decision.

## Runtime flow

1. The backend starts with LuaJIT disabled and verifies its local process bridge.
2. The frontend warms a read-only Vortex state cache and refreshes it periodically.
3. The launch interceptor observes supported direct `SteamClient.Apps.RunGame` sources.
4. A request passes through unchanged unless its AppID can be matched to a Vortex game with at least one valid profile.
5. An eligible request is preserved as a typed tuple and the Steam-themed decision modal opens.
6. The user can cancel, replay the exact Steam tuple, or request Vortex activation.
7. Vortex activation runs through the Lua backend with validated identifiers, bounded process execution, and a configurable timeout.
8. After deployment confirmation, the preserved Steam request or configured custom target starts through a one-shot continuation path.

## Components

| Area | Responsibility |
| --- | --- |
| `frontend/launch` | Source allowlist, interception, one-shot bypass, prompt orchestration, and Steam continuation |
| `frontend/vortex` | Typed backend calls and Vortex response validation |
| `frontend/settings` | General and per-game settings UI and launch policy |
| `frontend/matching` | Steam AppID diagnostics and explicit game-ID mapping |
| `backend/vortex` | Vortex discovery, read-only probing, profile activation, and deployment confirmation |
| `backend/steam` | Steam library and manifest resolution |
| `backend/settings` | Validated local persistence and remembered-choice policy |
| `backend/util` | Bounded JSON, paths, command lines, Windows process execution, and text handling |

## Trust boundaries

### Steam launch interception

Only verified direct `RunGame` sources are eligible. Unknown, automatic, remote-streaming, lobby, recovery, and otherwise ambiguous sources pass through. Eligibility failures also pass through before the original call is withheld.

The Steam continuation path replays the original typed tuple once. Its bypass token is bound to the full request signature, expires quickly, and is revoked if replay throws.

### Vortex access

Discovery and matching use read-only Vortex state. The plugin never uses Vortex state mutation operations and never edits profile or deployment files directly.

Vortex 2.3.0 only applies profile-selection arguments reliably during a cold start. The plugin therefore requires positive deployment confirmation and offers recovery instead of claiming success when an already-running Vortex instance ignores the request. Activation retry force-terminates exact-name `Vortex.exe` processes, verifies that none remain, and only then repeats the held activation.

### Process execution

Custom arguments are parsed without a command shell. The Lua backend delegates captured execution to `backend/util/process_runner.ps1` through the committed Windows-subsystem helper built from `backend/util/process_shell.cs`. The helper validates an absolute executable, passes escaped arguments directly, captures output, and returns the child exit code. Infrastructure-only PowerShell runners use Windows `CREATE_NO_WINDOW` semantics, and captured Vortex process trees additionally run on a private hidden Windows desktop. Detached interactive targets and activation-time process-state checks bypass PowerShell: the Windows-subsystem helper queries process state itself and creates custom targets directly on the user's desktop with hidden `DETACHED_PROCESS` Win32 flags. Broker children also receive the real system command processor rather than the bridge's temporary `ComSpec` override. Detached targets cannot retain the bridge's capture pipes, and Vortex's supported minimized startup mode keeps its main window hidden.

Vortex 2.3.0 separately starts its Console-subsystem `dotnetprobe.exe`, its
main-process `fsutil dirty query` administrator check, and some shell-backed
startup tools through Node without `windowsHide`. The explicitly invoked
`scripts/patch-vortex-dotnetprobe.ps1` compatibility repair validates and backs
up Vortex's complete `app.asar`, replaces the administrator shell with a direct
hidden `fsutil.exe` invocation, adds `windowsHide` to the other exact paths,
and updates the affected ASAR integrity hashes with same-size replacements.
The signed probe remains unchanged and Windows no longer exposes the child
console hosts. This external Vortex repair is never applied implicitly and may
need to be repeated after a Vortex update.

### Data handling

Settings are stored under `%LOCALAPPDATA%\VortexLaunchBridge`. Logs are local. Normal structured events redact paths and launch arguments; diagnostic logging is explicit and should only be enabled while investigating a problem.

Every parser, RPC envelope, path, identifier, output buffer, and asynchronous operation has a validation or size/time boundary.

## Detailed design records

- [Launch hook findings](launch-hook-findings.md)
- [Launch continuation findings](launch-continuation-findings.md)
- [Vortex probe findings](vortex-probe-findings.md)
- [Game matching findings](game-matching-findings.md)
- [Vortex activation findings](vortex-activation-findings.md)
- [Hardening and settings](phase6-hardening-settings.md)
