# Changelog

All notable changes to Vortex Launch Bridge are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/).

## 1.0.6 - 2026-08-01

### Fixed

- Refreshed Vortex's read-only game and profile snapshot on every supported
  Steam PLAY request, allowing profiles added since Steam startup to appear as
  soon as Vortex is closed and its safe state query can run.
- Removed the five-second post-cancel launch suppression and made every newer
  supported launch request immediately close and supersede the older pending
  prompt or lookup.

## 1.0.5 - 2026-07-31

### Fixed

- Added a Retry action to Vortex activation failures that force-closes every
  running Vortex instance, verifies shutdown, and repeats the held profile
  activation without requiring Steam to restart.
- Aligned the widened Vortex detection action with Clear Override by offsetting
  its full 32-pixel horizontal-padding expansion.
- Added consistent horizontal padding to the Vortex detection and read-only
  probe buttons in the settings panel.
- Accepted opaque Vortex profile IDs that begin with a hyphen, allowing valid
  generated profiles to reach Vortex activation.
- Applied the compact action-button height to two-button recovery dialogs as
  well as the initial three-button launch prompt.
- Prevented detached Vortex processes from inheriting the bridge's captured
  output handles, allowing activation RPCs to return while Vortex remains open.
- Activated a game's last-used profile through Vortex's reliable game-selection
  startup path, avoiding its cold-start profile/recovery race.
- Started Vortex with its supported minimized flag so profile activation and
  deployment can run without leaving its main window visible.
- Recognized Vortex's already-active profile completion record so last-used
  profiles no longer wait for a switch event that Vortex does not emit.
- Kept activation waits below Millennium's 30-second child-RPC deadline so a
  real Vortex timeout reaches the recovery dialog instead of appearing as an
  unavailable backend.
- Explicitly launched detached Vortex targets with hidden window state,
  preventing console-subsystem launchers from briefly flashing a terminal.
- Replaced the broker's normal PowerShell start with native
  `CREATE_NO_WINDOW` process creation, preventing Windows from allocating a
  transient `conhost.exe` during activation polling.
- Removed PowerShell from detached Vortex startup entirely; the Windows
  subsystem broker now creates the interactive target directly with hidden,
  `DETACHED_PROCESS` Win32 startup flags so Windows cannot provision a console
  host for it.
- Moved activation-time Vortex process checks into that broker as well, removing
  the last repeated PowerShell/conhost process path from profile launches.
- Classified an already-running Vortex cache refresh as an informational safety
  skip when a prior cache is available, instead of emitting misleading backend
  and frontend failure warnings.
- Added a guarded Vortex 2.3.0 renderer compatibility repair that supplies
  Node's missing `windowsHide` option for `dotnetprobe.exe`, updates the ASAR
  integrity hashes without changing its layout, and preserves the signed probe.
- Restored the system command processor in broker children, preventing Vortex
  and its extensions from inheriting the bridge's temporary `ComSpec` override.
- Reused an already-running Vortex instance when its latest bounded log state
  exactly confirms the requested game and last-active profile, avoiding a
  timeout caused by Vortex 2.3.0 ignoring redundant second-instance arguments.
- Removed an overriding raw `CreateProcessW` launch path that used default
  console creation flags, ensuring Vortex activation and custom targets always
  use the Windows-subsystem broker's hidden, detached startup path.
- Extended the guarded Vortex renderer repair to apply `windowsHide` to its
  shared executable-spawn wrapper, preventing `shell: true` startup tools from
  briefly exposing `cmd.exe` and `conhost.exe` during cold activation.
- Removed the command shell from Vortex's main-process `fsutil dirty query`
  administrator check and hid the direct executable, eliminating the remaining
  `cmd.exe` console race before its renderer initialized.

## 1.0.4 - 2026-07-25

### Fixed

- Applied Windows `CREATE_NO_WINDOW` semantics to the bridge's registry and process-state runner, eliminating the remaining PowerShell console flashes during Steam startup and periodic cache refreshes.

## 0.7.14 - 2026-07-23

### Fixed

- Isolated captured Vortex CLI process trees on a private hidden Windows desktop, preventing console-based Vortex helpers from flashing terminal windows during startup and five-minute cache refreshes.
- Added regression coverage that verifies captured process trees actually inherit the private desktop.

## 0.7.13 - 2026-07-23

### Added

- Steam launch interception for verified direct launch sources.
- Read-only Vortex detection, profile discovery, and Steam game matching.
- Background Vortex state caching for immediate eligibility decisions.
- A Steam-themed launch prompt with Vortex, Steam continuation, and cancel actions.
- Vortex profile activation with bounded deployment confirmation.
- Per-game preferred profiles, remembered choices, custom launch targets, and exact game-ID mappings.
- Local settings, redacted logging, recovery paths, and automated regression coverage.

### Security

- Bounded JSON and command-line parsing.
- Shell-free process argument handling through a committed Windows-subsystem helper.
- Strict validation for paths, AppIDs, profile IDs, game IDs, settings, and backend RPC envelopes.

### Known limitations

- Vortex 2.3.0 may ignore profile-selection arguments when it is already running. A cold Vortex start is required for confirmed activation.
- Continuing through Steam does not undeploy Vortex-managed files and therefore does not guarantee an unmodded launch.
- Only verified direct Steam launch sources are intercepted; unsupported and ambiguous routes pass through unchanged.
