type LogLevel = 'debug' | 'info' | 'warn' | 'error';
type LogFields = Readonly<Record<string, unknown>>;
export interface FrontendLogRecord {
	timestamp: string;
	component: 'frontend';
	level: LogLevel;
	event: string;
	fields: LogFields;
}

const LOG_PREFIX = '[VLB]';
let diagnosticLoggingEnabled = false;
let backendLogSink: ((record: FrontendLogRecord) => void) | undefined;

export function setBackendLogSink(
	sink: ((record: FrontendLogRecord) => void) | undefined,
): void {
	backendLogSink = sink;
}

function emit(level: LogLevel, event: string, fields: LogFields = {}): void {
	if (level === 'debug' && !diagnosticLoggingEnabled) {
		return;
	}
	const record = {
		timestamp: new Date().toISOString(),
		component: 'frontend',
		level,
		event,
		fields,
	} satisfies FrontendLogRecord;
	const message = `${LOG_PREFIX} ${JSON.stringify({
		timestamp: record.timestamp,
		component: record.component,
		level: record.level,
		event: record.event,
		...record.fields,
	})}`;

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

	backendLogSink?.(record);
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
