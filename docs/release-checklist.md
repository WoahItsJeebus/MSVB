# Release checklist

This checklist prepares a commit for the Steam Client Homebrew Plugin Database. It does not replace the database's current contribution instructions.

## 1. Prepare the repository

- [ ] Review the current [addon submission guide](https://docs.steambrew.app/developers/submitting).
- [ ] Confirm the public repository and default branch contain every required source and binary.
- [ ] Confirm `backend/util/process_shell.exe` is committed alongside its source.
- [ ] Confirm the repository has no credentials, personal paths, local logs, generated test output, or `node_modules`.
- [ ] Review README installation, limitation, troubleshooting, and privacy language.
- [ ] Update `CHANGELOG.md`.

## 2. Synchronize the version

Set the same semantic version in:

- `package.json`
- `plugin.json`
- `frontend/index.tsx`
- `backend/main.lua`

Create the release commit before selecting the Plugin Database submodule revision.

## 3. Validate

From a clean Windows checkout:

```powershell
npm install --global pnpm@10.34.5
pnpm install
pnpm run build
pnpm test
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\build-installer.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-installer-integration.ps1
```

Complete the [manual release matrix](testing.md#manual-release-matrix). Also verify a clean Node 20 Linux environment can run the production build with the repository's pinned package manager:

```sh
corepack prepare pnpm@10.34.5 --activate
NODE_ENV=production pnpm install
NODE_ENV=production pnpm run build
```

## 4. Publish the release

- [ ] Push the release commit to the public default branch.
- [ ] Tag the exact commit as `vX.Y.Z`.
- [ ] Create a GitHub release using the matching changelog section.
- [ ] Upload `artifacts/VortexLaunchBridgeInstaller.exe` to the release and
      record its SHA-256 checksum.
- [ ] Confirm the tag and default branch build successfully.

## 5. Submit or update the database entry

Fork and clone [SteamClientHomebrew/PluginDatabase](https://github.com/SteamClientHomebrew/PluginDatabase), then add this repository as a pinned submodule:

```sh
git submodule add https://github.com/WoahItsJeebus/MSVB.git plugins/vortex-launch-bridge
git add .gitmodules plugins/vortex-launch-bridge
git commit -m "add Vortex Launch Bridge"
```

For later releases, update the existing submodule to the new release commit instead of adding it again. Open a focused pull request to the Plugin Database and include the plugin name, version, purpose, tested environment, and validation results.

The database pins an exact repository commit. Every plugin update therefore needs a new database pull request that advances the submodule pointer.
