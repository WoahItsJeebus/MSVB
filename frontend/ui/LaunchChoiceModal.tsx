import { DialogButton, ModalRoot } from '@steambrew/client';

export interface LaunchChoiceModalProps {
	steamAppId: number;
	profileCount: number;
	onLaunchWithVortex(): void;
	onContinueWithSteam(): void;
	onDismiss(): void;
}

export function LaunchChoiceModal({
	steamAppId,
	profileCount,
	onLaunchWithVortex,
	onContinueWithSteam,
	onDismiss,
}: LaunchChoiceModalProps) {
	const profileLabel = profileCount === 1 ? 'profile' : 'profiles';

	return (
		<ModalRoot
			bDisableBackgroundDismiss
			closeModal={onDismiss}
			onCancel={onDismiss}
			onEscKeypress={onDismiss}
		>
			<div style={{ display: 'flex', flexDirection: 'column', gap: '12px', maxWidth: '560px' }}>
				<div>
					Vortex manages Steam AppID {steamAppId} with {profileCount} available {profileLabel}.
				</div>
				<div>
					Continuing with Steam resumes the exact intercepted Steam request. It does not change
					anything Vortex may already have deployed.
				</div>
				<div>
					Launching with Vortex activates a selected profile, waits for Vortex to confirm its
					deployment work, then resumes this Steam launch.
				</div>
				<div style={{ display: 'flex', gap: '8px', justifyContent: 'flex-end' }}>
					<DialogButton onClick={onLaunchWithVortex}>Launch with Vortex</DialogButton>
					<DialogButton onClick={onContinueWithSteam}>Continue launching with Steam...</DialogButton>
				</div>
			</div>
		</ModalRoot>
	);
}
