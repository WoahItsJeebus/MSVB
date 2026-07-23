export type VortexDetectionSource = 'configured' | 'registry' | 'known-path';

export interface VortexInstallation {
	found: boolean;
	executablePath?: string;
	source?: VortexDetectionSource;
	version?: string;
	error?: string;
	configuredPathInvalid?: boolean;
}

export interface VortexCommandResult {
	executed: boolean;
	label: string;
	arguments: string[];
	timeoutMs?: number;
	started?: boolean;
	timedOut?: boolean;
	exitCode?: number;
	errorCode?: number;
	error?: string;
	durationMs?: number;
	stdout?: string;
	stderr?: string;
	stdoutBytes?: number;
	stderrBytes?: number;
	stdoutEncoding?: 'utf-8' | 'binary';
	stderrEncoding?: 'utf-8' | 'binary';
	stdoutTruncated?: boolean;
	stderrTruncated?: boolean;
	wasVortexRunning?: boolean;
	isVortexRunningAfter?: boolean;
	startedAnotherInstance?: boolean;
	skipReason?: string;
	outputFormat?: 'json' | 'assignments' | 'empty' | 'unknown';
	outputIsJson?: boolean;
	assignmentCount?: number;
	jsonValueCount?: number;
	invalidAssignmentCount?: number;
	ignoredLineCount?: number;
}

export interface VortexProfile {
	id: string;
	name: string;
	gameId: string;
	enabledModCount?: number;
	isLastActive?: boolean;
}

export interface VortexDiscoveredGame {
	id: string;
	name?: string;
	path?: string;
	store?: string;
	executable?: string;
	hidden?: boolean;
	pathSetManually?: boolean;
}

export interface VortexProbeResult {
	ok: boolean;
	readOnly: true;
	installation: VortexInstallation;
	versionCommand?: VortexCommandResult;
	stateCommand?: VortexCommandResult;
	profiles: VortexProfile[];
	discoveredGames: VortexDiscoveredGame[];
	invalidProfileCount?: number;
	warnings: string[];
	error?: string;
}

export interface VortexOverrideResult {
	ok: boolean;
	installation?: VortexInstallation;
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

function requireString(record: Record<string, unknown>, key: string, label: string): string {
	const value = record[key];
	if (typeof value !== 'string' || value.length === 0) {
		throw new Error(`${label} has an invalid ${key} field.`);
	}
	return value;
}

function optionalString(record: Record<string, unknown>, key: string, label: string): string | undefined {
	const value = record[key];
	if (value === undefined) {
		return undefined;
	}
	if (typeof value !== 'string') {
		throw new Error(`${label} has an invalid ${key} field.`);
	}
	return value;
}

function optionalBoolean(record: Record<string, unknown>, key: string, label: string): boolean | undefined {
	const value = record[key];
	if (value === undefined) {
		return undefined;
	}
	if (typeof value !== 'boolean') {
		throw new Error(`${label} has an invalid ${key} field.`);
	}
	return value;
}

function optionalNumber(record: Record<string, unknown>, key: string, label: string): number | undefined {
	const value = record[key];
	if (value === undefined) {
		return undefined;
	}
	if (typeof value !== 'number' || !Number.isFinite(value)) {
		throw new Error(`${label} has an invalid ${key} field.`);
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

function stringArray(value: unknown, label: string): string[] {
	return asArray(value, label).map((item, index) => {
		if (typeof item !== 'string') {
			throw new Error(`${label}[${index}] is not a string.`);
		}
		return item;
	});
}

export function parseVortexInstallation(value: unknown): VortexInstallation {
	const record = requireRecord(value, 'Vortex installation response');
	if (typeof record.found !== 'boolean') {
		throw new Error('Vortex installation response has an invalid found field.');
	}

	const source = optionalString(record, 'source', 'Vortex installation response');
	if (source !== undefined && source !== 'configured' && source !== 'registry' && source !== 'known-path') {
		throw new Error('Vortex installation response has an unknown source.');
	}

	return {
		found: record.found,
		executablePath: optionalString(record, 'executablePath', 'Vortex installation response'),
		source,
		version: optionalString(record, 'version', 'Vortex installation response'),
		error: optionalString(record, 'error', 'Vortex installation response'),
		configuredPathInvalid: optionalBoolean(
			record,
			'configuredPathInvalid',
			'Vortex installation response',
		),
	};
}

function parseCommand(value: unknown, label: string): VortexCommandResult {
	const record = requireRecord(value, label);
	if (typeof record.executed !== 'boolean') {
		throw new Error(`${label} has an invalid executed field.`);
	}

	const outputFormat = optionalString(record, 'outputFormat', label);
	if (
		outputFormat !== undefined &&
		outputFormat !== 'json' &&
		outputFormat !== 'assignments' &&
		outputFormat !== 'empty' &&
		outputFormat !== 'unknown'
	) {
		throw new Error(`${label} has an unknown outputFormat.`);
	}

	const stdoutEncoding = optionalString(record, 'stdoutEncoding', label);
	const stderrEncoding = optionalString(record, 'stderrEncoding', label);
	if (stdoutEncoding !== undefined && stdoutEncoding !== 'utf-8' && stdoutEncoding !== 'binary') {
		throw new Error(`${label} has an unknown stdoutEncoding.`);
	}
	if (stderrEncoding !== undefined && stderrEncoding !== 'utf-8' && stderrEncoding !== 'binary') {
		throw new Error(`${label} has an unknown stderrEncoding.`);
	}

	return {
		executed: record.executed,
		label: requireString(record, 'label', label),
		arguments: stringArray(record.arguments, `${label}.arguments`),
		timeoutMs: optionalNumber(record, 'timeoutMs', label),
		started: optionalBoolean(record, 'started', label),
		timedOut: optionalBoolean(record, 'timedOut', label),
		exitCode: optionalNumber(record, 'exitCode', label),
		errorCode: optionalNumber(record, 'errorCode', label),
		error: optionalString(record, 'error', label),
		durationMs: optionalNumber(record, 'durationMs', label),
		stdout: optionalString(record, 'stdout', label),
		stderr: optionalString(record, 'stderr', label),
		stdoutBytes: optionalNumber(record, 'stdoutBytes', label),
		stderrBytes: optionalNumber(record, 'stderrBytes', label),
		stdoutEncoding,
		stderrEncoding,
		stdoutTruncated: optionalBoolean(record, 'stdoutTruncated', label),
		stderrTruncated: optionalBoolean(record, 'stderrTruncated', label),
		wasVortexRunning: optionalBoolean(record, 'wasVortexRunning', label),
		isVortexRunningAfter: optionalBoolean(record, 'isVortexRunningAfter', label),
		startedAnotherInstance: optionalBoolean(record, 'startedAnotherInstance', label),
		skipReason: optionalString(record, 'skipReason', label),
		outputFormat,
		outputIsJson: optionalBoolean(record, 'outputIsJson', label),
		assignmentCount: optionalNumber(record, 'assignmentCount', label),
		jsonValueCount: optionalNumber(record, 'jsonValueCount', label),
		invalidAssignmentCount: optionalNumber(record, 'invalidAssignmentCount', label),
		ignoredLineCount: optionalNumber(record, 'ignoredLineCount', label),
	};
}

function parseProfile(value: unknown, index: number): VortexProfile {
	const label = `Vortex probe profiles[${index}]`;
	const record = requireRecord(value, label);
	return {
		id: requireString(record, 'id', label),
		name: requireString(record, 'name', label),
		gameId: requireString(record, 'gameId', label),
		enabledModCount: optionalNumber(record, 'enabledModCount', label),
		isLastActive: optionalBoolean(record, 'isLastActive', label),
	};
}

function parseDiscoveredGame(value: unknown, index: number): VortexDiscoveredGame {
	const label = `Vortex probe discoveredGames[${index}]`;
	const record = requireRecord(value, label);
	return {
		id: requireString(record, 'id', label),
		name: optionalString(record, 'name', label),
		path: optionalString(record, 'path', label),
		store: optionalString(record, 'store', label),
		executable: optionalString(record, 'executable', label),
		hidden: optionalBoolean(record, 'hidden', label),
		pathSetManually: optionalBoolean(record, 'pathSetManually', label),
	};
}

export function parseVortexProbeResult(value: unknown): VortexProbeResult {
	const record = requireRecord(value, 'Vortex probe response');
	if (typeof record.ok !== 'boolean' || record.readOnly !== true) {
		throw new Error('Vortex probe response has invalid status fields.');
	}

	return {
		ok: record.ok,
		readOnly: true,
		installation: parseVortexInstallation(record.installation),
		versionCommand:
			record.versionCommand === undefined
				? undefined
				: parseCommand(record.versionCommand, 'Vortex version command'),
		stateCommand:
			record.stateCommand === undefined
				? undefined
				: parseCommand(record.stateCommand, 'Vortex state command'),
		profiles: asArray(record.profiles, 'Vortex probe profiles').map(parseProfile),
		discoveredGames: asArray(record.discoveredGames, 'Vortex probe discoveredGames').map(
			parseDiscoveredGame,
		),
		invalidProfileCount: optionalNumber(record, 'invalidProfileCount', 'Vortex probe response'),
		warnings: stringArray(record.warnings, 'Vortex probe warnings'),
		error: optionalString(record, 'error', 'Vortex probe response'),
	};
}

export function parseVortexOverrideResult(value: unknown): VortexOverrideResult {
	const record = requireRecord(value, 'Vortex override response');
	if (typeof record.ok !== 'boolean') {
		throw new Error('Vortex override response has an invalid ok field.');
	}

	return {
		ok: record.ok,
		installation:
			record.installation === undefined ? undefined : parseVortexInstallation(record.installation),
		error: optionalString(record, 'error', 'Vortex override response'),
	};
}
