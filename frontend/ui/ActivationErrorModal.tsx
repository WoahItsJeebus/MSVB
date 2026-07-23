import { DialogButton, ModalRoot } from '@steambrew/client';

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
		<ModalRoot
			bDisableBackgroundDismiss
			closeModal={onCancel}
			onCancel={onCancel}
			onEscKeypress={onCancel}
		>
			<div style={{ display: 'flex', flexDirection: 'column', gap: '12px', maxWidth: '560px' }}>
				<div>{message}</div>
				{warning === undefined ? null : <div>{warning}</div>}
				<div>
					Continuing with Steam resumes the exact intercepted request without asking Vortex to
					make another change.
				</div>
				<div style={{ display: 'flex', gap: '8px', justifyContent: 'flex-end' }}>
					<DialogButton onClick={onContinueWithSteam}>
						Continue launching with Steam...
					</DialogButton>
					<DialogButton onClick={onCancel}>Cancel</DialogButton>
				</div>
			</div>
		</ModalRoot>
	);
}
