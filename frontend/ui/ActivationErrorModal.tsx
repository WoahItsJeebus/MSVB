import { ConfirmModal } from '@steambrew/client';

import { STEAM_MODAL_CLASS_NAME, SteamModalChromeStyles } from './SteamModalChrome';

export interface ActivationErrorModalProps {
	message: string;
	warning?: string;
	onContinueWithSteam(): void;
	onCancel(): void;
}

export function ActivationErrorModal({
	message,
	warning,
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
					<div>
						Continuing with Steam resumes the exact intercepted request without asking Vortex
						to make another change.
					</div>
				</div>
			}
			strOKButtonText="Continue launching with Steam..."
			strCancelButtonText="Cancel"
			bDisableBackgroundDismiss
			closeModal={onCancel}
			onOK={onContinueWithSteam}
			onCancel={onCancel}
			onEscKeypress={onCancel}
		/>
	);
}
