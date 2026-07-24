# Changelog

All notable changes to Vortex Launch Bridge are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

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

## [0.7.15] - 2026-07-23

### Fixed

- Applied Windows `CREATE_NO_WINDOW` semantics to the bridge's registry and process-state runner, eliminating the remaining PowerShell console flashes during Steam startup and periodic cache refreshes.

## [0.7.14] - 2026-07-23

### Fixed

- Isolated captured Vortex CLI process trees on a private hidden Windows desktop, preventing console-based Vortex helpers from flashing terminal windows during startup and five-minute cache refreshes.
- Added regression coverage that verifies captured process trees actually inherit the private desktop.

## [0.7.13] - 2026-07-23

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

[Unreleased]: https://github.com/WoahItsJeebus/MSVB/compare/v0.7.15...HEAD
[0.7.15]: https://github.com/WoahItsJeebus/MSVB/compare/v0.7.14...v0.7.15
[0.7.14]: https://github.com/WoahItsJeebus/MSVB/compare/v0.7.13...v0.7.14
[0.7.13]: https://github.com/WoahItsJeebus/MSVB/releases/tag/v0.7.13
