import { Client } from '@modelcontextprotocol/sdk/client/index.js'
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js'

const deviceId = process.env.ANDROID_LAB_SMOKE_DEVICE
if (!deviceId) {
  console.log(JSON.stringify({ status: 'skipped', reason: 'Set ANDROID_LAB_SMOKE_DEVICE to run the live bridge smoke.' }))
  process.exit(0)
}
const transport = new StdioClientTransport({
  command: process.execPath,
  args: ['bridge/launcher.mjs'],
  env: { ...process.env, ANDROID_LAB_DEFAULT_DEVICE: deviceId },
  cwd: process.cwd(),
})
const client = new Client({ name: 'android-lab-smoke', version: '0.1.3' }, { capabilities: {} })
await client.connect(transport)
const listed = await client.listTools()
const names = listed.tools.map(tool => tool.name)
if (!names.includes('android_lab_devices') || !names.includes('android_lab_get_screen_state')) throw new Error('Generic Android Lab tools are missing')
const devices = await client.callTool({ name: 'android_lab_devices', arguments: {} })
const text = devices.content?.find(item => item.type === 'text')?.text ?? ''
const registered = JSON.parse(text)
const selected = Array.isArray(registered) ? registered.find(device => device.deviceId === deviceId) : undefined
if (!selected) throw new Error(`Smoke device is not registered: ${deviceId}`)
if (selected.mcpEnabled !== true || selected.credentialPolicy !== 'no-credentials' || selected.dataPolicy === 'preserve') {
  throw new Error(`Smoke device is not safe for acceptance: ${deviceId}`)
}
const lease = await client.callTool({ name: 'android_lab_acquire', arguments: { deviceId, owner: 'bridge-smoke', ttlSeconds: 60 } })
const leaseText = lease.content?.find(item => item.type === 'text')?.text ?? ''
const leaseValue = JSON.parse(leaseText)
if (!leaseValue.leaseId) throw new Error('Lease was not created')
const screen = await client.callTool({ name: 'android_lab_get_screen_state', arguments: { deviceId, leaseId: leaseValue.leaseId } })
if (!screen.content?.length) throw new Error('Screen state call returned no content')
await client.callTool({ name: 'android_lab_release', arguments: { deviceId, leaseId: leaseValue.leaseId } })
console.log(JSON.stringify({ toolCount: names.length, hasGenericTools: true, deviceId, routedCall: 'get-screen-state-passed', lease: 'acquire-release-passed' }))
await client.close()
