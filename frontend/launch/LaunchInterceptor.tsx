import {
	callOriginal,
	ELaunchSource,
	replacePatch,
	showModal,
	type Apps,
	type Patch,
	type ShowModalResult,
} from '@steambrew/client';

import { log } from '../logging/Logger';
import { matchVortexGame } from '../matching/MatchClient';
import type { VortexGameMatch } from '../matching/MatchTypes';
import { LaunchChoiceModal } from '../ui/LaunchChoiceModal';
import { LaunchBypass } from './LaunchBypass';
import {
	createSteamLaunchRequest,
	type SteamLaunchRequest,
	type SteamRunGameArguments,
} from './LaunchRequest';
import { SteamLauncher } from './SteamLauncher';

type PendingState =
	| 'checking-vortex'
	| 'awaiting-user'
	| 'continuing-steam'
	| 'cancelled'
	| 'completed'
	| 'failed';

interface PendingLaunch {
	request: SteamLaunchRequest;
	state: PendingState;
	duplicateCount: number;
	modal?: ShowModalResult;
}

type PatchableApps = Apps & Record<PropertyKey, unknown>;

export interface LaunchInterception {
	stop(): void;
}

const SUPPORTED_LAUNCH_SOURCE = ELaunchSource._2ftLibraryDetails;
const MATCH_DECISION_TIMEOUT_MS = 20_000;
const CANCELLED_RETRY_WINDOW_MS = 5_000;

function callOriginalResult(): void {
	// replacePatch uses this runtime symbol to invoke the exact function it
	// replaced. Its generic return type does not include the symbol for void APIs.
	return callOriginal as unknown as void;
}

function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
	return new Promise<T>((resolve, reject) => {
		const timeoutId = setTimeout(() => {
			reject(new Error(`Launch matching timed out after ${timeoutMs} ms.`));
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

export function startLaunchInterception(): LaunchInterception {
	let active = true;
	let interceptionEnabled = true;
	const pendingBySignature = new Map<string, PendingLaunch>();
	const recentlyCancelledByApp = new Map<number, number>();
	const bypass = new LaunchBypass();

	if (typeof SteamClient === 'undefined' || SteamClient.Apps === undefined) {
		log.error('launch.interception.unavailable', new Error('SteamClient.Apps is unavailable.'));
		return {
			stop(): void {
				active = false;
				bypass.clear();
			},
		};
	}

	const apps = SteamClient.Apps;
	if (typeof apps.RunGame !== 'function') {
		log.error('launch.interception.unavailable', new Error('SteamClient.Apps.RunGame is unavailable.'));
		return {
			stop(): void {
				active = false;
				bypass.clear();
			},
		};
	}

	const launcher = new SteamLauncher(apps, bypass);
	let patch: Patch<PatchableApps, 'RunGame'> | undefined;

	function pruneCancelled(now = Date.now()): void {
		for (const [appId, expiresAt] of recentlyCancelledByApp) {
			if (expiresAt <= now) {
				recentlyCancelledByApp.delete(appId);
			}
		}
	}

	function isCurrent(pending: PendingLaunch): boolean {
		return pendingBySignature.get(pending.request.signature) === pending;
	}

	function closeModal(pending: PendingLaunch): void {
		const modal = pending.modal;
		pending.modal = undefined;
		if (modal !== undefined) {
			try {
				// Close() intentionally does not invoke modal callbacks.
				modal.Close();
			} catch (error: unknown) {
				log.error('launch.modal.close_failed', error, {
					requestId: pending.request.requestId,
					steamAppId: pending.request.numericAppId,
				});
			}
		}
	}

	function removePending(pending: PendingLaunch): void {
		if (isCurrent(pending)) {
			pendingBySignature.delete(pending.request.signature);
		}
	}

	function continueWithSteam(pending: PendingLaunch, reason: string): void {
		if (!isCurrent(pending) || pending.state === 'continuing-steam') {
			return;
		}

		pending.state = 'continuing-steam';
		closeModal(pending);
		try {
			launcher.continueLaunch(pending.request);
			pending.state = 'completed';
			log.info('launch.continued_with_steam', {
				requestId: pending.request.requestId,
				steamAppId: pending.request.numericAppId,
				launchSource: pending.request.launchSource,
				launchOptionsPresent: pending.request.launchOptions.length > 0,
				launchOptionsRedacted: true,
				duplicateCount: pending.duplicateCount,
				reason,
			});
		} catch (error: unknown) {
			pending.state = 'failed';
			log.error('launch.continuation.failed', error, {
				requestId: pending.request.requestId,
				steamAppId: pending.request.numericAppId,
				reason,
			});
		} finally {
			removePending(pending);
		}
	}

	function cancelPending(pending: PendingLaunch, reason: 'dismissed' | 'vortex-selected'): void {
		if (!isCurrent(pending)) {
			return;
		}

		pending.state = 'cancelled';
		closeModal(pending);
		recentlyCancelledByApp.set(
			pending.request.numericAppId,
			Date.now() + CANCELLED_RETRY_WINDOW_MS,
		);
		removePending(pending);
		log.info('launch.pending_cancelled', {
			requestId: pending.request.requestId,
			steamAppId: pending.request.numericAppId,
			reason,
			vortexActivationDeferred: reason === 'vortex-selected',
		});
	}

	function showChoice(pending: PendingLaunch, match: VortexGameMatch): void {
		if (!isCurrent(pending) || !active) {
			return;
		}
		if (
			!match.matched ||
			match.vortexGameId === undefined ||
			match.profiles.length === 0
		) {
			continueWithSteam(pending, 'no-matching-vortex-profiles');
			return;
		}

		pending.state = 'awaiting-user';
		pending.modal = showModal(
			<LaunchChoiceModal
				steamAppId={pending.request.numericAppId}
				profileCount={match.profiles.length}
				onLaunchWithVortex={() => cancelPending(pending, 'vortex-selected')}
				onContinueWithSteam={() => continueWithSteam(pending, 'user-selected-steam')}
				onDismiss={() => cancelPending(pending, 'dismissed')}
			/>,
			undefined,
			{
				strTitle: 'Vortex Launch Bridge',
				bHideMainWindowForPopouts: false,
				bNeverPopOut: true,
			},
		);

		log.info('launch.modal.shown', {
			requestId: pending.request.requestId,
			steamAppId: pending.request.numericAppId,
			matchConfidence: match.confidence,
			profileCount: match.profiles.length,
			vortexGameIdRedacted: true,
		});
	}

	async function checkVortex(pending: PendingLaunch): Promise<void> {
		try {
			const match = await withTimeout(
				matchVortexGame(pending.request.numericAppId),
				MATCH_DECISION_TIMEOUT_MS,
			);
			if (!isCurrent(pending) || !active) {
				return;
			}
			if (match.steamAppId !== pending.request.numericAppId) {
				throw new Error('The backend returned a match for a different Steam AppID.');
			}
			showChoice(pending, match);
		} catch (error: unknown) {
			if (!isCurrent(pending)) {
				return;
			}
			// A frontend/backend bridge failure disables interception for this
			// session. The current request fails open and future calls pass through.
			interceptionEnabled = false;
			log.error('launch.interception.suspended', error, {
				requestId: pending.request.requestId,
				steamAppId: pending.request.numericAppId,
				futureLaunchesPassThrough: true,
			});
			continueWithSteam(pending, 'matching-error-fail-open');
		}
	}

	function handleRunGame(args: SteamRunGameArguments): void {
		const request = createSteamLaunchRequest(args);
		if (request === undefined) {
			return callOriginalResult();
		}

		if (bypass.consume(request)) {
			log.info('launch.bypass.consumed', {
				requestId: request.requestId,
				steamAppId: request.numericAppId,
				launchSource: request.launchSource,
			});
			return callOriginalResult();
		}

		if (
			!active ||
			!interceptionEnabled ||
			request.launchSource !== SUPPORTED_LAUNCH_SOURCE
		) {
			return callOriginalResult();
		}

		pruneCancelled(request.capturedAt);
		if (recentlyCancelledByApp.has(request.numericAppId)) {
			log.info('launch.cancelled_retry_suppressed', {
				requestId: request.requestId,
				steamAppId: request.numericAppId,
			});
			return;
		}

		const duplicate = pendingBySignature.get(request.signature);
		if (duplicate !== undefined) {
			duplicate.duplicateCount += 1;
			log.info('launch.pending_duplicate_suppressed', {
				requestId: duplicate.request.requestId,
				steamAppId: duplicate.request.numericAppId,
				state: duplicate.state,
				duplicateCount: duplicate.duplicateCount,
			});
			return;
		}

		if (pendingBySignature.size > 0) {
			const activePending = pendingBySignature.values().next().value as
				| PendingLaunch
				| undefined;
			if (activePending?.request.numericAppId === request.numericAppId) {
				activePending.duplicateCount += 1;
				log.info('launch.pending_duplicate_suppressed', {
					requestId: activePending.request.requestId,
					steamAppId: activePending.request.numericAppId,
					state: activePending.state,
					duplicateCount: activePending.duplicateCount,
					signatureVaried: true,
				});
				return;
			}
			log.warn('launch.concurrent_request_passed_through', {
				requestId: request.requestId,
				steamAppId: request.numericAppId,
				activePendingCount: pendingBySignature.size,
			});
			return callOriginalResult();
		}

		const pending: PendingLaunch = {
			request,
			state: 'checking-vortex',
			duplicateCount: 0,
		};
		pendingBySignature.set(request.signature, pending);
		log.info('launch.intercepted', {
			requestId: request.requestId,
			steamAppId: request.numericAppId,
			launchSource: request.launchSource,
			launchOptionsPresent: request.launchOptions.length > 0,
			launchOptionsRedacted: true,
			parameter3: request.parameter3,
		});
		void checkVortex(pending);
	}

	try {
		patch = replacePatch(
			apps as PatchableApps,
			'RunGame',
			(args) => handleRunGame(args as SteamRunGameArguments),
		);
	} catch (error: unknown) {
		interceptionEnabled = false;
		log.error('launch.interception.registration_failed', error, {
			futureLaunchesPassThrough: true,
		});
	}

	log.info('launch.interception.started', {
		phase: 4,
		route: 'RunGame',
		launchSource: SUPPORTED_LAUNCH_SOURCE,
		launchSourceName: ELaunchSource[SUPPORTED_LAUNCH_SOURCE],
		oneShotBypass: true,
		cancelLaunchUsed: false,
	});

	return {
		stop(): void {
			if (!active) {
				return;
			}
			active = false;
			interceptionEnabled = false;

			// Fail open on unload so a backend check or open modal cannot strand
			// a request after the plugin has gone away.
			for (const pending of [...pendingBySignature.values()]) {
				continueWithSteam(pending, 'plugin-unload-fail-open');
			}

			if (patch !== undefined && !patch.hasUnpatched) {
				try {
					patch.unpatch();
					log.info('launch.hook.unregistered', {
						hook: 'RunGame.replacePatch',
					});
				} catch (error: unknown) {
					log.error('launch.hook.unregister_failed', error, {
						hook: 'RunGame.replacePatch',
					});
				}
			}

			pendingBySignature.clear();
			recentlyCancelledByApp.clear();
			bypass.clear();
			log.info('launch.interception.stopped', {
				pendingCount: 0,
			});
		},
	};
}
