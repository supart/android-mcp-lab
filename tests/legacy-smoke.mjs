import path from 'node:path'
import { Client } from '@modelcontextprotocol/sdk/client/index.js'
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js'

const root = path.resolve(import.meta.dirname, '..')
const entry = process.env.ANDROID_LAB_LEGACY_ENTRY
if (!entry) {
  console.log(JSON.stringify({ status: 'skipped', reason: 'Set ANDROID_LAB_LEGACY_ENTRY to run the live legacy compatibility smoke.' }))
  process.exit(0)
}
const legacyDevice = process.env.ANDROID_LAB_LEGACY_DEVICE ?? 'codex_api36'
const legacyPrefix = process.env.ANDROID_LAB_LEGACY_PREFIX ?? 'android_legacy_'
const pwsh = process.env.ANDROID_LAB_PWSH ?? 'pwsh.exe'
const isPowerShell = entry.toLowerCase().endsWith('.ps1')
const transport = new StdioClientTransport({
  command: isPowerShell ? pwsh : process.execPath,
  args: isPowerShell ? ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', entry] : [entry],
  cwd: root,
  env: { ...process.env, ANDROID_LAB_LEGACY_DEVICE: legacyDevice, ANDROID_LAB_LEGACY_PREFIX: legacyPrefix },
})

const client = new Client({ name: 'android-lab-legacy-smoke', version: '0.1.3' }, { capabilities: {} })
await client.connect(transport)

const listed = await client.listTools()
const tools = listed.tools
const names = tools.map(tool => tool.name)
const screenToolName = `${legacyPrefix}get_screen_state`
const screenTool = tools.find(tool => tool.name === screenToolName)
if (!screenTool) throw new Error('Legacy screen-state tool is missing')
if (names.some(name => name.startsWith('android_lab_'))) throw new Error('Generic tools leaked into legacy mode')
if (names.some(name => name.startsWith(legacyPrefix) && JSON.stringify(tools.find(tool => tool.name === name)?.inputSchema ?? {}).includes('deviceId'))) {
  throw new Error('Legacy schema still exposes deviceId')
}
if (names.some(name => name.startsWith(legacyPrefix) && JSON.stringify(tools.find(tool => tool.name === name)?.inputSchema ?? {}).includes('leaseId'))) {
  throw new Error('Legacy schema still exposes leaseId')
}

const screen = await client.callTool({ name: screenToolName, arguments: {} })
if (!screen.content?.length) throw new Error('Legacy screen-state call returned no content')

console.log(JSON.stringify({
  status: 'passed',
  toolCount: names.length,
  legacyPrefix,
  genericToolsHidden: true,
  deviceIdHidden: true,
  leaseIdHidden: true,
  readOnlyScreenCall: 'passed',
}))
await client.close()
