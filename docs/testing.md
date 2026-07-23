# Testing

## Automated checks

Run the production frontend build and complete regression suite from Windows PowerShell:

```powershell
pnpm install
pnpm run build
pnpm test
```

The test suite covers:

- exact Steam request preservation and one-shot continuation;
- Vortex activation response validation;
- remembered-choice and general settings policy;
- pure-Lua JSON, command-line, settings, parser, cache, matching, and launcher modules;
- hidden process execution and output capture;
- required backend safety guards and RPC envelopes;
- Steam-themed modal actions and responsive settings controls;
- startup cache warming and process-bridge verification.

The GitHub Actions build exercises the Plugin Database's Linux, Node 20, and production-mode build path with the repository's pinned pnpm 10 toolchain. Runtime and Lua integration tests remain Windows-only.

## Manual release matrix

Use a disposable test profile and a game whose expected Vortex deployment state is known.

### Startup and settings

1. Start Steam with Vortex closed.
2. Confirm Vortex Launch Bridge loads without a crash notification.
3. Open the settings panel and verify every control is visible, aligned, and usable at narrow and wide Steam window sizes.
4. Run **Detect Vortex**, **Run read-only probe**, and the game-matching diagnostics.
5. Restart Steam and confirm saved general, per-game, and mapping settings reload.

### Eligible launch prompt

1. Launch a Vortex-managed Steam game with at least one valid profile.
2. Confirm the prompt appears without a multi-second foreground lookup.
3. Confirm it shows the Steam app name, profile count, platform, and AppID.
4. Confirm the close button, **Cancel**, **Continue launching with Steam...**, and **Launch with Vortex** actions are usable.
5. Confirm dismissing or cancelling does not launch the game.

### Steam continuation

1. Choose **Continue launching with Steam...**
2. Confirm the game receives the original Steam launch request exactly once.
3. Repeat with Steam launch options and a supported alternate direct launch source.
4. Confirm the plugin does not describe this action as an unmodded or vanilla launch.

### Vortex activation

1. Fully close Vortex.
2. Choose **Launch with Vortex** and select a profile when prompted.
3. Confirm Vortex starts without visible console windows.
4. Confirm the selected profile deploys before the game target starts.
5. Repeat with an already-running Vortex instance and confirm timeout/recovery is clear and no launch is duplicated.
6. Repeat with a preferred profile and a configured custom executable/arguments.

### Fail-open and recovery

1. Launch a game that Vortex does not manage and confirm Steam launches it normally.
2. Test a managed game with no valid profiles and confirm Steam launches it normally.
3. Temporarily configure an invalid Vortex path, profile ID, game mapping, and custom executable in turn.
4. Confirm invalid configuration is rejected or produces a bounded recovery prompt.
5. Confirm automatic/internal and unsupported launch sources remain untouched.

### Logs and privacy

1. Confirm the backend log is present under `<Steam>\millennium\logs`.
2. Confirm normal logs do not expose full paths or launch arguments.
3. Enable diagnostic logging, reproduce one launch, disable it again, and inspect the result.
4. Unload or disable the plugin and confirm its hooks and timers are disposed.
