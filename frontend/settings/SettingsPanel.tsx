import { DialogButton, Field, TextField, ToggleField } from '@steambrew/client';
import { useCallback, useEffect, useState } from 'react';

import { log, setDiagnosticLogging } from '../logging/Logger';
import {
	fullWidthControlStyle,
	ResponsiveActionRow,
	ResponsiveControlGroup,
	responsiveButtonStyle,
} from '../ui/ResponsiveControls';
import {
	clearRememberedChoices,
	getGameLaunchSettings,
	getPluginSettings,
	setGameLaunchSettings,
	updatePluginSettings,
} from './SettingsClient';
import type { GameLaunchSettings, PluginSettings } from './SettingsTypes';

type BusyOperation = 'load-general' | 'save-general' | 'clear' | 'load-game' | 'save-game';

function parseAppId(value: string): number | undefined {
	if (!/^[1-9]\d*$/.test(value)) {
		return undefined;
	}
	const appId = Number(value);
	return Number.isSafeInteger(appId) && appId <= 4_294_967_295 ? appId : undefined;
}

function errorText(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

export function SettingsPanel() {
	const [general, setGeneral] = useState<PluginSettings>();
	const [timeoutSeconds, setTimeoutSeconds] = useState('30');
	const [appIdText, setAppIdText] = useState('');
	const [game, setGame] = useState<GameLaunchSettings>();
	const [busy, setBusy] = useState<BusyOperation>();
	const [generalStatus, setGeneralStatus] = useState<string>();
	const [gameStatus, setGameStatus] = useState<string>();
	const appId = parseAppId(appIdText);

	const loadGeneral = useCallback(async (): Promise<void> => {
		setBusy('load-general');
		setGeneralStatus(undefined);
		try {
			const loaded = await getPluginSettings();
			setGeneral(loaded);
			setTimeoutSeconds(String(loaded.vortexActivationTimeoutMs / 1_000));
			setDiagnosticLogging(loaded.diagnosticLogging);
		} catch (error: unknown) {
			setGeneralStatus(errorText(error));
			log.error('settings.general.load_failed', error);
		} finally {
			setBusy(undefined);
		}
	}, []);

	useEffect(() => {
		void loadGeneral();
	}, [loadGeneral]);

	const saveGeneral = async (): Promise<void> => {
		if (general === undefined) {
			return;
		}
		const seconds = Number(timeoutSeconds);
		if (!Number.isInteger(seconds) || seconds < 1 || seconds > 300) {
			setGeneralStatus('Vortex activation timeout must be a whole number from 1 to 300 seconds.');
			return;
		}

		setBusy('save-general');
		setGeneralStatus(undefined);
		try {
			const saved = await updatePluginSettings({
				...general,
				vortexActivationTimeoutMs: seconds * 1_000,
			});
			setGeneral(saved);
			setTimeoutSeconds(String(saved.vortexActivationTimeoutMs / 1_000));
			setDiagnosticLogging(saved.diagnosticLogging);
			setGeneralStatus('General launch settings saved.');
		} catch (error: unknown) {
			setGeneralStatus(errorText(error));
			log.error('settings.general.save_failed', error);
		} finally {
			setBusy(undefined);
		}
	};

	const clearChoices = async (): Promise<void> => {
		setBusy('clear');
		setGeneralStatus(undefined);
		try {
			await clearRememberedChoices();
			setGame((current) =>
				current === undefined
					? current
					: { ...current, rememberedChoice: undefined },
			);
			setGeneralStatus('Remembered launch choices cleared.');
		} catch (error: unknown) {
			setGeneralStatus(errorText(error));
			log.error('settings.remembered_choices.clear_failed', error);
		} finally {
			setBusy(undefined);
		}
	};

	const loadGame = async (): Promise<void> => {
		if (appId === undefined) {
			setGameStatus('Steam AppID must be a positive 32-bit integer.');
			return;
		}
		setBusy('load-game');
		setGameStatus(undefined);
		try {
			const loaded = await getGameLaunchSettings(appId);
			setGame(loaded);
			setGameStatus(
				loaded.rememberedChoice === undefined
					? 'Per-game launch settings loaded; no launch choice is remembered.'
					: `Per-game launch settings loaded; ${loaded.rememberedChoice} is remembered.`,
			);
		} catch (error: unknown) {
			setGameStatus(errorText(error));
			log.error('settings.game.load_failed', error, { steamAppId: appId });
		} finally {
			setBusy(undefined);
		}
	};

	const saveGame = async (): Promise<void> => {
		if (appId === undefined || game === undefined || game.steamAppId !== appId) {
			setGameStatus('Load per-game settings for this Steam AppID before saving.');
			return;
		}
		setBusy('save-game');
		setGameStatus(undefined);
		try {
			const saved = await setGameLaunchSettings(game);
			setGame(saved);
			setGameStatus('Per-game launch settings saved.');
			log.info('settings.game.ui_saved', {
				steamAppId: appId,
				preferredLaunchTarget: saved.preferredLaunchTarget,
				preferredProfileConfigured: saved.preferredProfileId !== undefined,
				customExecutableRedacted: saved.customExecutable !== undefined,
				customArgumentsRedacted: saved.customArguments.length > 0,
			});
		} catch (error: unknown) {
			setGameStatus(errorText(error));
			log.error('settings.game.ui_save_failed', error, { steamAppId: appId });
		} finally {
			setBusy(undefined);
		}
	};

	return (
		<>
			<ToggleField
				label="Always ask before an eligible launch"
				description="Enabled by default. Remembered choices never bypass the launch modal while this is on."
				checked={general?.alwaysAsk ?? true}
				disabled={general === undefined || busy !== undefined}
				onChange={(checked) =>
					setGeneral((current) => (current === undefined ? current : { ...current, alwaysAsk: checked }))
				}
			/>
			<ToggleField
				label="Remember launch choices per game"
				description="Opt in to saving Steam/Vortex decisions and the selected Vortex profile."
				checked={general?.rememberChoicePerGame ?? false}
				disabled={general === undefined || busy !== undefined}
				onChange={(checked) =>
					setGeneral((current) =>
						current === undefined ? current : { ...current, rememberChoicePerGame: checked },
					)
				}
			/>
			<ToggleField
				label="Enable diagnostic launch logging"
				description="Records detailed Steam callback observations. Paths and launch arguments remain redacted."
				checked={general?.diagnosticLogging ?? false}
				disabled={general === undefined || busy !== undefined}
				onChange={(checked) =>
					setGeneral((current) =>
						current === undefined ? current : { ...current, diagnosticLogging: checked },
					)
				}
			/>
			<Field
				label="Vortex activation timeout (seconds)"
				description={generalStatus ?? 'Allowed range: 1 to 300 seconds.'}
				childrenLayout="below"
			>
				<ResponsiveControlGroup>
					<TextField
						value={timeoutSeconds}
						disabled={general === undefined || busy !== undefined}
						mustBeNumeric
						style={fullWidthControlStyle}
						onChange={(event) => setTimeoutSeconds(event.currentTarget.value.trim())}
					/>
					<ResponsiveActionRow>
						<DialogButton
							disabled={general === undefined || busy !== undefined}
							onClick={() => void saveGeneral()}
							style={responsiveButtonStyle}
						>
							{busy === 'save-general' ? 'Saving...' : 'Save general settings'}
						</DialogButton>
						<DialogButton
							disabled={busy !== undefined}
							onClick={() => void clearChoices()}
							style={responsiveButtonStyle}
						>
							{busy === 'clear' ? 'Clearing...' : 'Clear remembered choices'}
						</DialogButton>
					</ResponsiveActionRow>
				</ResponsiveControlGroup>
			</Field>
			<Field
				label="Per-game profile and launch tool"
				description={
					gameStatus ??
					"Enter a Steam AppID, then load its settings. Profile IDs must match Vortex's stable profile ID exactly."
				}
				childrenLayout="below"
			>
				<ResponsiveControlGroup>
					<TextField
						value={appIdText}
						disabled={busy !== undefined}
						style={fullWidthControlStyle}
						onChange={(event) => {
							setAppIdText(event.currentTarget.value.trim());
							setGame(undefined);
							setGameStatus(undefined);
						}}
					/>
					<ResponsiveActionRow>
						<DialogButton
							disabled={busy !== undefined || appId === undefined}
							onClick={() => void loadGame()}
						>
							{busy === 'load-game' ? 'Loading...' : 'Load per-game settings'}
						</DialogButton>
					</ResponsiveActionRow>
				</ResponsiveControlGroup>
			</Field>
			{game === undefined ? null : (
				<>
					<Field label="Preferred Vortex profile ID" childrenLayout="below">
						<TextField
							value={game.preferredProfileId ?? ''}
							disabled={busy !== undefined}
							style={fullWidthControlStyle}
							onChange={(event) =>
								setGame((current) =>
									current === undefined
										? current
										: { ...current, preferredProfileId: event.currentTarget.value },
								)
							}
						/>
					</Field>
					<ToggleField
						label="Use a custom executable after Vortex activation"
						description="Off replays the exact preserved Steam request. On starts the configured executable directly."
						checked={game.preferredLaunchTarget === 'custom'}
						disabled={busy !== undefined}
						onChange={(checked) =>
							setGame((current) =>
								current === undefined
									? current
									: { ...current, preferredLaunchTarget: checked ? 'custom' : 'steam' },
							)
						}
					/>
					<Field label="Custom executable (.exe)" childrenLayout="below">
						<TextField
							value={game.customExecutable ?? ''}
							disabled={busy !== undefined}
							style={fullWidthControlStyle}
							onChange={(event) =>
								setGame((current) =>
									current === undefined
										? current
										: { ...current, customExecutable: event.currentTarget.value },
								)
							}
						/>
					</Field>
					<Field
						label="Custom arguments"
						description="Arguments are parsed without a command shell; paths and values containing spaces can be quoted."
						childrenLayout="below"
						bottomSeparator="none"
					>
						<ResponsiveControlGroup>
							<TextField
								value={game.customArguments}
								disabled={busy !== undefined}
								style={fullWidthControlStyle}
								onChange={(event) =>
									setGame((current) =>
										current === undefined
											? current
											: { ...current, customArguments: event.currentTarget.value },
									)
								}
							/>
							<ResponsiveActionRow>
								<DialogButton
									disabled={busy !== undefined}
									onClick={() => void saveGame()}
								>
									{busy === 'save-game' ? 'Saving...' : 'Save per-game settings'}
								</DialogButton>
							</ResponsiveActionRow>
						</ResponsiveControlGroup>
					</Field>
				</>
			)}
		</>
	);
}
