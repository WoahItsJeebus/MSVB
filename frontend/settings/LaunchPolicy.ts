import type { VortexProfile } from '../vortex/VortexTypes';
import type { GameLaunchSettings, PluginSettings } from './SettingsTypes';

export type LaunchPolicyDecision =
	| { kind: 'ask' }
	| { kind: 'steam' }
	| { kind: 'vortex'; profile: VortexProfile };

export function resolveLaunchPolicy(
	pluginSettings: PluginSettings,
	gameSettings: GameLaunchSettings,
	profiles: readonly VortexProfile[],
): LaunchPolicyDecision {
	if (
		pluginSettings.alwaysAsk ||
		!pluginSettings.rememberChoicePerGame ||
		gameSettings.rememberedChoice === undefined
	) {
		return { kind: 'ask' };
	}
	if (gameSettings.rememberedChoice === 'steam') {
		return { kind: 'steam' };
	}

	const profile = profiles.find(
		(candidate) => candidate.id === gameSettings.preferredProfileId,
	);
	return profile === undefined ? { kind: 'ask' } : { kind: 'vortex', profile };
}
