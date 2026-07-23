import { beforePatch, ELaunchSource } from '@steambrew/client';
import type { Apps, GameAction, Unregisterable } from '@steambrew/client';

import { log } from '../logging/Logger';
import { LaunchDiagnostics } from './LaunchDiagnostics';
import type { LaunchObservation } from './LaunchDiagnostics';
import { describeDiagnosticToken, describeNumericIdentifier, fingerprintForDedupe, summarizeSensitiveText } from './LaunchRedaction';

interface Cleanup {
	name: string;
	dispose(): void;
}

export interface LaunchInstrumentation {
	stop(): void;
}

type PatchableApps = Apps & Record<PropertyKey, unknown>;

function isUnregisterable(value: unknown): value is Unregisterable {
	return typeof value === 'object' && value !== null && 'unregister' in value && typeof value.unregister === 'function';
}

function launchSourceDetails(value: ELaunchSource): Readonly<Record<string, unknown>> {
	const enumName = ELaunchSource[value];
	return {
		value,
		name: typeof enumName === 'string' ? enumName : 'Unknown',
	};
}

function safeAppId(value: string): string | undefined {
	const description = describeNumericIdentifier(value);
	return description.redacted ? undefined : description.value;
}

function safeGameActionId(value: number): number | undefined {
	return Number.isSafeInteger(value) && value > 0 ? value : undefined;
}

export function startLaunchInstrumentation(): LaunchInstrumentation {
	const diagnostics = new LaunchDiagnostics();
	const cleanups: Cleanup[] = [];
	const detailRequests = new Map<string, number>();
	let active = true;

	if (typeof SteamClient === 'undefined' || SteamClient.Apps === undefined) {
		log.error('launch.instrumentation.unavailable', new Error('SteamClient.Apps is unavailable.'));
		return {
			stop(): void {
				if (!active) {
					return;
				}
				active = false;
				diagnostics.stop();
			},
		};
	}

	const apps = SteamClient.Apps;
	const availability = {
		RegisterForGameActionUserRequest: typeof apps.RegisterForGameActionUserRequest === 'function',
		RegisterForGameActionStart: typeof apps.RegisterForGameActionStart === 'function',
		RegisterForGameActionTaskChange: typeof apps.RegisterForGameActionTaskChange === 'function',
		RegisterForGameActionEnd: typeof apps.RegisterForGameActionEnd === 'function',
		GetGameActionDetails: typeof apps.GetGameActionDetails === 'function',
		RunGame: typeof apps.RunGame === 'function',
		CancelLaunch: typeof apps.CancelLaunch === 'function',
	};

	function observeSafely(callback: LaunchObservation['callback'], createObservation: () => LaunchObservation): void {
		if (!active) {
			return;
		}

		try {
			diagnostics.record(createObservation());
		} catch (error: unknown) {
			log.error('launch.callback.processing_failed', error, { callback });
		}
	}

	function register(name: string, registrar: () => Unregisterable): void {
		try {
			const handle: unknown = registrar();
			if (!isUnregisterable(handle)) {
				throw new Error(`${name} did not return an unregisterable handle.`);
			}

			cleanups.push({
				name,
				dispose(): void {
					handle.unregister();
				},
			});
		} catch (error: unknown) {
			log.error('launch.hook.registration_failed', error, { hook: name });
		}
	}

	function requestGameActionDetails(appId: string, gameActionId: number): void {
		if (!active || !availability.GetGameActionDetails) {
			return;
		}

		const numericAppId = Number(appId);
		const requestKey = `${gameActionId}:${appId}`;
		const requestedAt = Date.now();
		for (const [key, timestamp] of detailRequests) {
			if (requestedAt - timestamp > 60_000) {
				detailRequests.delete(key);
			}
		}

		if (!Number.isSafeInteger(numericAppId) || numericAppId <= 0 || detailRequests.has(requestKey)) {
			return;
		}
		detailRequests.set(requestKey, requestedAt);

		try {
			// The installed type names this argument appId. Runtime validation is still required
			// because older community examples disagree about whether this is an action identifier.
			apps.GetGameActionDetails(numericAppId, (details: GameAction) => {
				observeSafely('game-action-details', () => ({
					callback: 'game-action-details',
					capturedAt: Date.now(),
					gameActionId: safeGameActionId(details.nGameActionID) ?? safeGameActionId(gameActionId),
					appId: safeAppId(appId),
					appIdPresent: appId.length > 0,
					parameters: {
						position1TypedAsGameAction: {
							nGameActionID: safeGameActionId(details.nGameActionID) ?? null,
							gameid: describeNumericIdentifier(details.gameid),
							strActionName: describeDiagnosticToken(details.strActionName),
							strTaskName: describeDiagnosticToken(details.strTaskName),
							strTaskDetails: summarizeSensitiveText(details.strTaskDetails),
							nLaunchOption: details.nLaunchOption,
							nSecondsRemaing: details.nSecondsRemaing,
							strNumDone: describeNumericIdentifier(details.strNumDone),
							strNumTotal: describeNumericIdentifier(details.strNumTotal),
							bWaitingForUI: details.bWaitingForUI,
						},
					},
					signature: [
						details.nGameActionID,
						details.gameid,
						details.strActionName,
						details.strTaskName,
						fingerprintForDedupe(details.strTaskDetails),
						details.nLaunchOption,
						details.bWaitingForUI,
					],
				}));
			});
		} catch (error: unknown) {
			log.error('launch.game_action_details.failed', error, {
				gameActionId,
				appId: describeNumericIdentifier(appId),
			});
		}
	}

	if (availability.RegisterForGameActionUserRequest) {
		register('RegisterForGameActionUserRequest', () =>
			apps.RegisterForGameActionUserRequest((gameActionId, appId, action, requestedAction, appId2) => {
				observeSafely('game-action-user-request', () => ({
					callback: 'game-action-user-request',
					capturedAt: Date.now(),
					gameActionId: safeGameActionId(gameActionId),
					appId: safeAppId(appId),
					appIdPresent: appId.length > 0,
					parameters: {
						position1GameActionId: safeGameActionId(gameActionId) ?? null,
						position2AppId: describeNumericIdentifier(appId),
						position3Action: describeDiagnosticToken(action),
						position4RequestedAction: describeDiagnosticToken(requestedAction),
						position5TypedAsAppId2: describeNumericIdentifier(appId2),
					},
					signature: [gameActionId, appId, action, requestedAction, fingerprintForDedupe(appId2)],
				}));
			}),
		);
	}

	if (availability.RegisterForGameActionStart) {
		register('RegisterForGameActionStart', () =>
			apps.RegisterForGameActionStart((gameActionId, appId, action, launchSource) => {
				observeSafely('game-action-start', () => ({
					callback: 'game-action-start',
					capturedAt: Date.now(),
					gameActionId: safeGameActionId(gameActionId),
					appId: safeAppId(appId),
					appIdPresent: appId.length > 0,
					parameters: {
						position1GameActionId: safeGameActionId(gameActionId) ?? null,
						position2AppId: describeNumericIdentifier(appId),
						position3Action: describeDiagnosticToken(action),
						position4LaunchSource: launchSourceDetails(launchSource),
					},
					signature: [gameActionId, appId, action, launchSource],
				}));
				requestGameActionDetails(appId, gameActionId);
			}),
		);
	}

	if (availability.RegisterForGameActionTaskChange) {
		register('RegisterForGameActionTaskChange', () =>
			apps.RegisterForGameActionTaskChange((gameActionId, appId, action, requestedAction, parameter5) => {
				observeSafely('game-action-task-change', () => ({
					callback: 'game-action-task-change',
					capturedAt: Date.now(),
					gameActionId: safeGameActionId(gameActionId),
					appId: safeAppId(appId),
					appIdPresent: appId.length > 0,
					parameters: {
						position1GameActionId: safeGameActionId(gameActionId) ?? null,
						position2AppId: describeNumericIdentifier(appId),
						position3Action: describeDiagnosticToken(action),
						position4RequestedAction: describeDiagnosticToken(requestedAction),
						position5Unknown: summarizeSensitiveText(parameter5),
					},
					signature: [gameActionId, appId, action, requestedAction, fingerprintForDedupe(parameter5)],
				}));
			}),
		);
	}

	if (availability.RegisterForGameActionEnd) {
		register('RegisterForGameActionEnd', () =>
			apps.RegisterForGameActionEnd((gameActionId) => {
				observeSafely('game-action-end', () => ({
					callback: 'game-action-end',
					capturedAt: Date.now(),
					gameActionId: safeGameActionId(gameActionId),
					parameters: {
						position1GameActionId: safeGameActionId(gameActionId) ?? null,
					},
					signature: [gameActionId],
					completesTrace: true,
				}));
			}),
		);
	}

	if (availability.RunGame) {
		try {
			// This is the only launch method patched in Phase 1. beforePatch observes the
			// typed arguments, then invokes the original function with the same this/args/return.
			const patch = beforePatch(apps as PatchableApps, 'RunGame', ([appId, launchOptions, parameter3, launchSource]) => {
				observeSafely('run-game', () => ({
					callback: 'run-game',
					capturedAt: Date.now(),
					appId: safeAppId(appId),
					appIdPresent: appId.length > 0,
					parameters: {
						position1AppId: describeNumericIdentifier(appId),
						position2LaunchOptions: summarizeSensitiveText(launchOptions),
						position3Unknown: parameter3,
						position4LaunchSource: launchSourceDetails(launchSource),
					},
					signature: [appId, fingerprintForDedupe(launchOptions), parameter3, launchSource],
				}));
			});

			cleanups.push({
				name: 'RunGame.beforePatch',
				dispose(): void {
					if (!patch.hasUnpatched) {
						patch.unpatch();
					}
				},
			});
		} catch (error: unknown) {
			log.error('launch.run_game_patch.failed', error);
		}
	}

	log.info('launch.instrumentation.started', {
		phase: 1,
		sharedJsContext: true,
		availability,
		activeObservers: cleanups.map((cleanup) => cleanup.name),
		behavior: 'observe-only',
	});

	return {
		stop(): void {
			if (!active) {
				return;
			}
			active = false;

			for (const cleanup of [...cleanups].reverse()) {
				try {
					cleanup.dispose();
					log.info('launch.hook.unregistered', { hook: cleanup.name });
				} catch (error: unknown) {
					log.error('launch.hook.unregister_failed', error, { hook: cleanup.name });
				}
			}

			detailRequests.clear();
			diagnostics.stop();
			log.info('launch.instrumentation.stopped', {
				behavior: 'observe-only',
			});
		},
	};
}
