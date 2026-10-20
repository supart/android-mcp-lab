import { spawn } from 'node:child_process'

const root = process.argv[2]
const deviceId = process.argv[3] ?? 'codex_api36'
if (!root) throw new Error('Android Lab root is required')

const launcher = `${root.replace(/[\\/]$/u, '')}/bridge/launcher.mjs`
const child = spawn(process.execPath, [launcher], {
  cwd: root,
  stdio: ['pipe', 'pipe', 'pipe'],
  windowsHide: true,
  env: { ...process.env, ANDROID_LAB_DEFAULT_DEVICE: deviceId },
})
let buffer = ''
let nextId = 1
const pending = new Map()
const diagnostics = []
let activeLease

child.on('error', error => diagnostics.push(`child error: ${String(error).slice(0, 300)}`))
child.on('exit', (code, signal) => {
  if (code !== 0 || signal) diagnostics.push(`child exit: code=${code ?? 'null'} signal=${signal ?? 'null'}`)
  for (const [id, reject] of pending) reject(new Error(`MCP bridge exited while waiting for request ${id}`))
  pending.clear()
})
child.stderr.on('data', value => {
  const text = String(value).replace(/Bearer\s+\S+/giu, 'Bearer [redacted]')
  if (text.trim()) diagnostics.push(text.trim().slice(0, 300))
})
child.stdout.on('data', value => {
  buffer += String(value)
  for (;;) {
    const index = buffer.indexOf('\n')
    if (index < 0) break
    const line = buffer.slice(0, index).trim()
    buffer = buffer.slice(index + 1)
    if (!line) continue
    try {
      const message = JSON.parse(line)
      if (typeof message.id === 'number' && pending.has(message.id)) {
        const resolve = pending.get(message.id)
        pending.delete(message.id)
        resolve(message)
      }
    } catch { /* ignore non-protocol stdout */ }
  }
})

function request(method, params = {}) {
  const id = nextId++
  child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`)
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      pending.delete(id)
      reject(new Error(`${method} timed out (diagnostics=${diagnostics.slice(0, 3).join(' | ')})`))
    }, 45_000)
    pending.set(id, message => { clearTimeout(timer); resolve(message) })
  })
}

function resultText(message) {
  if (message.error) throw new Error(String(message.error.message ?? 'MCP request failed'))
  const result = message.result ?? {}
  const content = result.content?.find(item => item.type === 'text')
  if (result.isError) throw new Error(content?.text ?? 'MCP tool failed')
  return content?.text ?? ''
}

function assertSafeAcceptanceDevice(device, label, expectedDeviceId = deviceId) {
  if (!device || device.deviceId !== expectedDeviceId) throw new Error(`${label} ${expectedDeviceId} was not listed`)
  const reasons = []
  if (device.mcpEnabled !== true) reasons.push('disabled')
  if (device.credentialPolicy !== 'no-credentials') reasons.push('credential_blocked')
  if (device.dataPolicy === 'preserve') reasons.push('preserve_only')
  if (reasons.length) throw new Error(`${label} ${expectedDeviceId} is not safe for acceptance: ${reasons.join(',')}`)
}

try {
  await request('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'android-lab-acceptance', version: '0.1.3' } })
  child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method: 'notifications/initialized', params: {} })}\n`)
  const listed = await request('tools/list')
  const tools = listed.result?.tools ?? []
  if (tools.length !== 63) throw new Error(`Expected 63 tools, received ${tools.length}`)
  const devices = JSON.parse(resultText(await request('tools/call', { name: 'android_lab_devices', arguments: {} })))
  const selectedDevice = devices.find(item => item.deviceId === deviceId)
  assertSafeAcceptanceDevice(selectedDevice, 'Acceptance device')

  const lease = JSON.parse(resultText(await request('tools/call', { name: 'android_lab_acquire', arguments: { deviceId, owner: 'android-lab-acceptance', ttlSeconds: 120 } })))
  if (!lease.leaseId) throw new Error('No lease was returned')
  activeLease = lease

  let sameDeviceConflict = false
  try {
    await request('tools/call', { name: 'android_lab_acquire', arguments: { deviceId, owner: 'android-lab-conflict', ttlSeconds: 60 } }).then(resultText)
  } catch (error) {
    sameDeviceConflict = String(error).includes('already leased')
  }
  if (!sameDeviceConflict) throw new Error('Same-device lease conflict was not rejected')

  const parallelDevice = devices.find(item => item.deviceId !== deviceId && item.mcpEnabled === true && item.credentialPolicy === 'no-credentials' && item.dataPolicy !== 'preserve')
  let parallelLease = false
  if (parallelDevice) {
    assertSafeAcceptanceDevice(parallelDevice, 'Parallel acceptance device', parallelDevice.deviceId)
    const other = JSON.parse(resultText(await request('tools/call', { name: 'android_lab_acquire', arguments: { deviceId: parallelDevice.deviceId, owner: 'android-lab-parallel', ttlSeconds: 60 } })))
    parallelLease = Boolean(other.leaseId)
    if (other.leaseId) await request('tools/call', { name: 'android_lab_release', arguments: { deviceId: parallelDevice.deviceId, leaseId: other.leaseId } })
  }

  const args = { deviceId, leaseId: lease.leaseId }
  resultText(await request('tools/call', { name: 'android_lab_open_app', arguments: { ...args, package_id: 'com.android.settings' } }))
  resultText(await request('tools/call', { name: 'android_lab_get_screen_state', arguments: { ...args, include_screenshot: true } }))
  resultText(await request('tools/call', { name: 'android_lab_press_back', arguments: args }))
  await request('tools/call', { name: 'android_lab_release', arguments: { deviceId, leaseId: lease.leaseId } })
  activeLease = undefined
  console.log(JSON.stringify({ status: 'passed', toolCount: tools.length, deviceId, openApp: 'passed', screenshot: 'passed', pressBack: 'passed', sameDeviceConflict, parallelLease, lease: 'released' }))
} finally {
  if (activeLease?.leaseId) {
    try { await request('tools/call', { name: 'android_lab_release', arguments: { deviceId, leaseId: activeLease.leaseId } }) } catch { /* lease expires */ }
  }
  child.kill()
}
