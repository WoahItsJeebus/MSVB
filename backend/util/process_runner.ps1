param(
	[Parameter(Mandatory = $true)]
	[string]$RequestPath
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

function ConvertTo-NativeArgument {
	param([AllowEmptyString()][string]$Value)

	if ($Value.Length -eq 0) {
		return '""'
	}
	if ($Value -notmatch '[\s"]') {
		return $Value
	}

	$output = New-Object System.Text.StringBuilder
	[void]$output.Append('"')
	$backslashes = 0
	foreach ($character in $Value.ToCharArray()) {
		if ($character -eq '\') {
			$backslashes += 1
		}
		elseif ($character -eq '"') {
			[void]$output.Append((('\' * ($backslashes * 2 + 1)) -join ''))
			[void]$output.Append('"')
			$backslashes = 0
		}
		else {
			if ($backslashes -gt 0) {
				[void]$output.Append((('\' * $backslashes) -join ''))
				$backslashes = 0
			}
			[void]$output.Append($character)
		}
	}
	if ($backslashes -gt 0) {
		[void]$output.Append((('\' * ($backslashes * 2)) -join ''))
	}
	[void]$output.Append('"')
	return $output.ToString()
}

function Limit-Output {
	param(
		[AllowEmptyString()][string]$Value,
		[int]$MaximumBytes
	)

	$bytes = $utf8.GetBytes($Value)
	if ($bytes.Length -le $MaximumBytes) {
		return @{
			value = $Value
			bytes = $bytes.Length
			truncated = $false
		}
	}

	return @{
		value = [System.Text.Encoding]::UTF8.GetString($bytes, 0, $MaximumBytes)
		bytes = $bytes.Length
		truncated = $true
	}
}

function Get-RegistryStringValue {
	param(
		[Microsoft.Win32.RegistryHive]$Hive,
		[Microsoft.Win32.RegistryView]$View,
		[string]$SubKeyPath,
		[string]$ValueName
	)

	$baseKey = $null
	$subKey = $null
	try {
		$baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, $View)
		$subKey = $baseKey.OpenSubKey($SubKeyPath, $false)
		if ($null -eq $subKey) {
			return $null
		}
		$value = $subKey.GetValue($ValueName)
		if ($value -is [string] -and -not [string]::IsNullOrWhiteSpace($value)) {
			return $value
		}
		return $null
	}
	finally {
		if ($null -ne $subKey) {
			$subKey.Dispose()
		}
		if ($null -ne $baseKey) {
			$baseKey.Dispose()
		}
	}
}

function Get-SteamInstallPath {
	$candidates = @(
		@(
			[Microsoft.Win32.RegistryHive]::CurrentUser,
			[Microsoft.Win32.RegistryView]::Registry64,
			'SOFTWARE\Valve\Steam',
			'SteamPath'
		),
		@(
			[Microsoft.Win32.RegistryHive]::LocalMachine,
			[Microsoft.Win32.RegistryView]::Registry32,
			'SOFTWARE\Valve\Steam',
			'InstallPath'
		),
		@(
			[Microsoft.Win32.RegistryHive]::LocalMachine,
			[Microsoft.Win32.RegistryView]::Registry64,
			'SOFTWARE\Valve\Steam',
			'InstallPath'
		)
	)

	foreach ($candidate in $candidates) {
		$value = Get-RegistryStringValue @candidate
		if ($null -ne $value) {
			return $value
		}
	}
	return $null
}

function Get-VortexUninstallEntries {
	$uninstallPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
	$locations = @(
		@(
			[Microsoft.Win32.RegistryHive]::CurrentUser,
			[Microsoft.Win32.RegistryView]::Registry64
		),
		@(
			[Microsoft.Win32.RegistryHive]::CurrentUser,
			[Microsoft.Win32.RegistryView]::Registry32
		),
		@(
			[Microsoft.Win32.RegistryHive]::LocalMachine,
			[Microsoft.Win32.RegistryView]::Registry64
		),
		@(
			[Microsoft.Win32.RegistryHive]::LocalMachine,
			[Microsoft.Win32.RegistryView]::Registry32
		)
	)
	$results = @()

	foreach ($location in $locations) {
		$baseKey = $null
		$uninstallKey = $null
		try {
			$baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
				$location[0],
				$location[1]
			)
			$uninstallKey = $baseKey.OpenSubKey($uninstallPath, $false)
			if ($null -eq $uninstallKey) {
				continue
			}

			foreach ($subKeyName in @($uninstallKey.GetSubKeyNames())) {
				if ($results.Count -ge 64) {
					break
				}
				$entryKey = $null
				try {
					$entryKey = $uninstallKey.OpenSubKey($subKeyName, $false)
					if ($null -eq $entryKey) {
						continue
					}
					$displayName = $entryKey.GetValue('DisplayName')
					if ($displayName -isnot [string] -or
						$displayName.IndexOf(
							'vortex',
							[System.StringComparison]::OrdinalIgnoreCase
						) -lt 0) {
						continue
					}
					$results += @{
						displayName = [string]$displayName
						displayVersion = [string]$entryKey.GetValue('DisplayVersion')
						installLocation = [string]$entryKey.GetValue('InstallLocation')
						displayIcon = [string]$entryKey.GetValue('DisplayIcon')
						uninstallString = [string]$entryKey.GetValue('UninstallString')
					}
				}
				finally {
					if ($null -ne $entryKey) {
						$entryKey.Dispose()
					}
				}
			}
		}
		finally {
			if ($null -ne $uninstallKey) {
				$uninstallKey.Dispose()
			}
			if ($null -ne $baseKey) {
				$baseKey.Dispose()
			}
		}
	}

	return @($results)
}

try {
	$requestText = [System.IO.File]::ReadAllText($RequestPath, $utf8)
	$request = $requestText | ConvertFrom-Json
	if ($request.operation -eq 'sleep') {
		$milliseconds = [Math]::Max(0, [Math]::Min(1000, [int]$request.milliseconds))
		Start-Sleep -Milliseconds $milliseconds
		@{ ok = $true } | ConvertTo-Json -Compress
		exit 0
	}
	if ($request.operation -eq 'is_running') {
		$executableName = [System.IO.Path]::GetFileName([string]$request.executable_name)
		if ($executableName -ne [string]$request.executable_name -or
			$executableName -notmatch '^[A-Za-z0-9._-]+\.exe$') {
			throw 'The process name is invalid.'
		}
		$processName = [System.IO.Path]::GetFileNameWithoutExtension($executableName)
		@{
			ok = $true
			running = @(Get-Process -Name $processName -ErrorAction SilentlyContinue).Count -gt 0
		} | ConvertTo-Json -Compress
		exit 0
	}
	if ($request.operation -eq 'get_steam_install_path') {
		@{
			ok = $true
			path = Get-SteamInstallPath
		} | ConvertTo-Json -Compress
		exit 0
	}
	if ($request.operation -eq 'get_vortex_uninstall_entries') {
		@{
			ok = $true
			entries = @(Get-VortexUninstallEntries)
		} | ConvertTo-Json -Depth 4 -Compress
		exit 0
	}

	if ($request.operation -ne 'process') {
		throw 'Unknown process-runner operation.'
	}

	$executable = [string]$request.executable
	if (-not [System.IO.Path]::IsPathRooted($executable) -or
		-not [System.IO.File]::Exists($executable)) {
		throw 'The requested executable is unavailable.'
	}

	$argumentValues =
		if ($null -eq $request.arguments -or
			($request.arguments -is [PSCustomObject] -and
				$request.arguments.PSObject.Properties.Count -eq 0)) {
			@()
		}
		else {
			@($request.arguments)
		}
	$arguments = $argumentValues |
		ForEach-Object { ConvertTo-NativeArgument ([string]$_) }
	$capture = [bool]$request.capture
	$timeoutMs = [Math]::Max(100, [Math]::Min(120000, [int]$request.timeout_ms))
	$maximumBytes = [Math]::Max(4096, [Math]::Min(4194304, [int]$request.maximum_output_bytes))
	$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

	if (-not $capture) {
		# Start-Process gives an interactive target independent standard
		# handles. Using ProcessStartInfo here would let the target inherit this
		# runner's captured handles and keep the outer broker blocked until the
		# target itself exited. Explicit hidden window state also prevents a
		# console-subsystem launcher from briefly showing a terminal before its
		# GUI or background process takes over.
		$process = Start-Process `
			-FilePath $executable `
			-ArgumentList ($arguments -join ' ') `
			-WindowStyle Hidden `
			-PassThru
		if ($null -eq $process) {
			throw 'The process did not start.'
		}
		@{
			started = $true
			processId = $process.Id
			durationMs = $stopwatch.ElapsedMilliseconds
		} | ConvertTo-Json -Compress
		$process.Dispose()
		exit 0
	}

	$startInfo = New-Object System.Diagnostics.ProcessStartInfo
	$startInfo.FileName = $executable
	$startInfo.Arguments = $arguments -join ' '
	$startInfo.UseShellExecute = $false
	$startInfo.CreateNoWindow = $true
	$startInfo.RedirectStandardOutput = $true
	$startInfo.RedirectStandardError = $true
	$startInfo.StandardOutputEncoding = $utf8
	$startInfo.StandardErrorEncoding = $utf8

	$process = New-Object System.Diagnostics.Process
	$process.StartInfo = $startInfo
	if (-not $process.Start()) {
		throw 'The process did not start.'
	}

	$stdoutTask = $process.StandardOutput.ReadToEndAsync()
	$stderrTask = $process.StandardError.ReadToEndAsync()
	$timedOut = -not $process.WaitForExit($timeoutMs)
	if ($timedOut) {
		try {
			$process.Kill()
			$process.WaitForExit(1000) | Out-Null
		}
		catch {
			# The structured timeout result below remains authoritative.
		}
	}
	else {
		$process.WaitForExit()
	}

	$stdout = $stdoutTask.GetAwaiter().GetResult()
	$stderr = $stderrTask.GetAwaiter().GetResult()
	$stdoutResult = Limit-Output $stdout $maximumBytes
	$stderrResult = Limit-Output $stderr $maximumBytes
	$exitCode = if ($process.HasExited) { $process.ExitCode } else { $null }

	@{
		started = $true
		timedOut = $timedOut
		exitCode = $exitCode
		durationMs = $stopwatch.ElapsedMilliseconds
		stdout = $stdoutResult.value
		stderr = $stderrResult.value
		stdoutBytes = $stdoutResult.bytes
		stderrBytes = $stderrResult.bytes
		stdoutTruncated = $stdoutResult.truncated
		stderrTruncated = $stderrResult.truncated
	} | ConvertTo-Json -Compress
	$process.Dispose()
}
catch {
	@{
		started = $false
		error = $_.Exception.Message
	} | ConvertTo-Json -Compress
	exit 1
}
