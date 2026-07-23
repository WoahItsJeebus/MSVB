const LOG_PREFIX = '[VLB]';

export default function WebkitMain(): void {
	console.info(
		`${LOG_PREFIX} ${JSON.stringify({
			timestamp: new Date().toISOString(),
			component: 'webkit',
			level: 'info',
			event: 'webkit.loaded',
		})}`,
	);
}
