# Codex Project Handoff: Steam–Vortex Launch Bridge

## Project summary

Create a Windows-first Millennium plugin for the desktop Steam client.

When the user requests that Steam launch a game, the plugin should determine whether that game is managed by Vortex and has at least one Vortex profile.

When a matching Vortex profile exists, show a Steam-native modal with these choices:

* `Launch with Vortex`
* `Continue launching with Steam...`

Do not use wording such as “Launch normally,” “Normal launch,” or “Launch vanilla.”

The Steam option does not guarantee an unmodded game. It means only that the plugin resumes Steam’s original launch request without asking Vortex to change or activate anything.

## Working name

Use this temporary working name unless the repository already has a name:

* Display name: `Vortex Launch Bridge`
* Internal plugin name: `vortex-launch-bridge`

The name can be changed later without redesigning the project.

## Target environment

* Operating system: Windows 10 and newer
* Host: Desktop Steam client
* Plugin framework: Millennium
* Starting point: official `SteamClientHomebrew/PluginTemplate`
* Frontend: TypeScript and React
* Backend: Lua
* Backend enabled in `plugin.json`
* Do not introduce Python
* Do not modify Millennium itself
* Do not modify Vortex itself

Use the current APIs and conventions present in the checked-out Millennium template. Do not assume examples from old Decky or old Millennium versions remain compatible.

## Core user flow

1. The user requests a game launch through Steam.
2. The plugin obtains the Steam AppID and original launch information.
3. The plugin checks whether Vortex is installed.
4. The plugin checks whether the requested Steam game maps to a Vortex-managed game.
5. The plugin checks whether that Vortex game has one or more profiles.
6. If no relevant profile exists, Steam continues without displaying anything.
7. If a profile exists, interrupt or suspend the original launch and display a modal.
8. The modal offers:

   * `Launch with Vortex`
   * `Continue launching with Steam...`
9. If the user chooses Steam, resume the original Steam launch exactly once.
10. If the user chooses Vortex:

    * cancel the original Steam launch;
    * activate the selected Vortex game/profile;
    * wait for Vortex activation or deployment when a dependable readiness signal exists;
    * launch the appropriate game executable or Steam AppID.
11. If several Vortex profiles exist, let the user choose one before continuing.

## Required semantics

### Continue launching with Steam...

This must resume the original Steam launch request as faithfully as possible.

Preserve:

* Steam AppID
* launch options
* launch source
* selected Steam launch option, where available
* any other relevant parameters captured from the original request

The resumed call must bypass this plugin’s interception once. It must not reopen the modal recursively.

Implement an explicit bypass mechanism, such as:

* a one-shot AppID token;
* a short-lived request identifier;
* or a guarded internal call around the preserved original launch function.

Do not disable interception globally while resuming a launch.

### Launch with Vortex

This means:

* activate the appropriate Vortex game;
* activate the chosen Vortex profile;
* allow Vortex to perform any necessary profile/deployment work;
* then launch the game through the best available launch target.

The initial implementation may launch the Steam AppID after activating the profile.

The architecture must leave room for games that require:

* script extenders;
* custom Vortex tools;
* alternate executables;
* launch arguments;
* a user-configured executable.

Do not assume that launching the base Steam executable is correct for every Vortex game.

### Modal dismissal

Treat explicit dismissal of the modal as cancellation of the pending launch.

Do not interpret the close button or Escape key as choosing Steam.

For internal plugin errors, fail open where reasonably safe. A plugin failure must not permanently break the Steam Play button.

## Important distinction

Do not describe `Continue launching with Steam...` as any of the following:

* vanilla
* unmodded
* mods disabled
* clean launch

Vortex may already have deployed mods into or around the game installation. Continuing through Steam does not undo those changes.

## Architecture

### Frontend responsibilities

The TypeScript frontend should handle:

* registering and unregistering Steam launch hooks;
* collecting Steam launch-request information;
* opening Steam-native dialogs;
* displaying profile choices;
* maintaining the one-shot launch bypass;
* calling the Lua backend;
* resuming the preserved Steam launch;
* displaying concise errors;
* recording structured diagnostic logs.

The launch interception should live in or be initialized from SharedJSContext.

Prefer Steam/Millennium UI components rather than custom HTML when practical.

Expected components may include:

* `showModal`
* `ConfirmModal`
* Steam dialog buttons
* dropdown or list components for profile selection

Use the APIs available in the current template rather than copying old imports blindly.

### Backend responsibilities

The Lua backend should handle:

* detecting Vortex;
* validating the Vortex executable;
* querying Vortex state;
* finding Vortex profiles;
* reading Steam app manifests when needed;
* matching Steam installations to Vortex games;
* starting Vortex with a selected game/profile;
* launching configured tools or executables later;
* persisting plugin settings;
* returning structured results to TypeScript.

The backend must call `millennium.ready()` promptly. Expensive filesystem scans or Vortex queries must happen after readiness.

### Suggested frontend modules

```text
frontend/
  index.tsx
  launch/
    LaunchInterceptor.ts
    LaunchRequest.ts
    LaunchBypass.ts
    SteamLauncher.ts
  vortex/
    VortexClient.ts
    VortexTypes.ts
  ui/
    LaunchChoiceModal.tsx
    ProfileChoiceModal.tsx
    ErrorModal.tsx
  settings/
    Settings.ts
    SettingsPanel.tsx
  logging/
    Logger.ts
```

Adapt this layout to the actual template rather than forcing it where inappropriate.

### Suggested backend modules

```text
backend/
  main.lua
  vortex/
    detection.lua
    cli.lua
    profiles.lua
    launcher.lua
  steam/
    manifests.lua
    libraries.lua
  matching/
    game_matcher.lua
  settings/
    settings.lua
  util/
    process.lua
    paths.lua
    json.lua
    logging.lua
```

Avoid one enormous backend file.

## Data contracts

Define explicit shared result shapes.

Example Vortex installation result:

```ts
interface VortexInstallation {
    found: boolean;
    executablePath?: string;
    source?: "registry" | "known-path" | "configured";
    version?: string;
    error?: string;
}
```

Example profile:

```ts
interface VortexProfile {
    id: string;
    name: string;
    gameId: string;
    enabledModCount?: number;
    isLastActive?: boolean;
}
```

Example match result:

```ts
interface VortexGameMatch {
    matched: boolean;
    confidence: "exact-path" | "steam-id" | "configured" | "none";
    steamAppId: number;
    steamInstallPath?: string;
    vortexGameId?: string;
    vortexGamePath?: string;
    profiles: VortexProfile[];
    warning?: string;
}
```

Example captured launch request:

```ts
interface SteamLaunchRequest {
    appId: string;
    launchOptions: string;
    launchSource?: number;
    gameActionId?: number;
    action?: string;
    requestedAction?: string;
    capturedAt: number;
}
```

Adjust fields to match values actually observed from Steam.

Do not invent values simply to satisfy these interfaces.

## Vortex detection strategy

Implement detection in this order:

1. User-configured executable path.
2. Windows uninstall/application registry information, if the Lua environment provides a safe supported way to query it.
3. Known installation-path candidates.
4. Search only a small number of sensible locations.
5. Do not recursively scan entire drives.

Validate candidates by checking:

* the file exists;
* it appears to be an executable;
* its name/path is plausible;
* optionally, invoking a harmless version or state query succeeds.

Cache the successful Vortex path.

Provide a settings override because Vortex may be installed in a custom location.

## Vortex profile querying

Prefer Vortex’s command-line interface over editing Vortex data files.

Known command-line capabilities to investigate include:

```text
--get <state-path>
--game <game-id>
--profile <profile-id>
--start-minimized
```

Do not assume the exact Vortex state paths or output format without testing them against the installed Vortex version.

Likely areas to investigate include Vortex’s persistent profiles and discovered-game state, but first create a probe that records:

* command executed;
* exit code;
* stdout;
* stderr;
* whether Vortex was already running;
* whether the command starts another instance;
* output encoding;
* whether output is valid JSON.

Never log personal paths or profile data at normal log level without redaction.

Do not use `--set` or `--del`.

Do not directly mutate Vortex’s database or state files.

## Steam-to-Vortex matching

Use deterministic matching in this order:

1. Explicit user mapping from Steam AppID to Vortex game ID.
2. Vortex-provided Steam/store identifier, if available.
3. Exact normalized installation-path match.
4. Exact executable-path match.
5. No match.

Do not use game titles as the primary matching mechanism.

Title matching may be offered only as a diagnostic suggestion requiring user confirmation.

Normalize paths by:

* resolving separators;
* removing trailing separators;
* comparing case-insensitively on Windows;
* resolving obvious relative segments;
* avoiding assumptions about symbolic links or junctions.

Steam installation paths may be obtained using:

* Steam application details exposed by the client;
* Steam library-folder configuration;
* `appmanifest_<appid>.acf`;
* or a combination of these.

Prefer Steam’s exposed client data when dependable. Use manifest parsing as a backend fallback.

## Launch interception research

Steam launch behavior is undocumented and may vary by launch source.

Investigate at least:

* Library Play button
* double-clicking a library entry
* desktop Steam shortcut
* `steam://run/<appid>`
* system-tray recent game
* Big Picture mode, if practical
* games with Steam launch-option selection dialogs

Potential APIs to inspect include:

* `SteamClient.Apps.RegisterForGameActionUserRequest`
* `SteamClient.Apps.RegisterForGameActionStart`
* `SteamClient.Apps.RegisterForGameActionTaskChange`
* `SteamClient.Apps.GetGameActionDetails`
* `SteamClient.Apps.CancelLaunch`
* `SteamClient.Apps.RunGame`

Do not assume that an event callback occurs early enough to prevent process creation.

Do not patch multiple launch APIs simultaneously until their event order is known.

Store unregisterable callback handles and remove every hook during plugin unload.

## Race-condition protection

The plugin must account for:

* rapid double-clicks on Play;
* repeated Steam events for one launch;
* a second game being launched while a prompt is open;
* the same AppID producing several action callbacks;
* Vortex already running;
* Vortex starting slowly;
* the game starting before cancellation;
* Steam retrying the launch;
* the resumed launch being intercepted again.

Maintain pending requests by a stable identifier where available.

At minimum, use:

* AppID;
* game action ID;
* capture timestamp;
* request state.

Suggested request states:

```text
observed
checking-vortex
awaiting-user
continuing-steam
activating-vortex
launching
cancelled
completed
failed
```

Never show duplicate modals for the same pending Steam action.

## Error behavior

### Before displaying a modal

If Vortex detection or profile checking fails:

* log the error;
* allow Steam to continue;
* do not show a blocking error unless debugging is enabled.

### After the original launch has been cancelled

If Vortex activation fails:

* show an error with:

  * `Continue launching with Steam...`
  * `Cancel`
* do not silently leave the user stranded.

### Backend unavailable

If the Lua backend cannot be reached:

* do not intercept future launches;
* log a prominent plugin error;
* leave Steam launch behavior untouched.

## Settings planned for later

Create the settings model now, but a full UI is not required in the first implementation.

Planned settings:

* Vortex executable path
* Always ask
* Remember choice per game
* Preferred profile per game
* Preferred launch target per game
* Custom executable per game
* Custom arguments per game
* Vortex activation timeout
* Enable diagnostic logging
* Clear remembered choices
* Steam AppID to Vortex game-ID overrides

Default behavior:

* Always ask when a matching profile exists.
* Do not remember a choice unless explicitly enabled.
* Do not prompt for games without profiles.
* Do not prompt when Vortex is unavailable.
* Fail open before cancellation.
* Do not automatically purge or disable mods.

## Implementation phases

### Phase 0: Scaffold and verify the environment

Goals:

* initialize the repository from the current official Millennium PluginTemplate;
* rename template metadata;
* enable the Lua backend;
* verify frontend-to-backend communication;
* add structured logging;
* add a README with local development instructions;
* make no Steam launch changes.

Acceptance criteria:

* plugin loads without errors;
* Lua backend calls `millennium.ready()`;
* frontend can call a trivial backend health method;
* backend returns platform and plugin-version information;
* plugin unloads cleanly.

### Phase 1: Launch-hook instrumentation

Goals:

* observe Steam launch requests without cancelling or delaying them;
* log callback order and parameters;
* test several launch routes;
* determine the safest interception point.

Requirements:

* do not call `CancelLaunch`;
* do not replace normal launch behavior;
* do not show the Vortex prompt yet;
* redact sensitive launch arguments where appropriate;
* deduplicate obviously repeated callbacks;
* unregister hooks on unload.

Deliver a diagnostic summary containing:

* event order;
* callback parameters;
* whether an AppID is always present;
* whether a game action ID is present;
* whether `RunGame` is directly invoked;
* behavior from each tested launch route;
* recommended interception strategy;
* unresolved risks.

Stop after Phase 1 and report findings before implementing launch cancellation.

### Phase 2: Vortex backend probe

Goals:

* detect the Vortex executable;
* validate harmless CLI invocation;
* discover the installed Vortex version where possible;
* test read-only `--get` commands;
* determine profile and discovered-game state shapes.

Do not integrate Steam interception yet.

Acceptance criteria:

* Vortex installation is detected or reported as absent;
* commands have timeouts;
* stdout/stderr/exit codes are captured;
* no Vortex state is modified;
* profile data can be converted into stable internal objects.

### Phase 3: Game matching

Goals:

* resolve a Steam AppID to an installation path;
* resolve Vortex discovered games;
* match games deterministically;
* return matching profiles.

Acceptance criteria:

* exact-path matching works;
* user override structure exists;
* ambiguous matches are rejected rather than guessed;
* no title-only automatic match is used.

### Phase 4: Steam modal and safe continuation

Goals:

* intercept one confirmed-safe launch route;
* display the Steam-native modal;
* implement `Continue launching with Steam...`;
* prevent recursion.

Acceptance criteria:

* the exact button label is used;
* choosing Steam launches exactly once;
* dismissing the modal cancels the pending launch;
* launches without Vortex profiles are unaffected;
* duplicate prompts do not appear.

### Phase 5: Vortex profile activation

Goals:

* add profile selection;
* start or focus Vortex;
* activate the selected game/profile;
* launch the game after activation.

Acceptance criteria:

* a selected profile becomes active;
* activation has timeout/error handling;
* failure offers `Continue launching with Steam...`;
* no Vortex state files are directly edited.

### Phase 6: Hardening and settings

Goals:

* support additional Steam launch routes;
* add remembered choices;
* add custom launch tools;
* improve logs and error recovery;
* add settings UI;
* write tests for pure matching/parsing modules.

## First Codex assignment

Implement only Phase 0 and Phase 1.

Do not implement Vortex integration yet.

Before writing launch hooks:

1. inspect the current PluginTemplate;
2. inspect current Millennium type definitions;
3. locate the current `SteamClient.Apps` typings;
4. document which APIs are typed and which require runtime probing;
5. preserve compatibility with the currently installed template dependencies.

Produce:

* working plugin scaffold;
* frontend/backend health check;
* launch instrumentation;
* cleanup/unload behavior;
* README;
* `docs/launch-hook-findings.md`;
* concise list of manual tests for the user.

Do not claim launch interception is solved until runtime logs demonstrate the event order.

## Code-quality requirements

* TypeScript strict mode where supported.
* No `any` unless Steam exposes genuinely unknown data; isolate and validate it.
* Use narrow interfaces for backend results.
* Validate all data crossing Lua/TypeScript boundaries.
* Add timeouts to process calls.
* Quote Windows command arguments correctly.
* Never interpolate untrusted strings directly into a shell command.
* Prefer direct process execution over `cmd.exe`.
* Redact sensitive command-line values from logs.
* Use structured log prefixes.
* Keep pure parsing and matching logic separate from host API calls.
* Explain undocumented Steam behavior in comments.
* Do not add speculative abstractions without a current use.
* Do not swallow errors silently.
* Do not block Steam’s UI thread with filesystem or process work.

## Non-goals for the first release

* Purging Vortex mods before a Steam launch
* Guaranteeing a vanilla launch
* Linux or macOS Vortex support
* Supporting every script extender automatically
* Mod installation or downloading
* Editing Vortex profiles
* Changing active mods
* Managing Nexus Mods accounts
* Launching non-Steam Vortex games
* Replacing Vortex
* Modifying Steam binaries
* Injecting into game processes

## Definition of MVP success

The MVP succeeds when:

1. A Steam game with no matching Vortex profile launches unchanged.
2. A Steam game with a matching Vortex profile displays one modal.
3. The modal contains:

   * `Launch with Vortex`
   * `Continue launching with Steam...`
4. Choosing Steam resumes the original request once.
5. Choosing Vortex activates the selected profile and launches through the configured target.
6. Errors do not permanently break Steam launching.
7. The plugin never describes the Steam option as vanilla or unmodded.
