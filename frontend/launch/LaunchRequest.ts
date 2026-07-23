import { ELaunchSource } from '@steambrew/client';

export type SteamRunGameArguments = readonly [
	appId: string,
	launchOptions: string,
	parameter3: number,
	launchSource: ELaunchSource,
];

export interface SteamLaunchRequest {
	requestId: string;
	appId: string;
	numericAppId: number;
	launchOptions: string;
	parameter3: number;
	launchSource: ELaunchSource;
	capturedAt: number;
	signature: string;
}

let nextRequestSequence = 0;

function parseSteamAppId(value: string): number | undefined {
	if (!/^[1-9]\d{0,9}$/.test(value)) {
		return undefined;
	}
	const numeric = Number(value);
	if (!Number.isSafeInteger(numeric) || numeric > 4_294_967_295) {
		return undefined;
	}
	return numeric;
}

export function createSteamLaunchRequest(
	args: SteamRunGameArguments,
	now = Date.now(),
): SteamLaunchRequest | undefined {
	const [appId, launchOptions, parameter3, launchSource] = args;
	const numericAppId = parseSteamAppId(appId);
	if (
		numericAppId === undefined ||
		typeof launchOptions !== 'string' ||
		typeof parameter3 !== 'number' ||
		!Number.isFinite(parameter3) ||
		typeof launchSource !== 'number' ||
		!Number.isFinite(launchSource)
	) {
		return undefined;
	}

	nextRequestSequence += 1;
	return {
		requestId: `${now.toString(36)}-${nextRequestSequence.toString(36)}`,
		appId,
		numericAppId,
		launchOptions,
		parameter3,
		launchSource,
		capturedAt: now,
		// The full launch options remain in memory because continuation must be
		// exact. The signature is never logged or persisted.
		signature: JSON.stringify([appId, launchOptions, parameter3, launchSource]),
	};
}

export function runGameArguments(request: SteamLaunchRequest): SteamRunGameArguments {
	return [
		request.appId,
		request.launchOptions,
		request.parameter3,
		request.launchSource,
	];
}
