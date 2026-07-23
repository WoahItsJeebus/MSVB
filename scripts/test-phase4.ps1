$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $repositoryRoot '.millennium\Phase4Tests'
$compiler = Join-Path $repositoryRoot 'node_modules\.bin\tsc.cmd'
$testEntry = Join-Path $outputDirectory 'tests\launch_continuation.js'

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

Push-Location $repositoryRoot
try {
	& $compiler `
		'tests\launch_continuation.ts' `
		'frontend\launch\LaunchBypass.ts' `
		'frontend\launch\LaunchRequest.ts' `
		'frontend\launch\SteamLauncher.ts' `
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
	node $testEntry
	exit $LASTEXITCODE
}
finally {
	Pop-Location
}
