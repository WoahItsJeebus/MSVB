import { DialogButton, ModalRoot } from '@steambrew/client';

export interface ActivationProgressModalProps {
	onDismiss(): void;
}

export function ActivationProgressModal({ onDismiss }: ActivationProgressModalProps) {
	return (
		<ModalRoot
			bDisableBackgroundDismiss
			closeModal={onDismiss}
			onCancel={onDismiss}
			onEscKeypress={onDismiss}
		>
			<div style={{ display: 'flex', flexDirection: 'column', gap: '12px', maxWidth: '560px' }}>
				<div>Waiting for Vortex to activate the selected profile and finish deployment...</div>
				<div>
					Cancelling stops the pending Steam launch. Vortex may continue the requested profile
					change.
				</div>
				<div style={{ display: 'flex', justifyContent: 'flex-end' }}>
					<DialogButton onClick={onDismiss}>Cancel</DialogButton>
				</div>
			</div>
		</ModalRoot>
	);
}
