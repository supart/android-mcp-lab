export type DataPolicy = 'preserve' | 'test' | 'destructive' | 'destructive-test-allowed'

export type CredentialPolicy = 'contains-credentials' | 'no-credentials'
export type ControlMode = 'codex-exclusive' | 'manual-reuse'

export interface AndroidLabDevice {
  readonly deviceId: string
  readonly avdName: string
  readonly serial?: string
  readonly deviceSlug: string
  readonly devicePort: number
  readonly hostPort: number
  readonly emulatorPort?: number
  readonly apiLevel?: number
  readonly abi?: string
  readonly mcpPackage: string
  readonly upstreamVersion: string
  readonly apkSha256: string
  readonly certificateSha256: string
  readonly credentialPolicy: CredentialPolicy
  readonly dataPolicy: DataPolicy
  readonly mcpEnabled: boolean
  readonly controlMode?: ControlMode
  readonly reservedFor?: string
  readonly registeredAtUtc: string
  readonly lastSeenAtUtc?: string
  readonly status?: 'offline' | 'starting' | 'ready' | 'failed'
  readonly failure?: string
}

export interface AndroidLabRegistry {
  readonly schemaVersion: 1
  readonly installVersion: string
  readonly defaultDeviceId?: string
  readonly devices: readonly AndroidLabDevice[]
}

export interface AndroidLabLease {
  readonly schemaVersion: 1
  readonly leaseId: string
  readonly deviceId: string
  readonly owner: string
  readonly createdAtUtc: string
  readonly expiresAtUtc: string
}

export function assertDeviceId(value: unknown): asserts value is string {
  if (typeof value !== 'string' || !/^[a-z0-9][a-z0-9_-]{1,63}$/u.test(value)) {
    throw new Error('deviceId must use lowercase letters, digits, underscore or hyphen')
  }
}
