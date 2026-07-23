import { DialogButton, Field, TextField } from '@steambrew/client';
import { useState } from 'react';

import { log } from '../logging/Logger';
import {
	getSteamAppIdOverride,
	matchVortexGame,
	resolveSteamInstallation,
	setSteamAppIdOverride,
} from './MatchClient';
import type { SteamInstallationResult, VortexGameMatch } from './MatchTypes';

type BusyOperation = 'resolve' | 'match' | 'load-override' | 'save-override';

function parseAppId(value: string): number | undefined {
	if (!/^[1-9]\d*$/.test(value)) {
		return undefined;
	}
	const appId = Number(value);
	if (!Number.isSafeInteger(appId) || appId > 4_294_967_295) {
		return undefined;
	}
	return appId;
}

function resultDescription(
	installation: SteamInstallationResult | undefined,
	match: VortexGameMatch | undefined,
	status: string | undefined,
): string {
	if (status !== undefined) {
		return status;
	}
	if (match !== undefined) {
		if (match.matched) {
			const profileLabel = match.profiles.length === 1 ? 'profile' : 'profiles';
			return `Matched to ${match.vortexGameId ?? 'an unknown Vortex game'} via ${match.confidence}; ${match.profiles.length} ${profileLabel}.`;
		}
		return match.warning ?? 'No deterministic Vortex match was found.';
	}
	if (installation !== undefined) {
		return installation.resolved
			? `Steam installation resolved via ${installation.source}; path is redacted from logs.`
			: (installation.warning ?? 'Steam installation was not resolved.');
	}
	return 'Enter an installed Steam AppID. Matching never uses a game title.';
}

export function GameMatchPanel() {
	const [appIdText, setAppIdText] = useState('');
	const [vortexGameId, setVortexGameId] = useState('');
	const [installation, setInstallation] = useState<SteamInstallationResult>();
	const [match, setMatch] = useState<VortexGameMatch>();
	const [status, setStatus] = useState<string>();
	const [busy, setBusy] = useState<BusyOperation>();

	const validAppId = parseAppId(appIdText);

	const handleError = (operation: string, error: unknown): void => {
		const message = error instanceof Error ? error.message : String(error);
		setStatus(message);
		log.error(operation, error);
	};

	const resolve = async (): Promise<void> => {
		if (validAppId === undefined) {
			setStatus('Steam AppID must be a positive 32-bit integer.');
			return;
		}
		setBusy('resolve');
		setStatus(undefined);
		setMatch(undefined);
		try {
			const result = await resolveSteamInstallation(validAppId);
			setInstallation(result);
			log.info('steam.installation.ui_result', {
				steamAppId: validAppId,
				resolved: result.resolved,
				source: result.source,
				candidateCount: result.candidateCount,
				installPathRedacted: result.installPath !== undefined,
			});
		} catch (error: unknown) {
			handleError('steam.installation.ui_failed', error);
		} finally {
			setBusy(undefined);
		}
	};

	const executeMatch = async (): Promise<void> => {
		if (validAppId === undefined) {
			setStatus('Steam AppID must be a positive 32-bit integer.');
			return;
		}
		setBusy('match');
		setStatus(undefined);
		try {
			const result = await matchVortexGame(validAppId);
			setMatch(result);
			if (result.steamInstallPath !== undefined) {
				setInstallation({
					resolved: true,
					steamAppId: result.steamAppId,
					source: result.steamSource ?? 'manifest',
					installPath: result.steamInstallPath,
				});
			}
			log.info('matching.ui_result', {
				steamAppId: validAppId,
				matched: result.matched,
				confidence: result.confidence,
				profileCount: result.profiles.length,
				steamSource: result.steamSource,
				pathsRedacted: true,
				vortexGameIdRedacted: result.vortexGameId !== undefined,
			});
		} catch (error: unknown) {
			handleError('matching.ui_failed', error);
		} finally {
			setBusy(undefined);
		}
	};

	const loadOverride = async (): Promise<void> => {
		if (validAppId === undefined) {
			setStatus('Steam AppID must be a positive 32-bit integer.');
			return;
		}
		setBusy('load-override');
		setStatus(undefined);
		try {
			const result = await getSteamAppIdOverride(validAppId);
			if (!result.ok) {
				throw new Error(result.error ?? 'The game mapping could not be loaded.');
			}
			setVortexGameId(result.vortexGameId ?? '');
			setStatus(
				result.vortexGameId
					? 'Configured Vortex game mapping loaded.'
					: 'No Vortex game mapping is configured for this AppID.',
			);
		} catch (error: unknown) {
			handleError('matching.override_load_failed', error);
		} finally {
			setBusy(undefined);
		}
	};

	const saveOverride = async (gameId: string): Promise<void> => {
		if (validAppId === undefined) {
			setStatus('Steam AppID must be a positive 32-bit integer.');
			return;
		}
		setBusy('save-override');
		setStatus(undefined);
		try {
			const result = await setSteamAppIdOverride(validAppId, gameId);
			if (!result.ok) {
				throw new Error(result.error ?? 'The game mapping could not be saved.');
			}
			setVortexGameId(result.vortexGameId ?? '');
			setMatch(undefined);
			setStatus(result.vortexGameId ? 'Game mapping saved.' : 'Game mapping cleared.');
			log.info('matching.override_ui_saved', {
				steamAppId: validAppId,
				configured: result.vortexGameId !== undefined,
				vortexGameIdRedacted: result.vortexGameId !== undefined,
			});
		} catch (error: unknown) {
			handleError('matching.override_ui_failed', error);
		} finally {
			setBusy(undefined);
		}
	};

	return (
		<>
			<Field
				label="Game matching diagnostics"
				description={resultDescription(installation, match, status)}
				childrenLayout="below"
			>
				<TextField
					value={appIdText}
					disabled={busy !== undefined}
					onChange={(event) => {
						setAppIdText(event.currentTarget.value.trim());
						setInstallation(undefined);
						setMatch(undefined);
						setStatus(undefined);
					}}
				/>
				<div style={{ display: 'flex', gap: '8px', marginTop: '8px' }}>
					<DialogButton
						disabled={busy !== undefined || validAppId === undefined}
						onClick={() => void resolve()}
					>
						{busy === 'resolve' ? 'Resolving...' : 'Resolve Steam path'}
					</DialogButton>
					<DialogButton
						disabled={busy !== undefined || validAppId === undefined}
						onClick={() => void executeMatch()}
					>
						{busy === 'match' ? 'Matching...' : 'Match Vortex game'}
					</DialogButton>
				</div>
			</Field>
			<Field
				label="Steam AppID to Vortex game-ID override"
				description="Optional exact mapping for the AppID above. An invalid configured game ID is rejected instead of falling back."
				childrenLayout="below"
				bottomSeparator="none"
			>
				<TextField
					value={vortexGameId}
					disabled={busy !== undefined}
					onChange={(event) => setVortexGameId(event.currentTarget.value)}
				/>
				<div style={{ display: 'flex', gap: '8px', marginTop: '8px' }}>
					<DialogButton
						disabled={busy !== undefined || validAppId === undefined}
						onClick={() => void loadOverride()}
					>
						{busy === 'load-override' ? 'Loading...' : 'Load mapping'}
					</DialogButton>
					<DialogButton
						disabled={
							busy !== undefined ||
							validAppId === undefined ||
							vortexGameId.trim().length === 0
						}
						onClick={() => void saveOverride(vortexGameId)}
					>
						{busy === 'save-override' ? 'Saving...' : 'Save mapping'}
					</DialogButton>
					<DialogButton
						disabled={busy !== undefined || validAppId === undefined}
						onClick={() => void saveOverride('')}
					>
						Clear mapping
					</DialogButton>
				</div>
			</Field>
		</>
	);
}
