import { DialogButton, Field, IconsModule, TextField } from '@steambrew/client';
import { useCallback, useEffect, useState } from 'react';

import { log } from '../logging/Logger';
import {
	fullWidthControlStyle,
	insetPaddedActionButtonStyle,
	paddedActionButtonStyle,
	ResponsiveActionRow,
	ResponsiveControlGroup,
	responsiveButtonStyle,
} from '../ui/ResponsiveControls';
import {
	getVortexInstallation,
	runVortexProbe,
	setVortexExecutablePath,
} from './VortexClient';
import type { VortexInstallation, VortexProbeResult } from './VortexTypes';

type BusyOperation = 'detect' | 'save' | 'probe';

function installationDescription(installation: VortexInstallation | undefined): string {
	if (installation === undefined) {
		return 'Vortex detection has not completed.';
	}
	if (!installation.found) {
		return installation.error ?? 'Vortex was not detected.';
	}

	const source = installation.source ?? 'unknown source';
	const version = installation.version ? `, version ${installation.version}` : '';
	return `Vortex detected via ${source}${version}.`;
}

function probeDescription(probe: VortexProbeResult | undefined): string {
	if (probe === undefined) {
		return 'Runs only --version and approved --get state queries. It never uses --set or --del.';
	}

	const state = probe.stateCommand;
	const stateSummary =
		state?.executed === false
			? `state query skipped (${state.skipReason ?? 'unspecified reason'})`
			: `state format ${state?.outputFormat ?? 'unavailable'}`;
	const warningSuffix = probe.warnings.length > 0 ? ` ${probe.warnings.join(' ')}` : '';
	return `${probe.profiles.length} profiles and ${probe.discoveredGames.length} discovered games; ${stateSummary}.${warningSuffix}`;
}

export function VortexProbePanel() {
	const [installation, setInstallation] = useState<VortexInstallation>();
	const [overridePath, setOverridePath] = useState('');
	const [probe, setProbe] = useState<VortexProbeResult>();
	const [busy, setBusy] = useState<BusyOperation>();
	const [statusError, setStatusError] = useState<string>();

	const detect = useCallback(async (): Promise<void> => {
		setBusy('detect');
		setStatusError(undefined);
		try {
			const detected = await getVortexInstallation();
			setInstallation(detected);
			setOverridePath((current) => current || detected.executablePath || '');
			log.info('vortex.detection.ok', {
				found: detected.found,
				source: detected.source,
				version: detected.version,
				executablePathRedacted: detected.executablePath !== undefined,
			});
		} catch (error: unknown) {
			const message = error instanceof Error ? error.message : String(error);
			setStatusError(message);
			log.error('vortex.detection.failed', error);
		} finally {
			setBusy(undefined);
		}
	}, []);

	useEffect(() => {
		void detect();
	}, [detect]);

	const saveOverride = async (path: string): Promise<void> => {
		setBusy('save');
		setStatusError(undefined);
		try {
			const result = await setVortexExecutablePath(path);
			if (!result.ok || result.installation === undefined) {
				throw new Error(result.error ?? 'The Vortex executable override was not saved.');
			}
			setOverridePath(path);
			setInstallation(result.installation);
			setProbe(undefined);
			log.info('vortex.override.saved', {
				configured: path.length > 0,
				found: result.installation.found,
				source: result.installation.source,
				pathRedacted: path.length > 0,
			});
		} catch (error: unknown) {
			const message = error instanceof Error ? error.message : String(error);
			setStatusError(message);
			log.error('vortex.override.failed', error);
		} finally {
			setBusy(undefined);
		}
	};

	const executeProbe = async (): Promise<void> => {
		setBusy('probe');
		setStatusError(undefined);
		try {
			const result = await runVortexProbe();
			setProbe(result);
			setInstallation(result.installation);
			log.info('vortex.probe.ok', {
				ok: result.ok,
				found: result.installation.found,
				version: result.installation.version,
				profileCount: result.profiles.length,
				discoveredGameCount: result.discoveredGames.length,
				versionExitCode: result.versionCommand?.exitCode,
				versionTimedOut: result.versionCommand?.timedOut,
				stateExecuted: result.stateCommand?.executed,
				stateExitCode: result.stateCommand?.exitCode,
				stateTimedOut: result.stateCommand?.timedOut,
				stateOutputFormat: result.stateCommand?.outputFormat,
				outputRedacted: true,
			});
		} catch (error: unknown) {
			const message = error instanceof Error ? error.message : String(error);
			setStatusError(message);
			log.error('vortex.probe.failed', error);
		} finally {
			setBusy(undefined);
		}
	};

	return (
		<>
			<Field
				label="Vortex installation"
				description={statusError ?? installationDescription(installation)}
				icon={<IconsModule.Settings />}
				childrenLayout="inline"
				inlineWrap="shift-children-below"
			>
				<DialogButton
					disabled={busy !== undefined}
					onClick={() => void detect()}
					style={insetPaddedActionButtonStyle}
				>
					{busy === 'detect' ? 'Detecting...' : 'Detect Vortex'}
				</DialogButton>
			</Field>
			<Field
				label="Vortex executable override"
				description="Optional. The value is stored in the plugin settings under LocalAppData."
				childrenLayout="below"
			>
				<ResponsiveControlGroup>
					<TextField
						value={overridePath}
						disabled={busy !== undefined}
						style={fullWidthControlStyle}
						onChange={(event) => setOverridePath(event.currentTarget.value)}
					/>
					<ResponsiveActionRow>
						<DialogButton
							disabled={busy !== undefined || overridePath.length === 0}
							onClick={() => void saveOverride(overridePath)}
							style={responsiveButtonStyle}
						>
							{busy === 'save' ? 'Saving...' : 'Save override'}
						</DialogButton>
						<DialogButton
							disabled={busy !== undefined}
							onClick={() => void saveOverride('')}
							style={responsiveButtonStyle}
						>
							Clear override
						</DialogButton>
					</ResponsiveActionRow>
				</ResponsiveControlGroup>
			</Field>
			<Field
				label="Read-only Vortex backend probe"
				description={probeDescription(probe)}
				bottomSeparator="none"
				childrenLayout="inline"
				inlineWrap="shift-children-below"
			>
				<DialogButton
					disabled={busy !== undefined || installation?.found !== true}
					onClick={() => void executeProbe()}
					style={paddedActionButtonStyle}
				>
					{busy === 'probe' ? 'Probing...' : 'Run read-only probe'}
				</DialogButton>
			</Field>
		</>
	);
}
