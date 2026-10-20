export function isRecoverableMcpSessionError(value) {
    return /invalid\s+or\s+missing\s+mcp\s+session|session\s+not\s+found|streamable\s+http\s+error|transport\s+closed|status\s*404/iu.test(String(value));
}
export async function callWithSessionRecovery(call, reconnect, allowRetry) {
    try {
        return await call();
    }
    catch (error) {
        if (!isRecoverableMcpSessionError(error))
            throw error;
        if (!allowRetry)
            throw new Error('session_recovery_required: side-effecting operation was not retried after session invalidation');
        await reconnect();
        try {
            return await call();
        }
        catch (retryError) {
            if (isRecoverableMcpSessionError(retryError))
                throw new Error('session_recovery_required: broker session could not be rebuilt');
            throw retryError;
        }
    }
}
export class LeaseTracker {
    leases = new Map();
    track(lease) { this.leases.set(lease.deviceId, lease); }
    forget(deviceId) { this.leases.delete(deviceId); }
    values() { return [...this.leases.values()]; }
    async releaseAll(release) {
        const failures = [];
        for (const lease of this.values()) {
            try {
                await release(lease);
            }
            catch (error) {
                failures.push(`${lease.deviceId}: ${String(error).slice(0, 240)}`);
            }
            this.forget(lease.deviceId);
        }
        return failures;
    }
}
