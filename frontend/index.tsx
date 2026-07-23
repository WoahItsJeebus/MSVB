import { definePlugin, Field, IconsModule } from '@steambrew/client';

import { getBackendHealth } from './backend/BackendClient';
import { startLaunchInstrumentation } from './launch/LaunchInstrumentation';
import type { LaunchInstrumentation } from './launch/LaunchInstrumentation';
import { log } from './logging/Logger';
import { VortexProbePanel } from './vortex/VortexProbePanel';

const PLUGIN_NAME = 'Vortex Launch Bridge';
const PLUGIN_VERSION = '0.3.0';

let activeLoadId = 0;
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

		log.info('backend.health.ok', {
			platform: health.platform,
			architecture: health.architecture,
			pluginVersion: health.pluginVersion,
			millenniumVersion: health.millenniumVersion,
			backendStartedAt: health.backendStartedAt,
		});
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
	launchInstrumentation?.stop();
	launchInstrumentation = undefined;

	let instrumentation: LaunchInstrumentation | undefined;
	void verifyBackend(loadId).then((backendHealthy) => {
		if (!backendHealthy || loadId !== activeLoadId) {
			return;
		}

		instrumentation = startLaunchInstrumentation();
		launchInstrumentation = instrumentation;
	});

	return {
		title: PLUGIN_NAME,
		version: PLUGIN_VERSION,
		icon: <IconsModule.Settings />,
		content: (
			<>
				<Field
					label="Phase 1 diagnostics active"
					description="Launch callbacks remain observation-only. The plugin does not cancel, delay, or replace Steam launch behavior."
					icon={<IconsModule.Settings />}
				/>
				<VortexProbePanel />
			</>
		),
		onDismount(): void {
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
