import { callable } from '@steambrew/client';

import {
	parseCustomLaunchResult,
	parseGameLaunchSettings,
	parseOperationResult,
	parsePluginSettings,
	type CustomLaunchResult,
	type GameLaunchSettings,
	type PluginSettings,
	type RememberedLaunchChoice,
} from './SettingsTypes';

const requestPluginSettings = callable<[], string>('get_plugin_settings');
const requestUpdatePluginSettings = callable<[{ request_json: string }], string>(
	'update_plugin_settings',
);
const requestGameSettings = callable<[{ request_json: string }], string>(
	'get_game_launch_settings',
);
const requestSetGameSettings = callable<[{ request_json: string }], string>(
	'set_game_launch_settings',
);
const requestRememberChoice = callable<[{ request_json: string }], string>(
	'remember_launch_choice',
);
const requestClearRemembered = callable<[], string>('clear_remembered_choices');
const requestCustomLaunch = callable<[{ request_json: string }], string>(
	'launch_configured_target',
);

function withTimeout<T>(promise: Promise<T>, timeoutMs: number, operation: string): Promise<T> {
	return new Promise<T>((resolve, reject) => {
		const timeoutId = setTimeout(() => reject(new Error(`${operation} timed out.`)), timeoutMs);
		promise.then(
			(value) => {
				clearTimeout(timeoutId);
				resolve(value);
			},
			(error: unknown) => {
				clearTimeout(timeoutId);
				reject(error);
			},
		);
	});
}

function json(response: string, operation: string): unknown {
	try {
		return JSON.parse(response) as unknown;
	} catch {
		throw new Error(`${operation} returned invalid JSON.`);
	}
}

export async function getPluginSettings(): Promise<PluginSettings> {
	const response = await withTimeout(requestPluginSettings(), 5_000, 'Loading plugin settings');
	return parsePluginSettings(json(response, 'Loading plugin settings'));
}

export async function updatePluginSettings(settings: PluginSettings): Promise<PluginSettings> {
	const response = await withTimeout(
		requestUpdatePluginSettings({
			request_json: JSON.stringify({
				always_ask: settings.alwaysAsk,
				remember_choice_per_game: settings.rememberChoicePerGame,
				vortex_activation_timeout_ms: settings.vortexActivationTimeoutMs,
				diagnostic_logging: settings.diagnosticLogging,
			}),
		}),
		5_000,
		'Saving plugin settings',
	);
	return parsePluginSettings(json(response, 'Saving plugin settings'));
}

export async function getGameLaunchSettings(appId: number): Promise<GameLaunchSettings> {
	const response = await withTimeout(
		requestGameSettings({
			request_json: JSON.stringify({ steam_app_id: appId }),
		}),
		5_000,
		'Loading per-game settings',
	);
	return parseGameLaunchSettings(json(response, 'Loading per-game settings'));
}

export async function setGameLaunchSettings(
	settings: GameLaunchSettings,
): Promise<GameLaunchSettings> {
	const response = await withTimeout(
		requestSetGameSettings({
			request_json: JSON.stringify({
				steam_app_id: settings.steamAppId,
				preferred_profile_id: settings.preferredProfileId ?? '',
				preferred_launch_target: settings.preferredLaunchTarget,
				custom_executable: settings.customExecutable ?? '',
				custom_arguments: settings.customArguments,
			}),
		}),
		8_000,
		'Saving per-game settings',
	);
	return parseGameLaunchSettings(json(response, 'Saving per-game settings'));
}

export async function rememberLaunchChoice(
	appId: number,
	choice: RememberedLaunchChoice,
	profileId = '',
): Promise<void> {
	const response = await withTimeout(
		requestRememberChoice({
			request_json: JSON.stringify({
				steam_app_id: appId,
				choice,
				vortex_profile_id: profileId,
			}),
		}),
		5_000,
		'Remembering the launch choice',
	);
	parseOperationResult(json(response, 'Remembering the launch choice'), 'Remembered choice response');
}

export async function clearRememberedChoices(): Promise<void> {
	const response = await withTimeout(
		requestClearRemembered(),
		5_000,
		'Clearing remembered choices',
	);
	parseOperationResult(json(response, 'Clearing remembered choices'), 'Clear choices response');
}

export async function launchConfiguredTarget(appId: number): Promise<CustomLaunchResult> {
	const response = await withTimeout(
		requestCustomLaunch({
			request_json: JSON.stringify({ steam_app_id: appId }),
		}),
		10_000,
		'Starting the custom launch target',
	);
	return parseCustomLaunchResult(json(response, 'Starting the custom launch target'));
}
