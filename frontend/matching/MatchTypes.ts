import type { VortexProfile } from '../vortex/VortexTypes';

export type SteamInstallationSource = 'steam-client' | 'manifest' | 'none';
export type VortexMatchConfidence =
	| 'configured'
	| 'steam-id'
	| 'exact-path'
	| 'exact-executable'
	| 'none';

export interface SteamInstallationResult {
	resolved: boolean;
	steamAppId: number;
	source: SteamInstallationSource;
	installPath?: string;
	candidateCount?: number;
	warning?: string;
}

export interface VortexGameMatch {
	matched: boolean;
	confidence: VortexMatchConfidence;
	steamAppId: number;
	steamSource?: SteamInstallationSource;
	steamInstallPath?: string;
	vortexGameId?: string;
	vortexGameName?: string;
	vortexGamePath?: string;
	profiles: VortexProfile[];
	warning?: string;
}

export interface SteamAppIdOverrideResult {
	ok: boolean;
	steamAppId?: number;
	vortexGameId?: string;
	error?: string;
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function requireRecord(value: unknown, label: string): Record<string, unknown> {
	if (!isRecord(value)) {
		throw new Error(`${label} is not an object.`);
	}
	return value;
}

function requireNumber(record: Record<string, unknown>, key: string, label: string): number {
	const value = record[key];
	if (typeof value !== 'number' || !Number.isFinite(value)) {
		throw new Error(`${label} has an invalid ${key} field.`);
	}
	return value;
}

function optionalNumber(
	record: Record<string, unknown>,
	key: string,
	label: string,
): number | undefined {
	const value = record[key];
	if (value === undefined) {
		return undefined;
	}
	if (typeof value !== 'number' || !Number.isFinite(value)) {
		throw new Error(`${label} has an invalid ${key} field.`);
	}
	return value;
}

function optionalString(
	record: Record<string, unknown>,
	key: string,
	label: string,
): string | undefined {
	const value = record[key];
	if (value === undefined) {
		return undefined;
	}
	if (typeof value !== 'string') {
		throw new Error(`${label} has an invalid ${key} field.`);
	}
	return value;
}

function parseSource(value: unknown, label: string): SteamInstallationSource {
	if (value !== 'steam-client' && value !== 'manifest' && value !== 'none') {
		throw new Error(`${label} has an invalid source field.`);
	}
	return value;
}

function parseConfidence(value: unknown): VortexMatchConfidence {
	if (
		value !== 'configured' &&
		value !== 'steam-id' &&
		value !== 'exact-path' &&
		value !== 'exact-executable' &&
		value !== 'none'
	) {
		throw new Error('Vortex game match has an invalid confidence field.');
	}
	return value;
}

function asArray(value: unknown, label: string): unknown[] {
	if (Array.isArray(value)) {
		return value;
	}
	if (isRecord(value) && Object.keys(value).length === 0) {
		return [];
	}
	throw new Error(`${label} is not an array.`);
}

function parseProfile(value: unknown, index: number): VortexProfile {
	const label = `Vortex game match profiles[${index}]`;
	const record = requireRecord(value, label);
	const id = optionalString(record, 'id', label);
	const name = optionalString(record, 'name', label);
	const gameId = optionalString(record, 'gameId', label);
	if (!id || !name || !gameId) {
		throw new Error(`${label} is missing required fields.`);
	}

	const enabledModCount = optionalNumber(record, 'enabledModCount', label);
	const isLastActive = record.isLastActive;
	if (isLastActive !== undefined && typeof isLastActive !== 'boolean') {
		throw new Error(`${label} has an invalid isLastActive field.`);
	}
	return { id, name, gameId, enabledModCount, isLastActive };
}

export function parseSteamInstallation(value: unknown): SteamInstallationResult {
	const label = 'Steam installation response';
	const record = requireRecord(value, label);
	if (typeof record.resolved !== 'boolean') {
		throw new Error(`${label} has an invalid resolved field.`);
	}

	return {
		resolved: record.resolved,
		steamAppId: requireNumber(record, 'steamAppId', label),
		source: parseSource(record.source, label),
		installPath: optionalString(record, 'installPath', label),
		candidateCount: optionalNumber(record, 'candidateCount', label),
		warning: optionalString(record, 'warning', label),
	};
}

export function parseVortexGameMatch(value: unknown): VortexGameMatch {
	const label = 'Vortex game match';
	const record = requireRecord(value, label);
	if (typeof record.matched !== 'boolean') {
		throw new Error(`${label} has an invalid matched field.`);
	}

	const steamSource =
		record.steamSource === undefined ? undefined : parseSource(record.steamSource, label);
	return {
		matched: record.matched,
		confidence: parseConfidence(record.confidence),
		steamAppId: requireNumber(record, 'steamAppId', label),
		steamSource,
		steamInstallPath: optionalString(record, 'steamInstallPath', label),
		vortexGameId: optionalString(record, 'vortexGameId', label),
		vortexGameName: optionalString(record, 'vortexGameName', label),
		vortexGamePath: optionalString(record, 'vortexGamePath', label),
		profiles: asArray(record.profiles, `${label} profiles`).map(parseProfile),
		warning: optionalString(record, 'warning', label),
	};
}

export function parseSteamAppIdOverride(value: unknown): SteamAppIdOverrideResult {
	const label = 'Steam AppID override response';
	const record = requireRecord(value, label);
	if (typeof record.ok !== 'boolean') {
		throw new Error(`${label} has an invalid ok field.`);
	}
	return {
		ok: record.ok,
		steamAppId: optionalNumber(record, 'steamAppId', label),
		vortexGameId: optionalString(record, 'vortexGameId', label),
		error: optionalString(record, 'error', label),
	};
}
