import { callable } from '@steambrew/client';

import { BackendHealth, parseBackendHealth } from './BackendTypes';

const HEALTH_CHECK_TIMEOUT_MS = 5_000;
const requestBackendHealth = callable<[], string>('get_health');

function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
	return new Promise<T>((resolve, reject) => {
		const timeoutId = setTimeout(() => {
			reject(new Error(`Backend health check timed out after ${timeoutMs} ms.`));
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

export async function getBackendHealth(): Promise<BackendHealth> {
	const response = await withTimeout(requestBackendHealth(), HEALTH_CHECK_TIMEOUT_MS);
	const parsed: unknown = JSON.parse(response);
	return parseBackendHealth(parsed);
}
