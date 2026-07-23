import { definePlugin, Field, IconsModule } from '@steambrew/client';

import { getBackendHealth } from './backend/BackendClient';
import { startLaunchInterception } from './launch/LaunchInterceptor';
import type { LaunchInterception } from './launch/LaunchInterceptor';
import { startLaunchInstrumentation } from './launch/LaunchInstrumentation';
import type { LaunchInstrumentation } from './launch/LaunchInstrumentation';
import { log } from './logging/Logger';
import { GameMatchPanel } from './matching/GameMatchPanel';
import { VortexProbePanel } from './vortex/VortexProbePanel';

const PLUGIN_NAME = 'Vortex Launch Bridge';
const PLUGIN_VERSION = '0.5.0';

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
	launchInterception?.stop();
	launchInterception = undefined;
	launchInstrumentation?.stop();
	launchInstrumentation = undefined;

	let interception: LaunchInterception | undefined;
	let instrumentation: LaunchInstrumentation | undefined;
	void verifyBackend(loadId).then((backendHealthy) => {
		if (!backendHealthy || loadId !== activeLoadId) {
			return;
		}

		instrumentation = startLaunchInstrumentation();
		launchInstrumentation = instrumentation;
		interception = startLaunchInterception();
		launchInterception = interception;
	});

	return {
		title: PLUGIN_NAME,
		version: PLUGIN_VERSION,
		icon: <IconsModule.Settings />,
		content: (
			<>
				<Field
					label="Phase 4 direct-launch interception active"
					description="Only direct Library Details RunGame requests are eligible. Other launch sources pass through unchanged; matching failures fail open."
					icon={<IconsModule.Settings />}
				/>
				<VortexProbePanel />
				<GameMatchPanel />
			</>
		),
		onDismount(): void {
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
