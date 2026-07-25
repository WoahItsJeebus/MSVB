export type RememberedLaunchChoice = 'steam' | 'vortex';
export type PreferredLaunchTarget = 'steam' | 'custom';

export interface PluginSettings {
	alwaysAsk: boolean;
	rememberChoicePerGame: boolean;
	vortexActivationTimeoutMs: number;
	diagnosticLogging: boolean;
}

export interface GameLaunchSettings {
	steamAppId: number;
	rememberedChoice?: RememberedLaunchChoice;
	preferredProfileId?: string;
	preferredLaunchTarget: PreferredLaunchTarget;
	customExecutable?: string;
	customArguments: string;
}

export interface CustomLaunchResult {
	ok: boolean;
	started: boolean;
	target: PreferredLaunchTarget;
	processId?: number;
	durationMs?: number;
	error?: string;
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function record(value: unknown, label: string): Record<string, unknown> {
	if (!isRecord(value)) {
		throw new Error(`${label} is not an object.`);
	}
	return value;
}

function booleanField(value: unknown, key: string, label: string): boolean {
	const source = record(value, label);
	if (typeof source[key] !== 'boolean') {
		throw new Error(`${label} has an invalid ${key} field.`);
	}
	return source[key];
}

function numberField(value: unknown, key: string, label: string): number {
	const source = record(value, label);
	const field = source[key];
	if (typeof field !== 'number' || !Number.isFinite(field)) {
		throw new Error(`${label} has an invalid ${key} field.`);
	}
	return field;
}

function optionalString(source: Record<string, unknown>, key: string, label: string): string | undefined {
	const value = source[key];
	if (value === undefined) {
		return undefined;
	}
	if (typeof value !== 'string') {
		throw new Error(`${label} has an invalid ${key} field.`);
	}
	return value;
}

function safeSettingString(
	source: Record<string, unknown>,
	key: string,
	label: string,
	maximumLength: number,
): string | undefined {
	const value = optionalString(source, key, label);
	if (value === undefined) {
		return undefined;
	}
	if (value.length > maximumLength || /[\0-\x1f\x7f]/.test(value)) {
		throw new Error(`${label} has an unsafe ${key} field.`);
	}
	return value;
}

function parseChoice(value: unknown, label: string): RememberedLaunchChoice | undefined {
	if (value === undefined) {
		return undefined;
	}
	if (value !== 'steam' && value !== 'vortex') {
		throw new Error(`${label} has an invalid rememberedChoice field.`);
	}
	return value;
}

function parseTarget(value: unknown, label: string): PreferredLaunchTarget {
	if (value !== 'steam' && value !== 'custom') {
		throw new Error(`${label} has an invalid launch target.`);
	}
	return value;
}

function successfulPayload(value: unknown, label: string): Record<string, unknown> {
	const response = record(value, label);
	if (typeof response.ok !== 'boolean') {
		throw new Error(`${label} has an invalid ok field.`);
	}
	if (!response.ok) {
		throw new Error(optionalString(response, 'error', label) ?? `${label} failed.`);
	}
	return response;
}

export function parsePluginSettings(value: unknown): PluginSettings {
	const response = successfulPayload(value, 'Plugin settings response');
	const settings = record(response.settings, 'Plugin settings');
	const timeout = numberField(settings, 'vortexActivationTimeoutMs', 'Plugin settings');
	if (!Number.isSafeInteger(timeout) || timeout < 1_000 || timeout > 25_000) {
		throw new Error('Plugin settings has an invalid Vortex activation timeout.');
	}
	return {
		alwaysAsk: booleanField(settings, 'alwaysAsk', 'Plugin settings'),
		rememberChoicePerGame: booleanField(settings, 'rememberChoicePerGame', 'Plugin settings'),
		vortexActivationTimeoutMs: timeout,
		diagnosticLogging: booleanField(settings, 'diagnosticLogging', 'Plugin settings'),
	};
}

export function parseGameLaunchSettings(value: unknown): GameLaunchSettings {
	const response = successfulPayload(value, 'Per-game settings response');
	const game = record(response.game, 'Per-game settings');
	const appId = numberField(game, 'steamAppId', 'Per-game settings');
	if (!Number.isSafeInteger(appId) || appId < 1 || appId > 4_294_967_295) {
		throw new Error('Per-game settings has an invalid Steam AppID.');
	}
	const customArguments = safeSettingString(
		game,
		'customArguments',
		'Per-game settings',
		32_767,
	);
	return {
		steamAppId: appId,
		rememberedChoice: parseChoice(game.rememberedChoice, 'Per-game settings'),
		preferredProfileId: safeSettingString(
			game,
			'preferredProfileId',
			'Per-game settings',
			256,
		),
		preferredLaunchTarget: parseTarget(game.preferredLaunchTarget, 'Per-game settings'),
		customExecutable: safeSettingString(
			game,
			'customExecutable',
			'Per-game settings',
			32_767,
		),
		customArguments: customArguments ?? '',
	};
}

export function parseOperationResult(value: unknown, label: string): void {
	successfulPayload(value, label);
}

export function parseCustomLaunchResult(value: unknown): CustomLaunchResult {
	const label = 'Custom launch response';
	const response = record(value, label);
	if (typeof response.ok !== 'boolean' || typeof response.started !== 'boolean') {
		throw new Error(`${label} has invalid status fields.`);
	}
	const target = parseTarget(response.target, label);
	const processId = response.processId;
	const durationMs = response.durationMs;
	if (processId !== undefined && (typeof processId !== 'number' || !Number.isSafeInteger(processId))) {
		throw new Error(`${label} has an invalid processId field.`);
	}
	if (durationMs !== undefined && (typeof durationMs !== 'number' || !Number.isFinite(durationMs))) {
		throw new Error(`${label} has an invalid durationMs field.`);
	}
	return {
		ok: response.ok,
		started: response.started,
		target,
		processId,
		durationMs,
		error: optionalString(response, 'error', label),
	};
}
