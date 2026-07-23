import {
	callOriginal,
	ELaunchSource,
	replacePatch,
	showModal,
	type Apps,
	type Patch,
	type ShowModalProps,
	type ShowModalResult,
} from '@steambrew/client';
import type { ReactNode } from 'react';

import { log } from '../logging/Logger';
import { matchVortexGame } from '../matching/MatchClient';
import type { VortexGameMatch } from '../matching/MatchTypes';
import { resolveLaunchPolicy } from '../settings/LaunchPolicy';
import {
	getGameLaunchSettings,
	getPluginSettings,
	launchConfiguredTarget,
	rememberLaunchChoice,
} from '../settings/SettingsClient';
import type { GameLaunchSettings, PluginSettings } from '../settings/SettingsTypes';
import { ActivationErrorModal } from '../ui/ActivationErrorModal';
import { ActivationProgressModal } from '../ui/ActivationProgressModal';
import { LaunchChoiceModal } from '../ui/LaunchChoiceModal';
import { ProfileChoiceModal } from '../ui/ProfileChoiceModal';
import { activateVortexProfile } from '../vortex/VortexClient';
import type { VortexProfile } from '../vortex/VortexTypes';
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
	| 'selecting-profile'
	| 'activating-vortex'
	| 'continuing-steam'
	| 'launching'
	| 'cancelled'
	| 'completed'
	| 'failed';

type CancellationReason =
	| 'dismissed'
	| 'profile-selection-dismissed'
	| 'activation-cancelled'
	| 'activation-failure-cancelled'
	| 'target-failure-cancelled'
	| 'continuation-failure-cancelled';

interface PendingLaunch {
	request: SteamLaunchRequest;
	state: PendingState;
	duplicateCount: number;
	pluginSettings?: PluginSettings;
	gameSettings?: GameLaunchSettings;
	modal?: ShowModalResult;
}

type PatchableApps = Apps & Record<PropertyKey, unknown>;

export interface LaunchInterception {
	stop(): void;
}

const SUPPORTED_LAUNCH_SOURCES = new Set<ELaunchSource>([
	ELaunchSource._2ftLibraryDetails,
	ELaunchSource._2ftLibraryListView,
	ELaunchSource._2ftLibraryGrid,
	ELaunchSource._2ftMiniModeList,
	ELaunchSource._10ft,
	ELaunchSource.DashAppLaunchCmdLine,
	ELaunchSource.DashGameIdLaunchCmdLine,
	ELaunchSource.RunByGameDir,
	ELaunchSource.SubCmdRunDashGame,
	ELaunchSource.SteamURL_Launch,
	ELaunchSource.SteamURL_Run,
	ELaunchSource.SteamURL_RunGame,
	ELaunchSource.SteamURL_RunGameIdOrJumplist,
	ELaunchSource.SteamURL_RunSafe,
	ELaunchSource.TrayIcon,
	ELaunchSource.LibraryLeftColumnContextMenu,
	ELaunchSource.LibraryLeftColumnDoubleClick,
	ELaunchSource.AppPortraitContextMenu,
]);
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

function showDesktopModal(modal: ReactNode, props: ShowModalProps): ShowModalResult {
	// @steambrew/client's omitted-parent fallback calls findSP(). In Steam's
	// desktop SharedJS context the gamepad navigation controller may not exist,
	// causing findSP() to throw before the modal is created. RunGame interception
	// already executes in the correct desktop window, so pass it explicitly.
	return showModal(modal, window, props);
}

function getSteamAppName(appId: number, vortexFallback?: string): string {
	try {
		const displayName = window.appStore
			?.GetAppOverviewByAppID(appId)
			?.display_name
			?.trim();
		if (displayName !== undefined && displayName.length > 0) {
			return displayName;
		}
	} catch {
		// The in-memory Steam app overview can be unavailable briefly during
		// client startup. The matched Vortex name is a safe display fallback.
	}

	const fallback = vortexFallback?.trim();
	return fallback !== undefined && fallback.length > 0 ? fallback : `Steam app ${appId}`;
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

	function rememberChoiceSafely(
		pending: PendingLaunch,
		choice: 'steam' | 'vortex',
		profileId = '',
	): void {
		if (pending.pluginSettings?.rememberChoicePerGame !== true) {
			return;
		}
		void rememberLaunchChoice(
			pending.request.numericAppId,
			choice,
			profileId,
		).catch((error: unknown) => {
			log.error('settings.remembered_choice.bridge_failed', error, {
				requestId: pending.request.requestId,
				steamAppId: pending.request.numericAppId,
				choice,
				profileIdRedacted: profileId.length > 0,
			});
		});
	}

	function showRecoveryFailure(
		pending: PendingLaunch,
		title: string,
		message: string,
		warning: string | undefined,
		continueReason: string,
		cancelReason: CancellationReason,
	): void {
		if (!isCurrent(pending) || !active) {
			removePending(pending);
			return;
		}

		pending.state = 'failed';
		closeModal(pending);
		pending.modal = showDesktopModal(
			<ActivationErrorModal
				message={message}
				warning={warning}
				onContinueWithSteam={() => continueWithSteam(pending, continueReason)}
				onCancel={() => cancelPending(pending, cancelReason)}
			/>,
			{
				strTitle: title,
				bHideMainWindowForPopouts: false,
				bNeverPopOut: true,
			},
		);
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
			showRecoveryFailure(
				pending,
				'Steam launch failed',
				'Steam did not accept the preserved launch request. You can retry it or cancel.',
				undefined,
				'continuation-failure-user-retried',
				'continuation-failure-cancelled',
			);
			return;
		}
		removePending(pending);
	}

	async function launchAfterVortexActivation(
		pending: PendingLaunch,
		profile: VortexProfile,
	): Promise<void> {
		if (!isCurrent(pending)) {
			return;
		}

		pending.state = 'launching';
		closeModal(pending);
		if (pending.gameSettings?.preferredLaunchTarget === 'custom') {
			try {
				const result = await launchConfiguredTarget(
					pending.request.numericAppId,
				);
				if (!isCurrent(pending) || !active) {
					return;
				}
				if (!result.ok || !result.started || result.target !== 'custom') {
					log.warn('launch.post_activation_custom_target_failed', {
						requestId: pending.request.requestId,
						steamAppId: pending.request.numericAppId,
						processStarted: result.started,
						executablePathRedacted: true,
						argumentsRedacted: true,
					});
					showRecoveryFailure(
						pending,
						'Custom launch tool failed',
						result.error ?? 'The configured custom launch tool did not start.',
						undefined,
						'custom-target-failed-user-continued',
						'target-failure-cancelled',
					);
					return;
				}

				pending.state = 'completed';
				rememberChoiceSafely(pending, 'vortex', profile.id);
				log.info('launch.post_activation_custom_target_started', {
					requestId: pending.request.requestId,
					steamAppId: pending.request.numericAppId,
					processId: result.processId,
					executablePathRedacted: true,
					argumentsRedacted: true,
					activationConfirmed: true,
					deploymentConfirmed: true,
				});
				removePending(pending);
				return;
			} catch (error: unknown) {
				if (!isCurrent(pending)) {
					return;
				}
				interceptionEnabled = false;
				log.error('launch.post_activation_custom_target_bridge_failed', error, {
					requestId: pending.request.requestId,
					steamAppId: pending.request.numericAppId,
					executablePathRedacted: true,
					argumentsRedacted: true,
					futureLaunchesPassThrough: true,
				});
				showRecoveryFailure(
					pending,
					'Custom launch tool failed',
					'The custom launch tool could not be started because the plugin backend is unavailable.',
					undefined,
					'custom-target-bridge-failed-user-continued',
					'target-failure-cancelled',
				);
				return;
			}
		}

		try {
			launcher.continueLaunch(pending.request);
			pending.state = 'completed';
			rememberChoiceSafely(pending, 'vortex', profile.id);
			log.info('launch.post_activation_steam_target_started', {
				requestId: pending.request.requestId,
				steamAppId: pending.request.numericAppId,
				launchSource: pending.request.launchSource,
				launchOptionsPresent: pending.request.launchOptions.length > 0,
				launchOptionsRedacted: true,
				duplicateCount: pending.duplicateCount,
				activationConfirmed: true,
				deploymentConfirmed: true,
			});
		} catch (error: unknown) {
			pending.state = 'failed';
			log.error('launch.post_activation_steam_target_failed', error, {
				requestId: pending.request.requestId,
				steamAppId: pending.request.numericAppId,
			});
			showRecoveryFailure(
				pending,
				'Steam launch failed',
				'Vortex activation completed, but Steam did not accept the preserved launch request.',
				undefined,
				'post-activation-steam-failed-user-retried',
				'target-failure-cancelled',
			);
			return;
		}
		removePending(pending);
	}

	function cancelPending(pending: PendingLaunch, reason: CancellationReason): void {
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
		});
	}

	function showActivationFailure(
		pending: PendingLaunch,
		message: string,
		warning?: string,
	): void {
		showRecoveryFailure(
			pending,
			'Vortex activation failed',
			message,
			warning,
			'activation-failed-user-continued',
			'activation-failure-cancelled',
		);
	}

	async function activateProfile(
		pending: PendingLaunch,
		match: VortexGameMatch,
		profile: VortexProfile,
	): Promise<void> {
		if (!isCurrent(pending) || !active || pending.state !== 'selecting-profile') {
			return;
		}
		if (match.vortexGameId === undefined || profile.gameId !== match.vortexGameId) {
			showActivationFailure(
				pending,
				'The selected Vortex profile does not match this game.',
			);
			return;
		}

		pending.state = 'activating-vortex';
		closeModal(pending);
		pending.modal = showDesktopModal(
			<ActivationProgressModal
				onDismiss={() => cancelPending(pending, 'activation-cancelled')}
			/>,
			{
				strTitle: 'Activating Vortex profile',
				bHideMainWindowForPopouts: false,
				bNeverPopOut: true,
			},
		);
		log.info('vortex.profile.selected', {
			requestId: pending.request.requestId,
			steamAppId: pending.request.numericAppId,
			profileIdRedacted: true,
			gameIdRedacted: true,
		});

		try {
			const result = await activateVortexProfile(match.vortexGameId, profile.id);
			if (!isCurrent(pending) || !active) {
				return;
			}
			if (
				!result.ok ||
				!result.profileActivationConfirmed ||
				!result.deploymentConfirmed
			) {
				log.warn('vortex.activation.not_confirmed', {
					requestId: pending.request.requestId,
					steamAppId: pending.request.numericAppId,
					started: result.started,
					timedOut: result.timedOut,
					timeoutMs: result.timeoutMs,
					wasVortexRunning: result.wasVortexRunning,
					isVortexRunningAfter: result.isVortexRunningAfter,
					readinessAvailable: result.readinessAvailable,
					readinessSignal: result.readinessSignal,
					identifiersRedacted: true,
				});
				showActivationFailure(
					pending,
					result.error ?? 'Vortex did not confirm the selected profile.',
					result.warning,
				);
				return;
			}

			log.info('vortex.activation.confirmed', {
				requestId: pending.request.requestId,
				steamAppId: pending.request.numericAppId,
				durationMs: result.durationMs,
				wasVortexRunning: result.wasVortexRunning,
				isVortexRunningAfter: result.isVortexRunningAfter,
				readinessSignal: result.readinessSignal,
				identifiersRedacted: true,
			});
			void launchAfterVortexActivation(pending, profile);
		} catch (error: unknown) {
			if (!isCurrent(pending)) {
				return;
			}
			interceptionEnabled = false;
			log.error('vortex.activation.bridge_failed', error, {
				requestId: pending.request.requestId,
				steamAppId: pending.request.numericAppId,
				futureLaunchesPassThrough: true,
			});
			showActivationFailure(
				pending,
				'Vortex activation could not be completed because the plugin backend is unavailable.',
			);
		}
	}

	function beginVortexFlow(pending: PendingLaunch, match: VortexGameMatch): void {
		if (
			!isCurrent(pending) ||
			!active ||
			pending.state !== 'awaiting-user' ||
			match.vortexGameId === undefined
		) {
			return;
		}
		pending.state = 'selecting-profile';

		const profiles = match.profiles.filter(
			(profile) => profile.gameId === match.vortexGameId,
		);
		if (profiles.length === 0) {
			showActivationFailure(
				pending,
				'No valid Vortex profile remains available for this game.',
			);
			return;
		}
		const preferredProfile = profiles.find(
			(profile) => profile.id === pending.gameSettings?.preferredProfileId,
		);
		if (preferredProfile !== undefined) {
			void activateProfile(pending, match, preferredProfile);
			return;
		}
		if (profiles.length === 1) {
			void activateProfile(pending, match, profiles[0]);
			return;
		}

		closeModal(pending);
		pending.modal = showDesktopModal(
			<ProfileChoiceModal
				profiles={profiles}
				onSelect={(profile) => void activateProfile(pending, match, profile)}
				onDismiss={() => cancelPending(pending, 'profile-selection-dismissed')}
			/>,
			{
				strTitle: 'Select a Vortex profile',
				bHideMainWindowForPopouts: false,
				bNeverPopOut: true,
			},
		);
		log.info('vortex.profile_selection.shown', {
			requestId: pending.request.requestId,
			steamAppId: pending.request.numericAppId,
			profileCount: profiles.length,
			identifiersRedacted: true,
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

		const profiles = match.profiles.filter(
			(profile) => profile.gameId === match.vortexGameId,
		);
		if (profiles.length === 0) {
			continueWithSteam(pending, 'no-valid-vortex-profiles');
			return;
		}
		if (pending.pluginSettings === undefined || pending.gameSettings === undefined) {
			continueWithSteam(pending, 'settings-unavailable-fail-open');
			return;
		}
		const decision = resolveLaunchPolicy(
			pending.pluginSettings,
			pending.gameSettings,
			profiles,
		);
		if (decision.kind === 'steam') {
			log.info('launch.remembered_choice.applied', {
				requestId: pending.request.requestId,
				steamAppId: pending.request.numericAppId,
				choice: 'steam',
			});
			continueWithSteam(pending, 'remembered-steam-choice');
			return;
		}
		if (decision.kind === 'vortex') {
			pending.state = 'selecting-profile';
			log.info('launch.remembered_choice.applied', {
				requestId: pending.request.requestId,
				steamAppId: pending.request.numericAppId,
				choice: 'vortex',
				profileIdRedacted: true,
			});
			void activateProfile(pending, match, decision.profile);
			return;
		}

		pending.state = 'awaiting-user';
		pending.modal = showDesktopModal(
			<LaunchChoiceModal
				appName={getSteamAppName(
					pending.request.numericAppId,
					match.vortexGameName,
				)}
				steamAppId={pending.request.numericAppId}
				profileCount={profiles.length}
				onLaunchWithVortex={() => beginVortexFlow(pending, match)}
				onContinueWithSteam={() => {
					rememberChoiceSafely(pending, 'steam');
					continueWithSteam(pending, 'user-selected-steam');
				}}
				onCancel={() => cancelPending(pending, 'dismissed')}
			/>,
			{
				strTitle: 'Vortex Launch Bridge',
				bHideMainWindowForPopouts: false,
				bNeverPopOut: true,
				popupWidth: 720,
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
			const [match, pluginSettings, gameSettings] = await withTimeout(
				Promise.all([
					matchVortexGame(pending.request.numericAppId),
					getPluginSettings(),
					getGameLaunchSettings(pending.request.numericAppId),
				]),
				MATCH_DECISION_TIMEOUT_MS,
			);
			if (!isCurrent(pending) || !active) {
				return;
			}
			if (match.steamAppId !== pending.request.numericAppId) {
				throw new Error('The backend returned a match for a different Steam AppID.');
			}
			if (gameSettings.steamAppId !== pending.request.numericAppId) {
				throw new Error('The backend returned settings for a different Steam AppID.');
			}
			pending.pluginSettings = pluginSettings;
			pending.gameSettings = gameSettings;
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
			!SUPPORTED_LAUNCH_SOURCES.has(request.launchSource)
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
		phase: 6,
		route: 'RunGame',
		supportedLaunchSources: [...SUPPORTED_LAUNCH_SOURCES].map((source) => ({
			value: source,
			name: ELaunchSource[source],
		})),
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
