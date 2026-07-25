import { callable } from '@steambrew/client';

import {
	parseVortexActivationResult,
	parseVortexInstallation,
	parseVortexOverrideResult,
	parseVortexProbeResult,
	type VortexActivationResult,
	type VortexInstallation,
	type VortexOverrideResult,
	type VortexProbeResult,
} from './VortexTypes';

const requestInstallation = callable<[], string>('get_vortex_installation');
const requestOverride = callable<[{ request_json: string }], string>('set_vortex_executable_path');
const requestProbe = callable<[], string>('run_vortex_probe');
const requestCacheWarm = callable<[], string>('warm_vortex_state_cache');
const requestActivation = callable<[{ request_json: string }], string>(
	'activate_vortex_profile',
);

export interface VortexCacheWarmResult {
	ok: boolean;
	refreshed: boolean;
	skipped: boolean;
	skipReason?: string;
	cacheAvailable: boolean;
	durationMs: number;
	profileCount: number;
	discoveredGameCount: number;
	error?: string;
}

function withTimeout<T>(promise: Promise<T>, timeoutMs: number, operation: string): Promise<T> {
	return new Promise<T>((resolve, reject) => {
		const timeoutId = setTimeout(() => {
			reject(new Error(`${operation} timed out after ${timeoutMs} ms.`));
		}, timeoutMs);

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

function parseJson(response: string, operation: string): unknown {
	try {
		return JSON.parse(response) as unknown;
	} catch {
		throw new Error(`${operation} returned invalid JSON.`);
	}
}

function parseCacheWarmResult(value: unknown): VortexCacheWarmResult {
	if (typeof value !== 'object' || value === null || Array.isArray(value)) {
		throw new Error('Vortex cache refresh returned an invalid result.');
	}
	const result = value as Record<string, unknown>;
	if (
		typeof result.ok !== 'boolean' ||
		typeof result.refreshed !== 'boolean' ||
		typeof result.skipped !== 'boolean' ||
		(result.skipReason !== undefined && typeof result.skipReason !== 'string') ||
		typeof result.cacheAvailable !== 'boolean' ||
		typeof result.durationMs !== 'number' ||
		!Number.isFinite(result.durationMs) ||
		typeof result.profileCount !== 'number' ||
		!Number.isSafeInteger(result.profileCount) ||
		typeof result.discoveredGameCount !== 'number' ||
		!Number.isSafeInteger(result.discoveredGameCount) ||
		(result.error !== undefined && typeof result.error !== 'string')
	) {
		throw new Error('Vortex cache refresh returned invalid fields.');
	}
	return {
		ok: result.ok,
		refreshed: result.refreshed,
		skipped: result.skipped,
		skipReason: result.skipReason as string | undefined,
		cacheAvailable: result.cacheAvailable,
		durationMs: result.durationMs,
		profileCount: result.profileCount,
		discoveredGameCount: result.discoveredGameCount,
		error: result.error,
	};
}

export async function getVortexInstallation(): Promise<VortexInstallation> {
	const response = await withTimeout(requestInstallation(), 8_000, 'Vortex detection');
	return parseVortexInstallation(parseJson(response, 'Vortex detection'));
}

export async function setVortexExecutablePath(path: string): Promise<VortexOverrideResult> {
	const response = await withTimeout(
		requestOverride({
			request_json: JSON.stringify({ executable_path: path }),
		}),
		8_000,
		'Saving the Vortex override',
	);
	return parseVortexOverrideResult(parseJson(response, 'Saving the Vortex override'));
}

export async function runVortexProbe(): Promise<VortexProbeResult> {
	const response = await withTimeout(requestProbe(), 45_000, 'The read-only Vortex probe');
	return parseVortexProbeResult(parseJson(response, 'The read-only Vortex probe'));
}

export async function warmVortexStateCache(): Promise<VortexCacheWarmResult> {
	const response = await withTimeout(
		requestCacheWarm(),
		45_000,
		'The background Vortex state refresh',
	);
	return parseCacheWarmResult(parseJson(response, 'The background Vortex state refresh'));
}

export async function activateVortexProfile(
	gameId: string,
	profileId: string,
	profileIsLastActive: boolean,
): Promise<VortexActivationResult> {
	const response = await withTimeout(
		requestActivation({
			request_json: JSON.stringify({
				vortex_game_id: gameId,
				vortex_profile_id: profileId,
				vortex_profile_is_last_active: profileIsLastActive,
			}),
		}),
		310_000,
		'Vortex profile activation',
	);
	return parseVortexActivationResult(parseJson(response, 'Vortex profile activation'));
}
