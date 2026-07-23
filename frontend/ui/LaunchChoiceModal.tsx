import { ConfirmModal } from '@steambrew/client';

import { STEAM_MODAL_CLASS_NAME, SteamModalChromeStyles } from './SteamModalChrome';

export interface LaunchChoiceModalProps {
	appName: string;
	steamAppId: number;
	profileCount: number;
	onLaunchWithVortex(): void;
	onContinueWithSteam(): void;
	onCancel(): void;
}

export function LaunchChoiceModal({
	appName,
	steamAppId,
	profileCount,
	onLaunchWithVortex,
	onContinueWithSteam,
	onCancel,
}: LaunchChoiceModalProps) {
	const profileLabel = profileCount === 1 ? 'profile' : 'profiles';

	return (
		<ConfirmModal
			modalClassName={STEAM_MODAL_CLASS_NAME}
			strTitle="Vortex Launch Bridge"
			strDescription={
				<div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
					<SteamModalChromeStyles />
					<div>
						Vortex manages {appName} with {profileCount} available {profileLabel}.
					</div>
					<div>
						Continuing with Steam resumes the exact intercepted Steam request. It does not
						change anything Vortex may already have deployed.
					</div>
					<div>
						Launching with Vortex activates a selected profile, waits for Vortex to confirm
						its deployment work, then starts this game&apos;s configured launch target.
					</div>
					<div
						style={{
							display: 'flex',
							flexWrap: 'wrap',
							gap: '4px 16px',
							marginTop: '4px',
							paddingTop: '10px',
							borderTop: '1px solid currentColor',
							fontSize: '13px',
							opacity: 0.7,
						}}
					>
						<span>Platform: Steam</span>
						<span>AppID: {steamAppId}</span>
					</div>
				</div>
			}
			strOKButtonText="Launch with Vortex"
			strMiddleButtonText="Continue launching with Steam..."
			strCancelButtonText="Cancel"
			bDisableBackgroundDismiss
			// The parent owns the ShowModal handle and every action closes or
			// replaces it. A no-op prevents ConfirmModal's trailing close call
			// from reclassifying the primary or middle action as cancellation.
			closeModal={() => undefined}
			onOK={onLaunchWithVortex}
			onMiddleButton={onContinueWithSteam}
			onCancel={onCancel}
		/>
	);
}
