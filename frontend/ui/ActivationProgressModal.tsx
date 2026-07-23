import { ConfirmModal } from '@steambrew/client';

import { STEAM_MODAL_CLASS_NAME, SteamModalChromeStyles } from './SteamModalChrome';

export interface ActivationProgressModalProps {
	onDismiss(): void;
}

export function ActivationProgressModal({ onDismiss }: ActivationProgressModalProps) {
	return (
		<ConfirmModal
			modalClassName={STEAM_MODAL_CLASS_NAME}
			strTitle="Activating Vortex profile"
			strDescription={
				<div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
					<SteamModalChromeStyles />
					<div>Waiting for Vortex to activate the selected profile and finish deployment...</div>
					<div>
						Cancelling stops the pending Steam launch. Vortex may continue the requested
						profile change.
					</div>
				</div>
			}
			strOKButtonText="Cancel"
			bAlertDialog
			bDisableBackgroundDismiss
			closeModal={onDismiss}
			onCancel={onDismiss}
			onOK={onDismiss}
			onEscKeypress={onDismiss}
		/>
	);
}
