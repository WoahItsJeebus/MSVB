export interface DiagnosticText {
	value: string;
	redacted: boolean;
	length: number;
}

export interface SensitiveTextSummary {
	present: boolean;
	redacted: true;
	length: number;
}

const SAFE_DIAGNOSTIC_TOKEN = /^[A-Za-z0-9_.:-]{1,80}$/;
const NUMERIC_IDENTIFIER = /^\d{1,20}$/;
const SENSITIVE_TOKEN_HINT = /(auth|credential|key|pass(word|wd)?|secret|token)/i;

export function describeDiagnosticToken(value: string): DiagnosticText {
	if (SAFE_DIAGNOSTIC_TOKEN.test(value) && !SENSITIVE_TOKEN_HINT.test(value)) {
		return {
			value,
			redacted: false,
			length: value.length,
		};
	}

	return {
		value: value.length === 0 ? '<empty>' : '<redacted>',
		redacted: value.length > 0,
		length: value.length,
	};
}

export function describeNumericIdentifier(value: string): DiagnosticText {
	if (NUMERIC_IDENTIFIER.test(value)) {
		return {
			value,
			redacted: false,
			length: value.length,
		};
	}

	return {
		value: value.length === 0 ? '<empty>' : '<redacted:non-numeric>',
		redacted: value.length > 0,
		length: value.length,
	};
}

export function summarizeSensitiveText(value: string): SensitiveTextSummary {
	return {
		present: value.length > 0,
		redacted: true,
		length: value.length,
	};
}

export function fingerprintForDedupe(value: string): string {
	let hash = 0x811c9dc5;

	for (let index = 0; index < value.length; index += 1) {
		hash ^= value.charCodeAt(index);
		hash = Math.imul(hash, 0x01000193);
	}

	return (hash >>> 0).toString(16).padStart(8, '0');
}
