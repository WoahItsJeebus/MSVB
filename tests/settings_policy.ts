import { resolveLaunchPolicy } from '../frontend/settings/LaunchPolicy';
import {
	parseCustomLaunchResult,
	parseGameLaunchSettings,
	parsePluginSettings,
} from '../frontend/settings/SettingsTypes';
import type { VortexProfile } from '../frontend/vortex/VortexTypes';

function assert(condition: unknown, message: string): asserts condition {
	if (!condition) {
		throw new Error(message);
	}
}

const pluginSettings = parsePluginSettings({
	ok: true,
	settings: {
		alwaysAsk: false,
		rememberChoicePerGame: true,
		vortexActivationTimeoutMs: 20_000,
		diagnosticLogging: true,
	},
});
const profile: VortexProfile = {
	id: 'profile-a',
	name: 'Profile A',
	gameId: 'game-a',
};
const vortexGame = parseGameLaunchSettings({
	ok: true,
	game: {
		steamAppId: 1234,
		rememberedChoice: 'vortex',
		preferredProfileId: 'profile-a',
		preferredLaunchTarget: 'custom',
		customExecutable: 'C:\\Tools\\launcher.exe',
		customArguments: '--profile "A B"',
	},
});

const vortexDecision = resolveLaunchPolicy(pluginSettings, vortexGame, [profile]);
assert(vortexDecision.kind === 'vortex', 'A valid remembered Vortex profile should be applied.');
assert(
	vortexDecision.profile.id === 'profile-a',
	'The remembered policy must return the exact matching profile.',
);

const staleDecision = resolveLaunchPolicy(
	pluginSettings,
	{ ...vortexGame, preferredProfileId: 'missing-profile' },
	[profile],
);
assert(staleDecision.kind === 'ask', 'A stale profile must prompt instead of guessing.');

const steamDecision = resolveLaunchPolicy(
	pluginSettings,
	{ ...vortexGame, rememberedChoice: 'steam' },
	[profile],
);
assert(steamDecision.kind === 'steam', 'A valid remembered Steam decision should be applied.');

assert(
	resolveLaunchPolicy({ ...pluginSettings, alwaysAsk: true }, vortexGame, [profile]).kind === 'ask',
	'Always ask must override remembered choices.',
);
assert(
	resolveLaunchPolicy(
		{ ...pluginSettings, rememberChoicePerGame: false },
		vortexGame,
		[profile],
	).kind === 'ask',
	'Disabled remembering must ignore persisted choices.',
);

const customResult = parseCustomLaunchResult({
	ok: true,
	started: true,
	target: 'custom',
	processId: 42,
	durationMs: 3,
});
assert(customResult.started && customResult.processId === 42, 'Custom launch status should parse.');

let rejectedInvalidTarget = false;
try {
	parseGameLaunchSettings({
		ok: true,
		game: {
			steamAppId: 1234,
			preferredLaunchTarget: 'shell',
			customArguments: '',
		},
	});
} catch {
	rejectedInvalidTarget = true;
}
assert(rejectedInvalidTarget, 'Unknown launch targets must be rejected.');

let rejectedInvalidTimeout = false;
try {
	parsePluginSettings({
		ok: true,
		settings: {
			alwaysAsk: true,
			rememberChoicePerGame: false,
			vortexActivationTimeoutMs: 999,
			diagnosticLogging: false,
		},
	});
} catch {
	rejectedInvalidTimeout = true;
}
assert(rejectedInvalidTimeout, 'Out-of-range activation timeouts must be rejected.');

console.log('Settings and launch policy tests passed');
