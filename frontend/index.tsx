import { definePlugin, Field, IconsModule } from '@steambrew/client';

import { getBackendHealth } from './backend/BackendClient';
import { log } from './logging/Logger';

const PLUGIN_NAME = 'Vortex Launch Bridge';
const PLUGIN_VERSION = '0.1.0';

let activeLoadId = 0;

async function verifyBackend(loadId: number): Promise<void> {
	try {
		const health = await getBackendHealth();
		if (loadId !== activeLoadId) {
			return;
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
	} catch (error: unknown) {
		if (loadId === activeLoadId) {
			log.error('backend.health.failed', error);
		}
	}
}

export default definePlugin(() => {
	const loadId = ++activeLoadId;

	log.info('frontend.loaded', {
		pluginVersion: PLUGIN_VERSION,
	});
	void verifyBackend(loadId);

	return {
		title: PLUGIN_NAME,
		version: PLUGIN_VERSION,
		icon: <IconsModule.Settings />,
		content: (
			<Field
				label="Phase 0 ready"
				description="The Lua backend health check runs when the plugin loads. Steam launch behavior is unchanged."
				icon={<IconsModule.Settings />}
				bottomSeparator="none"
			/>
		),
		onDismount(): void {
			if (activeLoadId === loadId) {
				activeLoadId += 1;
			}

			log.info('frontend.unloaded', {
				pluginVersion: PLUGIN_VERSION,
			});
		},
	};
});
