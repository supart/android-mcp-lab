export type SessionState = 'fresh' | 'recovered' | 'invalidated' | 'not_started'

export function isRecoverableMcpSessionError(value: unknown): boolean {
  return /invalid\s+or\s+missing\s+mcp\s+session|session\s+not\s+found|streamable\s+http\s+error|transport\s+closed|status\s*404/iu.test(String(value))
}

export async function callWithSessionRecovery<T>(
  call: () => Promise<T>,
  reconnect: () => Promise<void>,
  allowRetry: boolean,
): Promise<T> {
  try {
    return await call()
  } catch (error) {
    if (!isRecoverableMcpSessionError(error)) throw error
    if (!allowRetry) throw new Error('session_recovery_required: side-effecting operation was not retried after session invalidation')
    await reconnect()
    try {
      return await call()
    } catch (retryError) {
      if (isRecoverableMcpSessionError(retryError)) throw new Error('session_recovery_required: broker session could not be rebuilt')
      throw retryError
    }
  }
}

export interface TrackedLease {
  readonly deviceId: string
  readonly leaseId: string
}

export class LeaseTracker {
  private readonly leases = new Map<string, TrackedLease>()

  track(lease: TrackedLease): void { this.leases.set(lease.deviceId, lease) }
  forget(deviceId: string): void { this.leases.delete(deviceId) }
  values(): readonly TrackedLease[] { return [...this.leases.values()] }

  async releaseAll(release: (lease: TrackedLease) => Promise<void>): Promise<readonly string[]> {
    const failures: string[] = []
    for (const lease of this.values()) {
      try { await release(lease) } catch (error) { failures.push(`${lease.deviceId}: ${String(error).slice(0, 240)}`) }
      this.forget(lease.deviceId)
    }
    return failures
  }
}
