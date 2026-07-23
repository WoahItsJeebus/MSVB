import { log } from '../logging/Logger';

export type LaunchCallbackName =
	| 'game-action-user-request'
	| 'game-action-start'
	| 'game-action-task-change'
	| 'game-action-details'
	| 'game-action-end'
	| 'run-game';

type SignatureValue = string | number | boolean | null | undefined;
type RequestState = 'observed' | 'completed';

export interface LaunchObservation {
	callback: LaunchCallbackName;
	capturedAt: number;
	gameActionId?: number;
	appId?: string;
	appIdPresent?: boolean;
	parameters: Readonly<Record<string, unknown>>;
	signature: readonly SignatureValue[];
	completesTrace?: boolean;
}

interface LaunchTrace {
	id: string;
	gameActionId?: number;
	appId?: string;
	firstObservedAt: number;
	lastObservedAt: number;
	state: RequestState;
}

interface DuplicateWindow {
	callback: LaunchCallbackName;
	traceId: string;
	firstSequence: number;
	lastSequence: number;
	firstCapturedAt: number;
	lastCapturedAt: number;
	suppressedCount: number;
	seenAt: number;
}

const DEDUPE_WINDOW_MS = 750;
const TRACE_CORRELATION_WINDOW_MS = 5_000;
const TRACE_RETENTION_MS = 60_000;

function validGameActionId(value: number | undefined): value is number {
	return typeof value === 'number' && Number.isSafeInteger(value) && value > 0;
}

function signatureKey(observation: LaunchObservation): string {
	return [observation.callback, observation.gameActionId, observation.appId, ...observation.signature]
		.map((value) => (value === undefined ? '<undefined>' : value === null ? '<null>' : String(value)))
		.join('|');
}

export class LaunchDiagnostics {
	private readonly sessionId = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
	private readonly tracesByAction = new Map<number, LaunchTrace>();
	private readonly recentTraceByApp = new Map<string, LaunchTrace>();
	private readonly duplicateWindows = new Map<string, DuplicateWindow>();
	private sequence = 0;
	private traceSequence = 0;

	record(observation: LaunchObservation): void {
		this.sequence += 1;
		this.prune(observation.capturedAt);

		const trace = this.resolveTrace(observation);
		const key = signatureKey(observation);
		const duplicate = this.duplicateWindows.get(key);

		if (duplicate !== undefined && observation.capturedAt - duplicate.seenAt <= DEDUPE_WINDOW_MS) {
			duplicate.lastSequence = this.sequence;
			duplicate.lastCapturedAt = observation.capturedAt;
			duplicate.suppressedCount += 1;
			duplicate.seenAt = observation.capturedAt;
			return;
		}

		this.flushDuplicateSummaries();
		this.duplicateWindows.set(key, {
			callback: observation.callback,
			traceId: trace.id,
			firstSequence: this.sequence,
			lastSequence: this.sequence,
			firstCapturedAt: observation.capturedAt,
			lastCapturedAt: observation.capturedAt,
			suppressedCount: 0,
			seenAt: observation.capturedAt,
		});

		trace.lastObservedAt = observation.capturedAt;
		if (observation.completesTrace === true) {
			trace.state = 'completed';
		}

		log.debug('launch.callback.observed', {
			sessionId: this.sessionId,
			sequence: this.sequence,
			traceId: trace.id,
			requestState: trace.state,
			callback: observation.callback,
			capturedAt: observation.capturedAt,
			firstObservedAt: trace.firstObservedAt,
			gameActionIdPresent: validGameActionId(observation.gameActionId),
			gameActionId: validGameActionId(observation.gameActionId) ? observation.gameActionId : null,
			appIdPresent: observation.appIdPresent ?? (observation.appId !== undefined && observation.appId.length > 0),
			parameters: observation.parameters,
		});
	}

	stop(): void {
		this.flushDuplicateSummaries();
		this.duplicateWindows.clear();
		this.tracesByAction.clear();
		this.recentTraceByApp.clear();

		log.debug('launch.diagnostics.stopped', {
			sessionId: this.sessionId,
			callbackCount: this.sequence,
		});
	}

	private resolveTrace(observation: LaunchObservation): LaunchTrace {
		if (validGameActionId(observation.gameActionId)) {
			const byAction = this.tracesByAction.get(observation.gameActionId);
			if (byAction !== undefined) {
				return byAction;
			}
		}

		if (observation.appId !== undefined) {
			const byApp = this.recentTraceByApp.get(observation.appId);
			if (byApp !== undefined && observation.capturedAt - byApp.lastObservedAt <= TRACE_CORRELATION_WINDOW_MS && byApp.state === 'observed') {
				if (validGameActionId(observation.gameActionId)) {
					byApp.gameActionId = observation.gameActionId;
					this.tracesByAction.set(observation.gameActionId, byApp);
				}
				return byApp;
			}
		}

		const trace: LaunchTrace = {
			id: `${this.sessionId}:${++this.traceSequence}`,
			gameActionId: validGameActionId(observation.gameActionId) ? observation.gameActionId : undefined,
			appId: observation.appId,
			firstObservedAt: observation.capturedAt,
			lastObservedAt: observation.capturedAt,
			state: 'observed',
		};

		if (trace.gameActionId !== undefined) {
			this.tracesByAction.set(trace.gameActionId, trace);
		}
		if (trace.appId !== undefined) {
			this.recentTraceByApp.set(trace.appId, trace);
		}

		return trace;
	}

	private flushDuplicateSummaries(): void {
		for (const duplicate of this.duplicateWindows.values()) {
			this.flushDuplicateSummary(duplicate);
		}
	}

	private prune(now: number): void {
		for (const [key, duplicate] of this.duplicateWindows) {
			if (now - duplicate.seenAt > DEDUPE_WINDOW_MS) {
				this.flushDuplicateSummary(duplicate);
				this.duplicateWindows.delete(key);
			}
		}

		for (const [gameActionId, trace] of this.tracesByAction) {
			if (now - trace.lastObservedAt > TRACE_RETENTION_MS) {
				this.tracesByAction.delete(gameActionId);
			}
		}

		for (const [appId, trace] of this.recentTraceByApp) {
			if (now - trace.lastObservedAt > TRACE_RETENTION_MS) {
				this.recentTraceByApp.delete(appId);
			}
		}
	}

	private flushDuplicateSummary(duplicate: DuplicateWindow): void {
		if (duplicate.suppressedCount === 0) {
			return;
		}

		log.debug('launch.callback.duplicates_suppressed', {
			sessionId: this.sessionId,
			traceId: duplicate.traceId,
			callback: duplicate.callback,
			firstSequence: duplicate.firstSequence,
			lastSequence: duplicate.lastSequence,
			firstCapturedAt: duplicate.firstCapturedAt,
			lastCapturedAt: duplicate.lastCapturedAt,
			suppressedCount: duplicate.suppressedCount,
		});
		duplicate.suppressedCount = 0;
	}
}
