import { parseVortexActivationResult } from '../frontend/vortex/VortexTypes';

function assert(condition: unknown, message: string): asserts condition {
	if (!condition) {
		throw new Error(message);
	}
}

const success = parseVortexActivationResult({
	ok: true,
	started: true,
	timedOut: false,
	timeoutMs: 30_000,
	durationMs: 1_250,
	wasVortexRunning: false,
	isVortexRunningAfter: true,
	profileActivationRequested: true,
	profileActivationConfirmed: true,
	deploymentConfirmed: true,
	readinessAvailable: true,
	readinessSignal: 'vortex-log-profile-switch',
});
assert(success.ok, 'A confirmed activation response should parse.');
assert(success.deploymentConfirmed, 'Deployment confirmation must be retained.');

const failure = parseVortexActivationResult({
	ok: false,
	started: true,
	timedOut: true,
	timeoutMs: 30_000,
	profileActivationRequested: true,
	profileActivationConfirmed: false,
	deploymentConfirmed: false,
	readinessAvailable: true,
	readinessSignal: 'vortex-log-profile-switch',
	error: 'Timed out.',
	warning: 'Vortex may still finish.',
});
assert(failure.timedOut, 'Timeout status must be retained.');
assert(failure.warning === 'Vortex may still finish.', 'The warning must be retained.');

let rejectedUnknownSignal = false;
try {
	parseVortexActivationResult({
		ok: true,
		started: true,
		timedOut: false,
		timeoutMs: 30_000,
		profileActivationRequested: true,
		profileActivationConfirmed: true,
		deploymentConfirmed: true,
		readinessSignal: 'process-started',
	});
} catch {
	rejectedUnknownSignal = true;
}
assert(rejectedUnknownSignal, 'An untrusted readiness signal must be rejected.');

console.log('Vortex activation contract tests passed');
