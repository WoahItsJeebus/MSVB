import { DialogButton, ModalRoot } from '@steambrew/client';

import type { VortexProfile } from '../vortex/VortexTypes';

export interface ProfileChoiceModalProps {
	profiles: VortexProfile[];
	onSelect(profile: VortexProfile): void;
	onDismiss(): void;
}

function profileDetails(profile: VortexProfile): string {
	const details: string[] = [];
	if (profile.isLastActive === true) {
		details.push('last active');
	}
	if (profile.enabledModCount !== undefined) {
		const modLabel = profile.enabledModCount === 1 ? 'enabled mod' : 'enabled mods';
		details.push(`${profile.enabledModCount} ${modLabel}`);
	}
	return details.length > 0 ? ` (${details.join(', ')})` : '';
}

export function ProfileChoiceModal({
	profiles,
	onSelect,
	onDismiss,
}: ProfileChoiceModalProps) {
	return (
		<ModalRoot
			bDisableBackgroundDismiss
			closeModal={onDismiss}
			onCancel={onDismiss}
			onEscKeypress={onDismiss}
		>
			<div style={{ display: 'flex', flexDirection: 'column', gap: '12px', maxWidth: '560px' }}>
				<div>Select the Vortex profile to activate before the configured launch target starts.</div>
				<div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
					{profiles.map((profile) => (
						<DialogButton key={profile.id} onClick={() => onSelect(profile)}>
							{profile.name}
							{profileDetails(profile)}
						</DialogButton>
					))}
				</div>
				<div style={{ display: 'flex', justifyContent: 'flex-end' }}>
					<DialogButton onClick={onDismiss}>Cancel</DialogButton>
				</div>
			</div>
		</ModalRoot>
	);
}
