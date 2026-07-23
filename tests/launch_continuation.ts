import type { Apps, ELaunchSource } from '@steambrew/client';

import { LaunchBypass } from '../frontend/launch/LaunchBypass';
import {
	createSteamLaunchRequest,
	runGameArguments,
	type SteamRunGameArguments,
} from '../frontend/launch/LaunchRequest';
import { SteamLauncher } from '../frontend/launch/SteamLauncher';

function assert(condition: unknown, message: string): asserts condition {
	if (!condition) {
		throw new Error(message);
	}
}

const originalArgs: SteamRunGameArguments = [
	'1234',
	'-windowed -user-option',
	7,
	100 as ELaunchSource,
];
const request = createSteamLaunchRequest(originalArgs, 1_000);
assert(request !== undefined, 'A valid RunGame tuple should produce a launch request.');
assert(request.numericAppId === 1234, 'The AppID should be parsed without changing its string form.');
assert(
	JSON.stringify(runGameArguments(request)) === JSON.stringify(originalArgs),
	'The replay tuple must exactly equal the intercepted tuple.',
);

const calls: SteamRunGameArguments[] = [];
const apps = {
	RunGame(...args: SteamRunGameArguments): void {
		calls.push(args);
	},
} as unknown as Apps;
const bypass = new LaunchBypass();
const launcher = new SteamLauncher(apps, bypass);

launcher.continueLaunch(request);
assert(calls.length === 1, 'Steam continuation should invoke RunGame once.');
assert(
	JSON.stringify(calls[0]) === JSON.stringify(originalArgs),
	'Steam continuation must preserve every RunGame argument.',
);
assert(bypass.consume(request), 'The issued bypass should match the exact continuation once.');
assert(!bypass.consume(request), 'A consumed bypass must not match twice.');

const changedRequest = createSteamLaunchRequest(
	['1234', '-different', 7, 100 as ELaunchSource],
	1_001,
);
assert(changedRequest !== undefined, 'The changed tuple should still be a valid request.');
const tokenId = bypass.issue(request, 2_000);
assert(
	!bypass.consume(changedRequest, 2_001),
	'A bypass must not match a request with different launch options.',
);
bypass.revoke(tokenId);

bypass.issue(request, 3_000);
assert(!bypass.consume(request, 8_000), 'An expired bypass must not be consumed.');

assert(
	createSteamLaunchRequest(['not-an-appid', '', 0, 100 as ELaunchSource]) === undefined,
	'Non-numeric AppIDs must pass through without interception.',
);

console.log('Launch continuation tests passed');
