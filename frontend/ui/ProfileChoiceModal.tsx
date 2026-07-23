import {
	DialogBodyText,
	DialogButton,
	DialogControlsSection,
	DialogHeader,
	ModalRoot,
} from '@steambrew/client';

import type { VortexProfile } from '../vortex/VortexTypes';
import { STEAM_MODAL_CLASS_NAME, SteamModalChromeStyles } from './SteamModalChrome';

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
			modalClassName={STEAM_MODAL_CLASS_NAME}
			bDisableBackgroundDismiss
			closeModal={onDismiss}
			onCancel={onDismiss}
			onEscKeypress={onDismiss}
		>
			<SteamModalChromeStyles />
			<DialogHeader>Select a Vortex profile</DialogHeader>
			<DialogBodyText>
				Select the profile to activate before the configured launch target starts.
			</DialogBodyText>
			<DialogControlsSection>
				<div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
					{profiles.map((profile) => (
						<DialogButton key={profile.id} onClick={() => onSelect(profile)}>
							{profile.name}
							{profileDetails(profile)}
						</DialogButton>
					))}
				</div>
				<div style={{ display: 'flex', justifyContent: 'flex-end', marginTop: '12px' }}>
					<DialogButton onClick={onDismiss}>Cancel</DialogButton>
				</div>
			</DialogControlsSection>
		</ModalRoot>
	);
}
