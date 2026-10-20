import { promises as fs } from 'node:fs'
import path from 'node:path'
import { Client } from '@modelcontextprotocol/sdk/client/index.js'
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js'

const localRoot = path.join(process.env.LOCALAPPDATA, 'WhiteCodex', 'AndroidMcpLab')
const leaseDir = path.join(localRoot, 'leases')
const deviceId = process.env.ANDROID_LAB_LEASE_SMOKE_DEVICE
if (!deviceId) {
  console.log(JSON.stringify({ status: 'skipped', reason: 'Set ANDROID_LAB_LEASE_SMOKE_DEVICE to run the live lease smoke.' }))
  process.exit(0)
}
const transport = new StdioClientTransport({ command: process.execPath, args: ['bridge/launcher.mjs'], cwd: process.cwd(), env: { ...process.env, ANDROID_LAB_DEFAULT_DEVICE: deviceId } })
const client = new Client({ name: 'android-lab-lease-smoke', version: '0.1.3' }, { capabilities: {} })
await client.connect(transport)
const call = async (name, args) => await client.callTool({ name, arguments: args })
const textOf = value => value.content?.find(item => item.type === 'text')?.text ?? ''
const errorText = async (promise) => {
  try { await promise; return '' } catch (error) { return String(error) }
}

const devices = JSON.parse(textOf(await call('android_lab_devices', {})))
const selected = Array.isArray(devices) ? devices.find(device => device.deviceId === deviceId) : undefined
if (!selected) throw new Error(`Lease smoke device is not registered: ${deviceId}`)
if (selected.mcpEnabled !== true || selected.credentialPolicy !== 'no-credentials' || selected.dataPolicy === 'preserve') {
  throw new Error(`Lease smoke device is not safe for acceptance: ${deviceId}`)
}
const primary = JSON.parse(textOf(await call('android_lab_acquire', { deviceId, owner: 'lease-smoke-primary', ttlSeconds: 60 })))
if (!primary.leaseId) throw new Error('Primary lease was not created')
const conflict = await errorText(call('android_lab_acquire', { deviceId, owner: 'lease-smoke-conflict', ttlSeconds: 60 }))
if (!conflict.includes('already leased')) throw new Error(`Same-device conflict was not rejected: ${conflict}`)
const noLease = await errorText(call('android_lab_tap', { deviceId, x: 1, y: 1 }))
if (!noLease.includes('valid lease')) throw new Error(`Mutating call without lease was not rejected: ${noLease}`)
const unknown = await errorText(call('android_lab_get_screen_state', { deviceId: 'not_registered' }))
if (!unknown.includes('Unknown or disabled')) throw new Error(`Unknown device was not rejected: ${unknown}`)
await call('android_lab_release', { deviceId, leaseId: primary.leaseId })

await fs.mkdir(leaseDir, { recursive: true })
await fs.writeFile(path.join(leaseDir, `${deviceId}.json`), JSON.stringify({ schemaVersion: 1, leaseId: 'expired', deviceId, owner: 'expired-fixture', createdAtUtc: '2020-01-01T00:00:00.000Z', expiresAtUtc: '2020-01-01T00:00:01.000Z' }), 'utf8')
const reclaimed = JSON.parse(textOf(await call('android_lab_acquire', { deviceId, owner: 'lease-smoke-reclaimed', ttlSeconds: 60 })))
if (!reclaimed.leaseId || reclaimed.leaseId === 'expired') throw new Error('Expired lease was not reclaimed')
await call('android_lab_release', { deviceId, leaseId: reclaimed.leaseId })
console.log(JSON.stringify({ sameDeviceConflict: true, expiredLeaseReclaimed: true, noLeaseWriteBlocked: true, unknownDeviceBlocked: true }))
await client.close()
