$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $repositoryRoot '.millennium\Phase5Tests'
$compiler = Join-Path $repositoryRoot 'node_modules\.bin\tsc.cmd'
$testEntry = Join-Path $outputDirectory 'tests\vortex_activation.js'

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

Push-Location $repositoryRoot
try {
	& $compiler `
		'tests\vortex_activation.ts' `
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
	node $testEntry
	exit $LASTEXITCODE
}
finally {
	Pop-Location
}
