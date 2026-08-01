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
	$installerCoreSource = Get-Content -LiteralPath 'installer\InstallerCore.cs' -Raw
	$installerAssemblySource = Get-Content -LiteralPath 'installer\AssemblyInfo.cs' -Raw
	$installerManifestSource = Get-Content -LiteralPath 'installer\app.manifest' -Raw
	if ($manifestVersion -ne $packageVersion -or
		$backendMain -notmatch "PLUGIN_VERSION\s*=\s*`"$escapedVersion`"" -or
		$frontendIndexSource -notmatch "const PLUGIN_VERSION\s*=\s*'$escapedVersion'" -or
		$readmeSource -notmatch "version-$escapedVersion-" -or
		$changelogSource -notmatch "(?m)^## (?:\[)?$escapedVersion(?:\])? - " -or
		$installerCoreSource -notmatch "InstallerVersion\s*=\s*`"$escapedVersion`"" -or
		$installerAssemblySource -notmatch "AssemblyVersion\(`"$escapedVersion\.0`"\)" -or
		$installerManifestSource -notmatch "assemblyIdentity version=`"$escapedVersion\.0`"") {
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
	$processRunnerSource =
		Get-Content -LiteralPath 'backend\util\process_runner.ps1' -Raw
	if ($processRunnerSource -notmatch
		'(?s)if\s*\(-not \$capture\).*?Start-Process.*?-WindowStyle\s+Hidden') {
		throw 'Detached process launches must explicitly request hidden window state.'
	}
	if (-not (Test-Path -LiteralPath 'backend\util\process_shell.exe')) {
		throw 'The hidden process shell is missing.'
	}
	$processShellSource = Get-Content -LiteralPath 'backend\util\process_shell.cs' -Raw
	if ($processShellSource -notmatch 'CreateNoWindow\s*=\s*0x08000000' -or
		$processShellSource -notmatch 'DetachedProcess\s*=\s*0x00000008' -or
		$processShellSource -notmatch 'RunWithoutConsole\(' -or
		$processShellSource -notmatch 'RunDetached\(' -or
		$processShellSource -notmatch '--vlb-detach' -or
		$processShellSource -notmatch '--vlb-detach-hidden-console' -or
		$processShellSource -notmatch '--vlb-detach-vortex-guarded' -or
		$processShellSource -notmatch 'RunGuardedDetachedVortex\(' -or
		$processShellSource -notmatch 'CreateSuspended\s*=\s*0x00000004' -or
		$processShellSource -notmatch 'SetWinEventHook\(' -or
		$processShellSource -notmatch 'ShowWindowAsync\(' -or
		$processShellSource -notmatch 'SetWindowPos\(' -or
		$processShellSource -notmatch 'IsDescendantProcess\(' -or
		$processShellSource -notmatch 'NormalizeChildEnvironment\(' -or
		$processShellSource -notmatch 'RunIsProcessRunning\(' -or
		$processShellSource -notmatch '--vlb-is-running' -or
		$processShellSource -notmatch 'RunTerminateVortex\(' -or
		$processShellSource -notmatch '--vlb-terminate-vortex' -or
		$processShellSource -notmatch 'Process\.GetProcessesByName\("Vortex"\)' -or
		$processShellSource -notmatch 'process\.Kill\(\)' -or
		$processShellSource -notmatch
			'createHiddenConsole\s*\?\s*CreateNewConsole\s*:\s*DetachedProcess' -or
		$processShellSource -notmatch
			'CreateNoWindow\s*\+\s*CreateUnicodeEnvironment' -or
		$processShellSource -notmatch 'CreateDesktop\(' -or
		$processShellSource -notmatch 'CreateProcess\(' -or
		$processShellSource -notmatch 'desktop\s*=\s*desktopName' -or
		-not $processShellSource.Contains('\"capture\":true')) {
		throw 'Bridge runners must suppress consoles, and captured process trees must run on a hidden desktop.'
	}
	$windowsSource = Get-Content -LiteralPath 'backend\util\windows.lua' -Raw
	if ($windowsSource -notmatch
		'(?s)function\s+detached_process_request\(\s*executable,\s*arguments,\s*create_hidden_console,\s*guard_vortex_console_windows\s*\)' -or
		$windowsSource -notmatch
		'(?s)local\s+function\s+start_detached_process\(\s*executable,\s*arguments,\s*create_hidden_console,\s*guard_vortex_console_windows\s*\).*?detached_process_request\(\s*executable,\s*arguments,\s*create_hidden_console,\s*guard_vortex_console_windows\s*\)' -or
		$windowsSource -notmatch
		'function\s+M\.start_process\(executable,\s*arguments\)\s*return\s+start_detached_process\(executable,\s*arguments,\s*false,\s*false\)\s*end' -or
		$windowsSource -notmatch
		'function\s+M\.start_process_with_hidden_console\(executable,\s*arguments\)\s*return\s+start_detached_process\(executable,\s*arguments,\s*true,\s*false\)\s*end' -or
		$windowsSource -notmatch
		'function\s+M\.start_vortex_process\(executable,\s*arguments\)\s*return\s+start_detached_process\(executable,\s*arguments,\s*false,\s*true\)\s*end' -or
		[regex]::Matches(
			$windowsSource,
			'function\s+M\.start_process\(executable,\s*arguments\)'
		).Count -ne 1 -or
		$windowsSource -notmatch
			'direct_is_running_request\(executable_name\)' -or
		$windowsSource -notmatch 'function\s+M\.terminate_vortex\(\)') {
		throw 'Detached targets and activation polling must bypass the PowerShell process runner.'
	}
	$vortexLauncherSource =
		Get-Content -LiteralPath 'backend\vortex\launcher.lua' -Raw
	if ($vortexLauncherSource -notmatch
		'local\s+process\s*=\s*windows\.start_vortex_process\(') {
		throw 'Vortex activation must use the guarded direct launcher.'
	}
	if ($vortexLauncherSource -notmatch
		'(?s)if\s+restart_requested\s+then.*?windows\.terminate_vortex\(\).*?local\s+process\s*=\s*windows\.start_vortex_process\(') {
		throw 'Forced activation retries must terminate Vortex before relaunching it.'
	}
	if (-not (Test-Path -LiteralPath 'scripts\patch-vortex-dotnetprobe.ps1')) {
		throw 'The guarded Vortex dotnet-probe compatibility repair is missing.'
	}
	$dotnetProbePatch =
		Get-Content -LiteralPath 'scripts\patch-vortex-dotnetprobe.ps1' -Raw
	if ($dotnetProbePatch -notmatch
		'unsupported size pickle' -or
		$dotnetProbePatch -notmatch
		'Get-FileHash' -or
		$dotnetProbePatch -notmatch
		'Copy-Item' -or
		-not $dotnetProbePatch.Contains(
			'(file,args,{windowsHide:true})'
		) -or
		-not $dotnetProbePatch.Contains(
			'o={cwd,env,windowsHide:!0,detached:'
		) -or
		-not $dotnetProbePatch.Contains(
			"execa('fsutil', ['dirty', 'query', "
		) -or
		$dotnetProbePatch -notmatch
			'shellLaunchPatched\s*=\s*\$true' -or
		$dotnetProbePatch -notmatch
			'adminCheckPatched\s*=\s*\$true' -or
		$dotnetProbePatch -notmatch
			'patchedAdminCheckHash') {
		throw 'The Vortex child-process repair must validate, back up, and verify its same-size ASAR edit.'
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
	if ($backendMain -notmatch
		'(?s)function\s+match_vortex_game\(request_json\).*?local\s+state_before_refresh\s*=\s*vortex_state_cache\.get\(\).*?local\s+refresh_result\s*=\s*vortex_state_cache\.refresh\(\).*?local\s+state,\s*cache_metadata\s*=\s*vortex_state_cache\.get\(\)') {
		throw 'Every launch-time game match must refresh Vortex state before using the cache.'
	}

	$launchInterceptor = Get-Content -LiteralPath 'frontend\launch\LaunchInterceptor.tsx' -Raw
	if ($launchInterceptor -notmatch 'return\s+showModal\(modal,\s*window,\s*props\)') {
		throw 'Launch modals must use the desktop SharedJS window explicitly.'
	}
	if ([regex]::Matches($launchInterceptor, '\bshowModal\(').Count -ne 1) {
		throw 'Launch modal call sites must use the guarded desktop modal helper.'
	}
	if ($launchInterceptor -match 'CANCELLED_RETRY_WINDOW_MS|recentlyCancelledByApp|launch\.pending_duplicate_suppressed' -or
		$launchInterceptor -notmatch 'launch\.pending_superseded' -or
		$launchInterceptor -notmatch "cancelPending\(activePending,\s*'superseded-by-new-launch'\)") {
		throw 'New launch attempts must immediately supersede the prior pending flow without a cooldown.'
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
	$activationErrorModal = Get-Content -LiteralPath 'frontend\ui\ActivationErrorModal.tsx' -Raw
	if ($activationErrorModal -notmatch "'Retry'" -or
		$activationErrorModal -notmatch 'onMiddleButton=\{onRetry' -or
		$launchInterceptor -notmatch 'retryVortexActivation\(' -or
		$launchInterceptor -notmatch 'activateProfile\(pending,\s*match,\s*profile,\s*true\)' -or
		$launchInterceptor -notmatch 'forceRestartVortex,') {
		throw 'Activation recovery must expose a force-closing Vortex retry action.'
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
		$responsiveControlsSource -notmatch "position:\s*'relative'" -or
		$responsiveControlsSource -notmatch "right:\s*'32px'" -or
		([regex]::Matches($vortexProbePanelSource, 'style=\{paddedActionButtonStyle\}')).Count -ne 1 -or
		([regex]::Matches($vortexProbePanelSource, 'style=\{insetPaddedActionButtonStyle\}')).Count -ne 1) {
		throw 'Vortex actions must retain comfortable padding without overflowing their field containers.'
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
