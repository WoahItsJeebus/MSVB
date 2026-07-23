export interface BackendHealth {
	ok: true;
	platform: string;
	architecture: string;
	pluginVersion: string;
	millenniumVersion: string;
	backendStartedAt: number;
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function requireString(record: Record<string, unknown>, key: string): string {
	const value = record[key];
	if (typeof value !== 'string' || value.length === 0) {
		throw new Error(`Backend health response has an invalid ${key} field.`);
	}

	return value;
}

export function parseBackendHealth(value: unknown): BackendHealth {
	if (!isRecord(value)) {
		throw new Error('Backend health response is not an object.');
	}

	if (value.ok !== true) {
		throw new Error('Backend health response did not report success.');
	}

	if (typeof value.backendStartedAt !== 'number' || !Number.isFinite(value.backendStartedAt)) {
		throw new Error('Backend health response has an invalid backendStartedAt field.');
	}

	return {
		ok: true,
		platform: requireString(value, 'platform'),
		architecture: requireString(value, 'architecture'),
		pluginVersion: requireString(value, 'pluginVersion'),
		millenniumVersion: requireString(value, 'millenniumVersion'),
		backendStartedAt: value.backendStartedAt,
	};
}
