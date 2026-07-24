$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$outputDirectory = Join-Path $repositoryRoot '.millennium\Phase6Tests'
$compiler = Join-Path $repositoryRoot 'node_modules\.bin\tsc.cmd'

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

Push-Location $repositoryRoot
try {
	$unsupportedJsonImports = Get-ChildItem -LiteralPath 'backend' -Recurse -Filter '*.lua' |
		Select-String -SimpleMatch 'require("cjson")'
	if ($unsupportedJsonImports) {
		throw 'Backend contains require("cjson"); current Millennium exposes require("json").'
	}
	$nativeJsonImports = Get-ChildItem -LiteralPath 'backend' -Recurse -Filter '*.lua' |
		Select-String -Pattern 'require\(["'']json["'']\)'
	if ($nativeJsonImports) {
		throw 'Backend must not call Millennium native JSON from an RPC handler.'
	}

	$backendMain = Get-Content -LiteralPath 'backend\main.lua' -Raw
	$packageVersion = (Get-Content -LiteralPath 'package.json' -Raw | ConvertFrom-Json).version
	$manifestVersion = (Get-Content -LiteralPath 'plugin.json' -Raw | ConvertFrom-Json).version
	$escapedVersion = [regex]::Escape($packageVersion)
	$frontendIndexSource = Get-Content -LiteralPath 'frontend\index.tsx' -Raw
	$readmeSource = Get-Content -LiteralPath 'README.md' -Raw
	$changelogSource = Get-Content -LiteralPath 'CHANGELOG.md' -Raw
	if ($manifestVersion -ne $packageVersion -or
		$backendMain -notmatch "PLUGIN_VERSION\s*=\s*`"$escapedVersion`"" -or
		$frontendIndexSource -notmatch "const PLUGIN_VERSION\s*=\s*'$escapedVersion'" -or
		$readmeSource -notmatch "version-$escapedVersion-" -or
		$changelogSource -notmatch "(?m)^## \[$escapedVersion\]") {
		throw "Current version references must match package.json version $packageVersion."
	}
	if ($backendMain -notmatch 'pcall\(jit\.off\)') {
		throw 'Backend must disable LuaJIT before loading plugin modules.'
	}
	if ($backendMain -match 'json\.encode') {
		throw 'Backend RPC responses must use the bounded pure-Lua JSON encoder.'
	}
	if (-not (Test-Path -LiteralPath 'backend\util\process_runner.ps1')) {
		throw 'The packaged process runner is missing.'
	}
	if (-not (Test-Path -LiteralPath 'backend\util\process_shell.exe')) {
		throw 'The hidden process shell is missing.'
	}
	$processShellSource = Get-Content -LiteralPath 'backend\util\process_shell.cs' -Raw
	if ($processShellSource -notmatch 'CreateNoWindow\s*=\s*true' -or
		$processShellSource -notmatch 'WindowStyle\s*=\s*ProcessWindowStyle\.Hidden' -or
		$processShellSource -notmatch 'CreateDesktop\(' -or
		$processShellSource -notmatch 'CreateProcess\(' -or
		$processShellSource -notmatch 'desktop\s*=\s*desktopName' -or
		-not $processShellSource.Contains('\"capture\":true')) {
		throw 'Bridge runners must suppress consoles, and captured process trees must run on a hidden desktop.'
	}
	if ($backendMain -notmatch 'function\s+verify_process_bridge\(\)') {
		throw 'Backend startup must expose process bridge verification.'
	}
	if ($backendMain -notmatch 'function\s+record_frontend_log\(request_json\)') {
		throw 'Backend must expose the bounded frontend log sink.'
	}
	if ($backendMain -notmatch 'function\s+warm_vortex_state_cache\(\)' -or
		$backendMain -notmatch 'vortex_state_cache\.get\(\)') {
		throw 'Backend must warm and consume the read-only Vortex state cache.'
	}

	$launchInterceptor = Get-Content -LiteralPath 'frontend\launch\LaunchInterceptor.tsx' -Raw
	if ($launchInterceptor -notmatch 'return\s+showModal\(modal,\s*window,\s*props\)') {
		throw 'Launch modals must use the desktop SharedJS window explicitly.'
	}
	if ([regex]::Matches($launchInterceptor, '\bshowModal\(').Count -ne 1) {
		throw 'Launch modal call sites must use the guarded desktop modal helper.'
	}

	$launchChoiceModal = Get-Content -LiteralPath 'frontend\ui\LaunchChoiceModal.tsx' -Raw
	if ($launchChoiceModal -notmatch '<ConfirmModal' -or
		$launchChoiceModal -notmatch 'strTitle="Vortex Launch Bridge"' -or
		$launchChoiceModal -notmatch 'strOKButtonText="Launch with Vortex"' -or
		$launchChoiceModal -notmatch 'strMiddleButtonText="Continue launching with Steam\.\.\."' -or
		$launchChoiceModal -notmatch 'strCancelButtonText="Cancel"' -or
		$launchChoiceModal -notmatch 'onMiddleButton=\{onContinueWithSteam\}' -or
		$launchChoiceModal -notmatch 'onCancel=\{onCancel\}') {
		throw 'Launch choice must use the themed Steam confirmation modal and exact action labels.'
	}
	if ($launchInterceptor -notmatch 'popupWidth:\s*720') {
		throw 'The three-action launch modal must request enough width for single-line action labels.'
	}

	$steamModalChrome = Get-Content -LiteralPath 'frontend\ui\SteamModalChrome.tsx' -Raw
	if ($steamModalChrome -notmatch 'height:\s*42px\s*!important' -or
		$steamModalChrome -notmatch 'padding-inline:\s*14px\s*!important' -or
		$steamModalChrome -notmatch 'DialogTwoColLayout\s*>\s*button\.DialogButton' -or
		$steamModalChrome -notmatch 'DialogThreeColLayout\s*>\s*button\.DialogButton') {
		throw 'Two- and three-action launch modal buttons must retain compact sizing.'
	}

	$responsivePanels = @(
		'frontend\settings\SettingsPanel.tsx',
		'frontend\vortex\VortexProbePanel.tsx',
		'frontend\matching\GameMatchPanel.tsx'
	)
	foreach ($panel in $responsivePanels) {
		$panelSource = Get-Content -LiteralPath $panel -Raw
		if ($panelSource -notmatch '<ResponsiveControlGroup>' -or
			$panelSource -notmatch 'fullWidthControlStyle') {
			throw "Settings panel '$panel' must use responsive full-width controls."
		}
	}

	$responsiveControlsSource = Get-Content -LiteralPath 'frontend\ui\ResponsiveControls.tsx' -Raw
	$vortexProbePanelSource = Get-Content -LiteralPath 'frontend\vortex\VortexProbePanel.tsx' -Raw
	if ($responsiveControlsSource -notmatch 'paddedActionButtonStyle' -or
		$responsiveControlsSource -notmatch "paddingLeft:\s*'16px'" -or
		$responsiveControlsSource -notmatch "paddingRight:\s*'16px'" -or
		([regex]::Matches($vortexProbePanelSource, 'style=\{paddedActionButtonStyle\}')).Count -ne 2) {
		throw 'Vortex detection and read-only probe buttons must retain comfortable horizontal padding.'
	}

	$rpcHandlers = @(
		'verify_rpc_transport',
		'set_vortex_executable_path',
		'activate_vortex_profile',
		'update_plugin_settings',
		'get_game_launch_settings',
		'set_game_launch_settings',
		'remember_launch_choice',
		'launch_configured_target',
		'resolve_steam_installation',
		'get_steam_app_id_override',
		'set_steam_app_id_override',
		'match_vortex_game',
		'record_frontend_log'
	)
	foreach ($handler in $rpcHandlers) {
		if ($backendMain -notmatch "function\s+$handler\(request_json\)") {
			throw "Backend RPC handler '$handler' must accept one JSON envelope."
		}
	}

	$rpcClientSources = @(
		'frontend\backend\BackendClient.ts',
		'frontend\vortex\VortexClient.ts',
		'frontend\settings\SettingsClient.ts',
		'frontend\matching\MatchClient.ts'
	) | ForEach-Object { Get-Content -LiteralPath $_ -Raw }
	foreach ($source in $rpcClientSources) {
		if ($source -match 'callable<\s*\[\s*\{(?!\s*request_json\s*:)') {
			throw 'Parameterized frontend RPCs must use one request_json field.'
		}
	}

	$frontendIndex = Get-Content -LiteralPath 'frontend\index.tsx' -Raw
	if ($frontendIndex -notmatch "warmVortexStateCache\(\)" -or
		$frontendIndex -notmatch 'VORTEX_CACHE_REFRESH_INTERVAL_MS') {
		throw 'Frontend startup must warm and periodically refresh the Vortex state cache.'
	}

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

	& (Join-Path $PSScriptRoot 'test-process-runner.ps1')
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

	lua tests\command_line.lua
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	lua tests\json_encode.lua
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	lua tests\json_decode.lua
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	lua tests\settings.lua
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	lua tests\vortex_parsers.lua
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	lua tests\state_cache.lua
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	lua tests\game_matching.lua
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
	lua tests\vortex_launcher.lua
	exit $LASTEXITCODE
}
finally {
	Pop-Location
}
