import { callable } from '@steambrew/client';

import type { FrontendLogRecord } from '../logging/Logger';
import { BackendHealth, parseBackendHealth } from './BackendTypes';

const HEALTH_CHECK_TIMEOUT_MS = 5_000;
const requestBackendHealth = callable<[], string>('get_health');
const requestRpcTransport = callable<[{ request_json: string }], string>('verify_rpc_transport');
const requestProcessBridge = callable<[], string>('verify_process_bridge');
const requestFrontendLog = callable<[{ request_json: string }], string>('record_frontend_log');

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

export async function verifyBackendRpcTransport(nonce: string): Promise<void> {
	const response = await withTimeout(
		requestRpcTransport({
			request_json: JSON.stringify({ nonce }),
		}),
		HEALTH_CHECK_TIMEOUT_MS,
	);
	const parsed: unknown = JSON.parse(response);
	if (
		typeof parsed !== 'object' ||
		parsed === null ||
		Array.isArray(parsed) ||
		(parsed as Record<string, unknown>).ok !== true ||
		(parsed as Record<string, unknown>).nonce !== nonce
	) {
		throw new Error('Backend RPC transport verification failed.');
	}
}

export async function verifyBackendProcessBridge(): Promise<void> {
	const response = await withTimeout(requestProcessBridge(), 10_000);
	const parsed: unknown = JSON.parse(response);
	if (
		typeof parsed !== 'object' ||
		parsed === null ||
		Array.isArray(parsed) ||
		(parsed as Record<string, unknown>).ok !== true ||
		(parsed as Record<string, unknown>).capturedMarker !== true
	) {
		throw new Error('Backend process bridge verification failed.');
	}
}

export function forwardFrontendLog(record: FrontendLogRecord): void {
	void requestFrontendLog({
		request_json: JSON.stringify(record),
	}).catch(() => {
		// The console remains the fallback if the backend is unloading or absent.
	});
}
