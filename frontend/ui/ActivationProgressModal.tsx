import { ConfirmModal } from '@steambrew/client';

import { STEAM_MODAL_CLASS_NAME, SteamModalChromeStyles } from './SteamModalChrome';

export interface ActivationProgressModalProps {
	restartingVortex?: boolean;
	onDismiss(): void;
}

export function ActivationProgressModal({
	restartingVortex = false,
	onDismiss,
}: ActivationProgressModalProps) {
	return (
		<ConfirmModal
			modalClassName={STEAM_MODAL_CLASS_NAME}
			strTitle="Activating Vortex profile"
			strDescription={
				<div style={{ display: 'flex', flexDirection: 'column', gap: '12px' }}>
					<SteamModalChromeStyles />
					<div>
						{restartingVortex
							? 'Closing all running Vortex processes, then retrying profile activation...'
							: 'Waiting for Vortex to activate the selected profile and finish deployment...'}
					</div>
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
