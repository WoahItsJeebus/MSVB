import { ConfirmModal } from '@steambrew/client';

import { STEAM_MODAL_CLASS_NAME, SteamModalChromeStyles } from './SteamModalChrome';

export interface ActivationErrorModalProps {
	message: string;
	warning?: string;
	onRetry?: () => void;
	onContinueWithSteam(): void;
	onCancel(): void;
}

export function ActivationErrorModal({
	message,
	warning,
	onRetry,
	onContinueWithSteam,
	onCancel,
}: ActivationErrorModalProps) {
	return (
		<ConfirmModal
			modalClassName={STEAM_MODAL_CLASS_NAME}
			strTitle="Vortex activation failed"
			strDescription={
				<div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
					<SteamModalChromeStyles />
					<div>{message}</div>
					{warning === undefined ? null : <div>{warning}</div>}
					{onRetry === undefined ? null : (
						<div>
							Retry closes all running Vortex processes, then starts Vortex again with
							the same profile.
						</div>
					)}
					<div>
						Continuing with Steam resumes the exact intercepted request without asking Vortex
						to make another change.
					</div>
				</div>
			}
			strOKButtonText={onRetry === undefined ? 'Continue launching with Steam...' : 'Retry'}
			strMiddleButtonText={
				onRetry === undefined ? undefined : 'Continue launching with Steam...'
			}
			strCancelButtonText="Cancel"
			bDisableBackgroundDismiss
			closeModal={() => undefined}
			onOK={onRetry ?? onContinueWithSteam}
			onMiddleButton={onRetry === undefined ? undefined : onContinueWithSteam}
			onCancel={onCancel}
			onEscKeypress={onCancel}
		/>
	);
}
