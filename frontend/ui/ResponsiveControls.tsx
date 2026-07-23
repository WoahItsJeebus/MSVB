import type { CSSProperties, ReactNode } from 'react';

const controlGroupStyle: CSSProperties = {
	display: 'flex',
	flexDirection: 'column',
	gap: '8px',
	minWidth: 0,
	width: '100%',
};

const actionRowStyle: CSSProperties = {
	display: 'flex',
	flexWrap: 'wrap',
	gap: '8px',
	minWidth: 0,
	width: '100%',
};

export const fullWidthControlStyle: CSSProperties = {
	boxSizing: 'border-box',
	minWidth: 0,
	width: '100%',
};

export const responsiveButtonStyle: CSSProperties = {
	flex: '1 1 160px',
	minWidth: 0,
};

interface ResponsiveControlsProps {
	children: ReactNode;
}

export function ResponsiveControlGroup({ children }: ResponsiveControlsProps) {
	return <div style={controlGroupStyle}>{children}</div>;
}

export function ResponsiveActionRow({ children }: ResponsiveControlsProps) {
	return <div style={actionRowStyle}>{children}</div>;
}
