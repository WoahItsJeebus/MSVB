import type { SteamLaunchRequest } from './LaunchRequest';

interface BypassToken {
	id: number;
	signature: string;
	expiresAt: number;
}

const BYPASS_TTL_MS = 5_000;

export class LaunchBypass {
	private readonly tokens = new Map<number, BypassToken>();
	private nextTokenId = 0;

	issue(request: SteamLaunchRequest, now = Date.now()): number {
		this.prune(now);
		this.nextTokenId += 1;
		this.tokens.set(this.nextTokenId, {
			id: this.nextTokenId,
			signature: request.signature,
			expiresAt: now + BYPASS_TTL_MS,
		});
		return this.nextTokenId;
	}

	consume(request: SteamLaunchRequest, now = Date.now()): boolean {
		this.prune(now);
		for (const token of this.tokens.values()) {
			if (token.signature === request.signature) {
				this.tokens.delete(token.id);
				return true;
			}
		}
		return false;
	}

	revoke(tokenId: number): void {
		this.tokens.delete(tokenId);
	}

	clear(): void {
		this.tokens.clear();
	}

	private prune(now: number): void {
		for (const [id, token] of this.tokens) {
			if (token.expiresAt <= now) {
				this.tokens.delete(id);
			}
		}
	}
}
