import { promises as fs } from 'node:fs'
import path from 'node:path'
import { Client } from '@modelcontextprotocol/sdk/client/index.js'
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js'

const root = path.resolve(import.meta.dirname, '..')
const managementTools = new Set([
  'android_lab_devices',
  'android_lab_acquire',
  'android_lab_release',
  'android_lab_start',
  'android_lab_stop',
  'android_lab_status',
])
const transport = new StdioClientTransport({
  command: process.execPath,
  args: [path.join(root, 'bridge', 'launcher.mjs')],
  cwd: root,
  env: { ...process.env },
})
const client = new Client({ name: 'android-lab-catalog-export', version: '0.1.3' }, { capabilities: {} })
await client.connect(transport)
try {
  const listed = await client.listTools()
  const tools = listed.tools
    .filter(tool => tool.name.startsWith('android_lab_') && !managementTools.has(tool.name))
    .map(tool => {
      const inputSchema = structuredClone(tool.inputSchema)
      delete inputSchema.properties?.deviceId
      delete inputSchema.properties?.leaseId
      if (Array.isArray(inputSchema.required)) inputSchema.required = inputSchema.required.filter(name => name !== 'deviceId' && name !== 'leaseId')
      return { ...tool, name: tool.name.slice('android_lab_'.length), inputSchema }
    })
  if (tools.length !== 57) throw new Error(`Expected 57 upstream tools, received ${tools.length}`)
  const target = path.join(root, 'assets', 'upstream-tools-v1.11.1.json')
  await fs.mkdir(path.dirname(target), { recursive: true })
  await fs.writeFile(target, `${JSON.stringify({ schemaVersion: 1, upstreamVersion: '1.11.1', tools }, null, 2)}\n`, 'utf8')
  process.stderr.write(`android-lab: wrote ${tools.length} tool schemas\n`)
} finally {
  await client.close()
}
