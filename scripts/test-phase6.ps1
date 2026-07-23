$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $repositoryRoot '.millennium\Phase6Tests'
$compiler = Join-Path $repositoryRoot 'node_modules\.bin\tsc.cmd'

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

Push-Location $repositoryRoot
try {
	& $compiler `
		'tests\launch_continuation.ts' `
		'tests\vortex_activation.ts' `
		'tests\settings_policy.ts' `
		'frontend\launch\LaunchBypass.ts' `
		'frontend\launch\LaunchRequest.ts' `
		'frontend\launch\SteamLauncher.ts' `
		'frontend\settings\LaunchPolicy.ts' `
		'frontend\settings\SettingsTypes.ts' `
		'frontend\vortex\VortexTypes.ts' `
		--module commonjs `
		--target ES2020 `
		--moduleResolution node `
		--strict `
		--esModuleInterop `
		--skipLibCheck `
		--outDir $outputDirectory
	if ($LASTEXITCODE -ne 0) {
		exit $LASTEXITCODE
	}

	[System.IO.File]::WriteAllText(
		(Join-Path $outputDirectory 'package.json'),
		'{"type":"commonjs"}'
	)

	node (Join-Path $outputDirectory 'tests\launch_continuation.js')
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	node (Join-Path $outputDirectory 'tests\vortex_activation.js')
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	node (Join-Path $outputDirectory 'tests\settings_policy.js')
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

	lua tests\command_line.lua
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	lua tests\settings.lua
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	lua tests\vortex_parsers.lua
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	lua tests\game_matching.lua
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	lua tests\vortex_launcher.lua
	exit $LASTEXITCODE
}
finally {
	Pop-Location
}
