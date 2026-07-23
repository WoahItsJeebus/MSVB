type LogLevel = 'debug' | 'info' | 'warn' | 'error';
type LogFields = Readonly<Record<string, unknown>>;

const LOG_PREFIX = '[VLB]';
let diagnosticLoggingEnabled = false;

function emit(level: LogLevel, event: string, fields: LogFields = {}): void {
	if (level === 'debug' && !diagnosticLoggingEnabled) {
		return;
	}
	const record = {
		timestamp: new Date().toISOString(),
		component: 'frontend',
		level,
		event,
		...fields,
	};
	const message = `${LOG_PREFIX} ${JSON.stringify(record)}`;

	switch (level) {
		case 'debug':
			console.debug(message);
			break;
		case 'info':
			console.info(message);
			break;
		case 'warn':
			console.warn(message);
			break;
		case 'error':
			console.error(message);
			break;
	}
}

export function setDiagnosticLogging(enabled: boolean): void {
	diagnosticLoggingEnabled = enabled;
}

function errorMessage(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

export const log = {
	debug(event: string, fields?: LogFields): void {
		emit('debug', event, fields);
	},
	info(event: string, fields?: LogFields): void {
		emit('info', event, fields);
	},
	warn(event: string, fields?: LogFields): void {
		emit('warn', event, fields);
	},
	error(event: string, error: unknown, fields: LogFields = {}): void {
		emit('error', event, { ...fields, error: errorMessage(error) });
	},
};
