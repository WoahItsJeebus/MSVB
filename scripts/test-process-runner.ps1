$ErrorActionPreference = 'Stop'

$runner = Join-Path (Split-Path -Parent $PSScriptRoot) 'backend\util\process_runner.ps1'
$testRoot = Join-Path $env:TEMP ('vlb-process-runner-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null

function Invoke-Runner {
	param([hashtable]$Request)

	$requestPath = Join-Path $testRoot ([Guid]::NewGuid().ToString('N') + '.json')
	[System.IO.File]::WriteAllText(
		$requestPath,
		($Request | ConvertTo-Json -Depth 8 -Compress),
		(New-Object System.Text.UTF8Encoding($false))
	)
	try {
		$output = & $runner -RequestPath $requestPath
		return $output | ConvertFrom-Json
	}
	finally {
		Remove-Item -LiteralPath $requestPath -Force -ErrorAction SilentlyContinue
	}
}

try {
	$powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
	$processShell = Join-Path (Split-Path -Parent $runner) 'process_shell.exe'
	if (-not (Test-Path -LiteralPath $processShell -PathType Leaf)) {
		throw 'The hidden process shell is missing.'
	}

	$capture = Invoke-Runner @{
		operation = 'process'
		executable = $powershell
		arguments = @(
			'-NoProfile',
			'-NonInteractive',
			'-Command',
			'[Console]::Write("bridge argument with spaces")'
		)
		capture = $true
		timeout_ms = 5000
		maximum_output_bytes = 4096
	}
	if (-not $capture.started -or $capture.timedOut -or
		$capture.exitCode -ne 0 -or
		$capture.stdout -ne 'bridge argument with spaces') {
		throw 'Captured process execution failed.'
	}

	$timeout = Invoke-Runner @{
		operation = 'process'
		executable = $powershell
		arguments = @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 2')
		capture = $true
		timeout_ms = 100
		maximum_output_bytes = 4096
	}
	if (-not $timeout.started -or -not $timeout.timedOut) {
		throw 'Process timeout enforcement failed.'
	}

	$running = Invoke-Runner @{
		operation = 'is_running'
		executable_name = 'powershell.exe'
	}
	if (-not $running.ok -or -not $running.running) {
		throw 'Process detection failed.'
	}

	$sleep = Invoke-Runner @{
		operation = 'sleep'
		milliseconds = 25
	}
	if (-not $sleep.ok) {
		throw 'Bridge sleep failed.'
	}

	$steamRegistry = Invoke-Runner @{
		operation = 'get_steam_install_path'
	}
	if (-not $steamRegistry.ok -or
		$steamRegistry.path -isnot [string] -or
		[string]::IsNullOrWhiteSpace($steamRegistry.path)) {
		throw 'Steam registry isolation failed.'
	}

	$vortexRegistry = Invoke-Runner @{
		operation = 'get_vortex_uninstall_entries'
	}
	if (-not $vortexRegistry.ok -or $null -eq $vortexRegistry.entries) {
		throw 'Vortex registry isolation failed.'
	}

	$originalCommandProcessor = $env:ComSpec
	$env:ComSpec = $processShell
	try {
		& lua (Join-Path (Split-Path -Parent $PSScriptRoot) 'tests\process_shell.lua') `
			"$env:WINDIR\System32\cmd.exe /d /c echo VLB_HIDDEN_SHELL_OK" `
			'VLB_HIDDEN_SHELL_OK'
		if ($LASTEXITCODE -ne 0) {
			throw 'The hidden process shell test failed.'
		}

		$desktopProbe = Join-Path (Split-Path -Parent $PSScriptRoot) 'tests\desktop_probe.ps1'
		$desktopRequestPath = Join-Path $testRoot 'desktop-probe.json'
		$desktopRequest = @{
			operation = 'process'
			executable = $powershell
			arguments = @(
				'-NoProfile',
				'-NonInteractive',
				'-ExecutionPolicy',
				'Bypass',
				'-File',
				$desktopProbe
			)
			capture = $true
			timeout_ms = 10000
			maximum_output_bytes = 4096
		}
		[System.IO.File]::WriteAllText(
			$desktopRequestPath,
			($desktopRequest | ConvertTo-Json -Depth 8 -Compress),
			(New-Object System.Text.UTF8Encoding($false))
		)
		$runnerCommand =
			'"' + $powershell + '"' +
			' -WindowStyle Hidden -NoLogo -NoProfile -NonInteractive' +
			' -ExecutionPolicy Bypass -File "' + $runner + '"' +
			' -RequestPath "' + $desktopRequestPath + '"'
		$desktopJson = (
			& lua `
				(Join-Path (Split-Path -Parent $PSScriptRoot) 'tests\process_shell.lua') `
				$runnerCommand `
				'started' `
				'emit'
		) -join "`n"
		if ($LASTEXITCODE -ne 0) {
			throw 'The hidden desktop process-shell test failed.'
		}
		$desktopResult = $desktopJson | ConvertFrom-Json
		if (-not $desktopResult.started -or
			$desktopResult.exitCode -ne 0 -or
			$desktopResult.stdout -notmatch '^VortexLaunchBridge-') {
			throw 'Captured process trees were not isolated on a hidden desktop.'
		}
	}
	finally {
		$env:ComSpec = $originalCommandProcessor
	}

	Write-Output 'PowerShell process bridge tests passed'
}
finally {
	$resolvedRoot = [System.IO.Path]::GetFullPath($testRoot)
	$resolvedTemp = [System.IO.Path]::GetFullPath($env:TEMP)
	if ($resolvedRoot.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
		[System.IO.Path]::GetFileName($resolvedRoot).StartsWith('vlb-process-runner-')) {
		Remove-Item -LiteralPath $resolvedRoot -Recurse -Force -ErrorAction SilentlyContinue
	}
}
