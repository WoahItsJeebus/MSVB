import { callable } from '@steambrew/client';

import { log } from '../logging/Logger';
import {
	parseSteamAppIdOverride,
	parseSteamInstallation,
	parseVortexGameMatch,
	type SteamAppIdOverrideResult,
	type SteamInstallationResult,
	type VortexGameMatch,
} from './MatchTypes';

const requestSteamInstallation = callable<[{ request_json: string }], string>(
	'resolve_steam_installation',
);
const requestGameMatch = callable<[{ request_json: string }], string>('match_vortex_game');
const requestGetOverride = callable<[{ request_json: string }], string>(
	'get_steam_app_id_override',
);
const requestSetOverride = callable<[{ request_json: string }], string>(
	'set_steam_app_id_override',
);

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

async function clientLibraryPaths(appId: number): Promise<string[]> {
	try {
		const folders = await withTimeout(
			SteamClient.InstallFolder.GetInstallFolders(),
			5_000,
			'Steam install-folder lookup',
		);
		const output: string[] = [];
		const seen = new Set<string>();
		for (const folder of folders) {
			if (
				!Array.isArray(folder.vecApps) ||
				!folder.vecApps.some((app) => app.nAppID === appId) ||
				typeof folder.strFolderPath !== 'string' ||
				folder.strFolderPath.length === 0
			) {
				continue;
			}
			const identity = folder.strFolderPath.replace(/\//g, '\\').toLocaleLowerCase();
			if (!seen.has(identity)) {
				seen.add(identity);
				output.push(folder.strFolderPath);
			}
		}
		return output;
	} catch (error: unknown) {
		log.warn('steam.install_folders.unavailable', {
			steamAppId: appId,
			error: error instanceof Error ? error.message : String(error),
			fallback: 'backend-manifests',
		});
		return [];
	}
}

export async function resolveSteamInstallation(appId: number): Promise<SteamInstallationResult> {
	const paths = await clientLibraryPaths(appId);
	const response = await withTimeout(
		requestSteamInstallation({
			request_json: JSON.stringify({
				steam_app_id: appId,
				client_library_paths_json: JSON.stringify(paths),
			}),
		}),
		10_000,
		'Steam installation resolution',
	);
	return parseSteamInstallation(parseJson(response, 'Steam installation resolution'));
}

export async function matchVortexGame(appId: number): Promise<VortexGameMatch> {
	const paths = await clientLibraryPaths(appId);
	const response = await withTimeout(
		requestGameMatch({
			request_json: JSON.stringify({
				steam_app_id: appId,
				client_library_paths_json: JSON.stringify(paths),
				steam_executable_path: '',
			}),
		}),
		45_000,
		'Vortex game matching',
	);
	return parseVortexGameMatch(parseJson(response, 'Vortex game matching'));
}

export async function getSteamAppIdOverride(
	appId: number,
): Promise<SteamAppIdOverrideResult> {
	const response = await withTimeout(
		requestGetOverride({
			request_json: JSON.stringify({ steam_app_id: appId }),
		}),
		5_000,
		'Loading the game mapping',
	);
	return parseSteamAppIdOverride(parseJson(response, 'Loading the game mapping'));
}

export async function setSteamAppIdOverride(
	appId: number,
	vortexGameId: string,
): Promise<SteamAppIdOverrideResult> {
	const response = await withTimeout(
		requestSetOverride({
			request_json: JSON.stringify({
				steam_app_id: appId,
				vortex_game_id: vortexGameId,
			}),
		}),
		5_000,
		'Saving the game mapping',
	);
	return parseSteamAppIdOverride(parseJson(response, 'Saving the game mapping'));
}
