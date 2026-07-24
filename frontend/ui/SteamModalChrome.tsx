export const STEAM_MODAL_CLASS_NAME = 'VortexLaunchBridgeModal';

const STEAM_MODAL_CHROME_CSS = `
	.VortexLaunchBridgeModal .ModalPosition_Dismiss .closeButton,
	body:has(.VortexLaunchBridgeModal) .title-area-icon.closeButton,
	body:has(.VortexLaunchBridgeModal) .title-area-icon.closeButton .title-area-icon-inner {
		display: flex !important;
		align-items: center !important;
		justify-content: center !important;
	}

	.VortexLaunchBridgeModal .ModalPosition_Dismiss .closeButton,
	body:has(.VortexLaunchBridgeModal) .title-area-icon.closeButton {
		line-height: 0 !important;
	}

	.VortexLaunchBridgeModal .ModalPosition_Dismiss .closeButton .SVGIcon_X_Line,
	body:has(.VortexLaunchBridgeModal) .title-area-icon.closeButton .SVGIcon_X_Line {
		display: block !important;
		width: 16px !important;
		height: 16px !important;
		margin: 0 !important;
		position: static !important;
		transform: none !important;
	}

	.VortexLaunchBridgeModal .DialogTwoColLayout > button.DialogButton,
	.VortexLaunchBridgeModal .DialogThreeColLayout > button.DialogButton {
		box-sizing: border-box !important;
		display: flex !important;
		align-items: center !important;
		justify-content: center !important;
		height: 42px !important;
		min-height: 42px !important;
		max-height: 42px !important;
		padding-block: 0 !important;
		padding-inline: 14px !important;
		line-height: 18px !important;
		white-space: normal !important;
	}
`;

export function SteamModalChromeStyles() {
	return <style>{STEAM_MODAL_CHROME_CSS}</style>;
}
