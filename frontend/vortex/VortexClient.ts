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
const requestOverride = callable<[{ executable_path: string }], string>('set_vortex_executable_path');
const requestProbe = callable<[], string>('run_vortex_probe');
const requestActivation = callable<
	[{ vortex_game_id: string; vortex_profile_id: string }],
	string
>('activate_vortex_profile');

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

export async function getVortexInstallation(): Promise<VortexInstallation> {
	const response = await withTimeout(requestInstallation(), 8_000, 'Vortex detection');
	return parseVortexInstallation(parseJson(response, 'Vortex detection'));
}

export async function setVortexExecutablePath(path: string): Promise<VortexOverrideResult> {
	const response = await withTimeout(
		requestOverride({ executable_path: path }),
		8_000,
		'Saving the Vortex override',
	);
	return parseVortexOverrideResult(parseJson(response, 'Saving the Vortex override'));
}

export async function runVortexProbe(): Promise<VortexProbeResult> {
	const response = await withTimeout(requestProbe(), 45_000, 'The read-only Vortex probe');
	return parseVortexProbeResult(parseJson(response, 'The read-only Vortex probe'));
}

export async function activateVortexProfile(
	gameId: string,
	profileId: string,
): Promise<VortexActivationResult> {
	const response = await withTimeout(
		requestActivation({
			vortex_game_id: gameId,
			vortex_profile_id: profileId,
		}),
		310_000,
		'Vortex profile activation',
	);
	return parseVortexActivationResult(parseJson(response, 'Vortex profile activation'));
}
