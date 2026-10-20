import { Client } from '@modelcontextprotocol/sdk/client/index.js'
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js'

const deviceId = process.env.ANDROID_LAB_READONLY_DEVICE
if (!deviceId) {
  console.log(JSON.stringify({ status: 'skipped', reason: 'Set ANDROID_LAB_READONLY_DEVICE to run the live read-only smoke.' }))
  process.exit(0)
}
const transport = new StdioClientTransport({
  command: process.execPath,
  args: ['bridge/launcher.mjs'],
  cwd: process.cwd(),
  env: { ...process.env },
})
const client = new Client({ name: 'android-lab-readonly-smoke', version: '0.1.3' }, { capabilities: {} })
await client.connect(transport)
const list = await client.listTools()
if (!list.tools.some(tool => tool.name === 'android_lab_get_screen_state')) throw new Error('Generic screen-state tool is missing')
const devicesResult = await client.callTool({ name: 'android_lab_devices', arguments: {} })
const devicesText = devicesResult.content?.find(item => item.type === 'text')?.text ?? ''
const devices = JSON.parse(devicesText)
const selected = Array.isArray(devices) ? devices.find(device => device.deviceId === deviceId) : undefined
if (!selected) throw new Error(`Read-only smoke device is not registered: ${deviceId}`)
if (selected.mcpEnabled !== true || selected.credentialPolicy !== 'no-credentials' || selected.dataPolicy === 'preserve') {
  throw new Error(`Read-only smoke device is not safe for acceptance: ${deviceId}`)
}
const result = await Promise.race([
  client.callTool({ name: 'android_lab_get_screen_state', arguments: { deviceId } }),
  new Promise((_, reject) => setTimeout(() => reject(new Error(`${deviceId} screen call timed out after 20 seconds`)), 20_000)),
])
if (!result?.content?.length) throw new Error(`${deviceId} screen-state call returned no content`)
console.log(JSON.stringify({ status: 'passed', operation: 'android_lab_get_screen_state', deviceId }))
await client.close()
