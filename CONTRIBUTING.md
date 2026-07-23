# Contributing to Vortex Launch Bridge

Thanks for taking the time to improve the project. Focused bug reports, documentation corrections, and narrowly scoped pull requests are welcome.

## Before opening an issue

1. Check existing issues for the same behavior.
2. Reproduce the problem with the latest version.
3. Confirm whether Vortex was already running.
4. Record the Windows, Steam, Millennium, plugin, and Vortex versions.
5. Reduce logs to the smallest relevant excerpt and remove sensitive local information.

Use the repository's bug-report or feature-request form whenever possible. Security-sensitive reports must follow [SECURITY.md](SECURITY.md).

## Development setup

Development currently requires Windows, Node.js 20, pnpm 10, Windows PowerShell, and Lua 5.1 on `PATH`.

```powershell
git clone https://github.com/WoahItsJeebus/MSVB.git
Set-Location MSVB
npm install --global pnpm@10.34.5
pnpm install
pnpm run build
pnpm test
```

For live Steam testing, close Steam and link the checkout into Millennium's plugin directory as described in the [development installation guide](README.md#development-installation).

## Pull requests

- Keep each pull request focused on one problem.
- Explain the user-visible behavior and the reason for the change.
- Add or update automated tests when behavior changes.
- Update the README, detailed docs, and changelog where relevant.
- Do not weaken fail-open behavior, validation, redaction, or timeout bounds.
- Do not add Vortex mutation commands, shell-based process launching, drive-wide scans, or game-process injection.
- Run `pnpm run build` and `pnpm test` before requesting review.

If the hidden process helper changes, edit `backend/util/process_shell.cs`, run `pnpm run build:process-shell`, and include the rebuilt `backend/util/process_shell.exe` in the same pull request.

## Style

- TypeScript is strict and formatted according to `.prettierrc`.
- Lua code should stay compatible with Millennium's Lua backend.
- Prefer explicit validation and bounded operations at every frontend/backend boundary.
- Keep user-facing text direct, accurate, and clear about Vortex's deployed-state limitations.

By contributing, you agree that your contributions will be licensed under the repository's [MIT License](LICENSE).
