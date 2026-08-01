import { definePlugin, Field, IconsModule } from '@steambrew/client';

import {
	forwardFrontendLog,
	getBackendHealth,
	verifyBackendProcessBridge,
	verifyBackendRpcTransport,
} from './backend/BackendClient';
import { startLaunchInterception } from './launch/LaunchInterceptor';
import type { LaunchInterception } from './launch/LaunchInterceptor';
import { startLaunchInstrumentation } from './launch/LaunchInstrumentation';
import type { LaunchInstrumentation } from './launch/LaunchInstrumentation';
import { log, setBackendLogSink, setDiagnosticLogging } from './logging/Logger';
import { GameMatchPanel } from './matching/GameMatchPanel';
import { getPluginSettings } from './settings/SettingsClient';
import { SettingsPanel } from './settings/SettingsPanel';
import { VortexProbePanel } from './vortex/VortexProbePanel';
import { warmVortexStateCache } from './vortex/VortexClient';

const PLUGIN_NAME = 'Vortex Launch Bridge';
const PLUGIN_VERSION = '1.0.5';
const VORTEX_CACHE_REFRESH_INTERVAL_MS = 5 * 60 * 1_000;

let activeLoadId = 0;
let launchInterception: LaunchInterception | undefined;
let launchInstrumentation: LaunchInstrumentation | undefined;

async function verifyBackend(loadId: number): Promise<boolean> {
	try {
		const health = await getBackendHealth();
		if (loadId !== activeLoadId) {
			return false;
		}

		if (health.pluginVersion !== PLUGIN_VERSION) {
			throw new Error(`Backend version ${health.pluginVersion} does not match frontend version ${PLUGIN_VERSION}.`);
		}

		await verifyBackendRpcTransport(`${PLUGIN_VERSION}:${loadId}`);
		if (loadId !== activeLoadId) {
			return false;
		}
		await verifyBackendProcessBridge();
		if (loadId !== activeLoadId) {
			return false;
		}

		log.info('backend.health.ok', {
			platform: health.platform,
			architecture: health.architecture,
			pluginVersion: health.pluginVersion,
			millenniumVersion: health.millenniumVersion,
			backendStartedAt: health.backendStartedAt,
		});
		log.info('backend.rpc_transport.ok', {
			pluginVersion: health.pluginVersion,
			singleJsonEnvelope: true,
		});
		log.info('backend.process_bridge.ok', {
			pluginVersion: health.pluginVersion,
			ffiCalls: false,
		});
		setBackendLogSink(forwardFrontendLog);
		return true;
	} catch (error: unknown) {
		if (loadId === activeLoadId) {
			log.error('backend.health.failed', error);
		}
		return false;
	}
}

export default definePlugin(() => {
	const loadId = ++activeLoadId;

	log.info('frontend.loaded', {
		pluginVersion: PLUGIN_VERSION,
	});
	launchInterception?.stop();
	launchInterception = undefined;
	launchInstrumentation?.stop();
	launchInstrumentation = undefined;

	let interception: LaunchInterception | undefined;
	let instrumentation: LaunchInstrumentation | undefined;
	let cacheRefreshTimer: number | undefined;
	let cacheRefreshInFlight = false;
	const refreshVortexCache = async (trigger: 'startup' | 'interval'): Promise<void> => {
		if (cacheRefreshInFlight || loadId !== activeLoadId) {
			return;
		}
		cacheRefreshInFlight = true;
		log.info('vortex.cache.refresh_started', { trigger });
		try {
			const result = await warmVortexStateCache();
			if (loadId !== activeLoadId) {
				return;
			}
			if (result.ok) {
				log.info('vortex.cache.refresh_completed', {
					trigger,
					durationMs: result.durationMs,
					profileCount: result.profileCount,
					discoveredGameCount: result.discoveredGameCount,
				});
			} else if (result.skipped && result.cacheAvailable) {
				log.info('vortex.cache.refresh_skipped', {
					trigger,
					reason: result.skipReason,
					cacheAvailable: true,
					durationMs: result.durationMs,
					profileCount: result.profileCount,
					discoveredGameCount: result.discoveredGameCount,
				});
			} else {
				log.warn('vortex.cache.refresh_failed', {
					trigger,
					cacheAvailable: result.cacheAvailable,
					durationMs: result.durationMs,
					error: result.error,
				});
			}
		} catch (error: unknown) {
			if (loadId === activeLoadId) {
				log.error('vortex.cache.refresh_bridge_failed', error, { trigger });
			}
		} finally {
			cacheRefreshInFlight = false;
		}
	};
	void verifyBackend(loadId).then(async (backendHealthy) => {
		if (!backendHealthy || loadId !== activeLoadId) {
			return;
		}

		try {
			const settings = await getPluginSettings();
			if (loadId !== activeLoadId) {
				return;
			}
			setDiagnosticLogging(settings.diagnosticLogging);
		} catch (error: unknown) {
			log.error('settings.initial_load_failed', error);
		}

		instrumentation = startLaunchInstrumentation();
		launchInstrumentation = instrumentation;
		interception = startLaunchInterception();
		launchInterception = interception;
		void refreshVortexCache('startup');
		cacheRefreshTimer = window.setInterval(() => {
			void refreshVortexCache('interval');
		}, VORTEX_CACHE_REFRESH_INTERVAL_MS);
	});

	return {
		title: PLUGIN_NAME,
		version: PLUGIN_VERSION,
		icon: <IconsModule.Settings />,
		content: (
			<>
				<Field
					label="Vortex Launch Bridge MVP active"
					description="Eligible direct Steam launch routes can activate a Vortex profile, then use the exact preserved Steam request or a configured per-game executable."
					icon={<IconsModule.Settings />}
				/>
				<SettingsPanel />
				<VortexProbePanel />
				<GameMatchPanel />
			</>
		),
		onDismount(): void {
			if (cacheRefreshTimer !== undefined) {
				window.clearInterval(cacheRefreshTimer);
				cacheRefreshTimer = undefined;
			}
			setBackendLogSink(undefined);
			interception?.stop();
			if (launchInterception === interception) {
				launchInterception = undefined;
			}
			instrumentation?.stop();
			if (launchInstrumentation === instrumentation) {
				launchInstrumentation = undefined;
			}

			if (activeLoadId === loadId) {
				activeLoadId += 1;
			}

			log.info('frontend.unloaded', {
				pluginVersion: PLUGIN_VERSION,
			});
		},
	};
});
