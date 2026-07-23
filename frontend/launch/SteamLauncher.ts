import type { Apps } from '@steambrew/client';

import { LaunchBypass } from './LaunchBypass';
import { runGameArguments, type SteamLaunchRequest } from './LaunchRequest';

export class SteamLauncher {
	constructor(
		private readonly apps: Apps,
		private readonly bypass: LaunchBypass,
	) {}

	continueLaunch(request: SteamLaunchRequest): void {
		const tokenId = this.bypass.issue(request);
		try {
			this.apps.RunGame(...runGameArguments(request));
		} catch (error: unknown) {
			this.bypass.revoke(tokenId);
			throw error;
		}
	}
}
