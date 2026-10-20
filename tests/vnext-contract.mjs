import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { callWithSessionRecovery, LeaseTracker } from '../bridge/src/session-lifecycle.ts'
import { assertToolCatalog, compareToolCatalog, isSupervisorReady } from '../bridge/src/runtime.ts'

const labRoot = fileURLToPath(new URL('../', import.meta.url))
const skillRoot = `${labRoot}/skill/ty-android-mcp`
const packageMetadata = JSON.parse(await readFile(`${labRoot}/package.json`, 'utf8'))
const skill = await readFile(`${skillRoot}/SKILL.md`, 'utf8')
const workflow = await readFile(`${skillRoot}/references/workflow-recipes.md`, 'utf8')
const policy = await readFile(`${skillRoot}/references/device-policy.md`, 'utf8')
const skillVersion = (await readFile(`${skillRoot}/VERSION`, 'utf8')).trim()
const statusScript = await readFile(`${labRoot}/scripts/Invoke-AndroidLab.ps1`, 'utf8')
const acceptanceHelper = await readFile(`${labRoot}/scripts/AndroidLabMcpAcceptance.mjs`, 'utf8')
const acceptanceScript = await readFile(`${labRoot}/scripts/Invoke-AndroidLabAcceptance.ps1`, 'utf8')
const commonScript = await readFile(`${labRoot}/scripts/Common.ps1`, 'utf8')
const runtimeExportScript = await readFile(`${labRoot}/scripts/Export-AndroidLabRuntime.ps1`, 'utf8')
const catalogExportScript = await readFile(`${labRoot}/scripts/Export-UpstreamToolCatalog.mjs`, 'utf8')
const bridgeStartScript = await readFile(`${labRoot}/scripts/Start-AndroidMcpLabBridge.ps1`, 'utf8')
const liveSmokeSources = await Promise.all(['bridge-smoke.mjs', 'device-readonly-smoke.mjs', 'lease-smoke.mjs'].map(name => readFile(`${labRoot}/tests/${name}`, 'utf8')))
const proxySource = await readFile(`${labRoot}/bridge/src/proxy.ts`, 'utf8')
const stableSource = [proxySource, await readFile(`${labRoot}/bridge/src/runtime.ts`, 'utf8'), await readFile(`${labRoot}/bridge/src/broker.ts`, 'utf8')].join('\n')

assert.equal(packageMetadata.version, '0.1.3')
const escapedPackageVersion = packageMetadata.version.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
assert.match(commonScript, new RegExp(`LabVersion\\s*=\\s*'${escapedPackageVersion}'`))
assert.doesNotMatch(stableSource, /version:\s*['"]0\.1\.[01]['"]/)

for (const required of ['fresh screen state', 'type_replace_text', 'credential', 'dismiss_keyboard', 'session_recovery_required', 'catalog_mismatch']) {
  assert.match(skill, new RegExp(required.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'), `Skill missing ${required}`)
}
for (const required of ['broker_recovery_deferred', 'project_installer_untrusted', 'per-operation', 'exact APK']) {
  assert.match(`${skill}\n${workflow}`, new RegExp(required.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'), `Skill workflow missing ${required}`)
}
assert.match(workflow, /ui_state_mismatch/i)
assert.match(policy, /bootCompleted=true.*adbRegistered=true.*companionReady=true/is)
assert.match(statusScript, /startupPhase/)
assert.match(statusScript, /adbRegistered/)
assert.match(statusScript, /companionReady/)
assert.match(statusScript, /emulatorVersion/)
assert.match(statusScript, /'runtime'\s*\{[\s\S]*ANDROID_LAB_INTERNAL_CALL[\s\S]*token\s*=/)
assert.match(commonScript, /dataPolicy -ne 'preserve'/)
assert.doesNotMatch(runtimeExportScript, /Unprotect-LabText|tokenMap|tokenDpapi/i)
assert.doesNotMatch(runtimeExportScript, /Invoke-AndroidLab\.ps1|Action\s+up/i)
assert.match(runtimeExportScript, /statePresence/)
assert.match(runtimeExportScript, /expectedCompanionToolCount\s*=\s*57/)
assert.match(runtimeExportScript, /expectedExposedToolCount\s*=\s*63/)
for (const managementTool of ['devices', 'acquire', 'release', 'start', 'stop', 'status']) assert.match(catalogExportScript, new RegExp(`android_lab_${managementTool}`))
assert.doesNotMatch(catalogExportScript, /ANDROID_LAB_CATALOG_DEVICE/)
assert.doesNotMatch(bridgeStartScript, /Unprotect-LabText|ANDROID_LAB_TOKEN_MAP|tokenDpapi/i)
assert.match(bridgeStartScript, /bridge\\launcher\.mjs/)
assert.doesNotMatch(bridgeStartScript, /bridge\\src\\server\.ts/)
assert.match(commonScript, /BridgeEntry.*bridge\\launcher\.mjs/)
assert.doesNotMatch(commonScript, /WorkspaceRoot|android-toolchain/i)
assert.doesNotMatch(skill, /adb\s+shell\s+input/i)
assert.equal(skillVersion, '0.2.0')
for (const variable of ['TY_ANDROID_MCP_APK', 'TY_ANDROID_MCP_INSTALL_SCRIPT', 'TY_ANDROID_MCP_PACKAGE']) assert.match(skill, new RegExp(variable))
assert.doesNotMatch(`${skill}\n${workflow}\n${policy}`, /C:\\Users\\|[A-Z]:\\|dsh-mobile-demo/i)
assert.match(`${skill}\n${workflow}`, /Sort-Object \{ \[version\]\$_\.Name \} -Descending/)
assert.doesNotMatch(`${skill}\n${workflow}`, /Sort-Object Name -Descending/)
assert.match(proxySource, /ANDROID_LAB_EXPECTED_EXPOSED_TOOL_COUNT\s*\?\?\s*'63'/)
const runtimeSource = await readFile(`${labRoot}/bridge/src/runtime.ts`, 'utf8')
assert.match(runtimeSource, /ANDROID_LAB_EXPECTED_COMPANION_TOOL_COUNT/)
assert.match(runtimeSource, /expectedSchemaHash/)
assert.match(runtimeSource, /observedSchemaHash/)
assert.match(runtimeSource, /expectedPrefix/)
assert.match(runtimeSource, /observedPrefix/)
assert.match(runtimeSource, /isSupervisorReady/)
assert.doesNotMatch(runtimeSource, /status:\s*'ready',\s*startupPhase:\s*'ready',\s*bootCompleted:\s*true,\s*adbRegistered:\s*true,\s*companionReady:\s*true/)
assert.doesNotMatch(stableSource, /android_lab_mirror_/i)
assert.match(acceptanceHelper, /function assertSafeAcceptanceDevice\(/)
assert.match(acceptanceHelper, /credentialPolicy\s*!==\s*'no-credentials'/)
assert.match(acceptanceHelper, /dataPolicy\s*===\s*'preserve'/)
assert.match(acceptanceHelper, /mcpEnabled\s*!==\s*true/)
assert.ok(acceptanceHelper.indexOf('assertSafeAcceptanceDevice(selectedDevice') < acceptanceHelper.indexOf("name: 'android_lab_acquire'"), 'acceptance must gate the selected device before acquire')
assert.ok(acceptanceHelper.indexOf('assertSafeAcceptanceDevice(parallelDevice') < acceptanceHelper.indexOf("owner: 'android-lab-parallel'"), 'acceptance must gate parallel device before acquire')
assert.match(acceptanceScript, /if \(\$errors\.Count -eq 0\)/)
assert.match(acceptanceScript, /Skipped because preflight safety checks failed/)
assert.match(acceptanceScript, /dataPolicy\s*-ne\s*'preserve'/)
assert.doesNotMatch(acceptanceScript, /-or\s+\$Mode\s+-eq\s+'Full'/i)
for (const smokeSource of liveSmokeSources) {
  assert.match(smokeSource, /credentialPolicy\s*!==\s*'no-credentials'/)
  assert.match(smokeSource, /dataPolicy\s*===\s*'preserve'/)
  assert.match(smokeSource, /mcpEnabled\s*!==\s*true/)
}

const catalogTool = (name, inputSchema = { type: 'object', properties: {} }) => ({ name, description: `${name} fixture`, inputSchema })
const expectedCatalog = { schemaVersion: 1, upstreamVersion: '1.11.1', tools: Array.from({ length: 57 }, (_, index) => catalogTool(`tool_${String(index).padStart(2, '0')}`)) }
assert.doesNotThrow(() => assertToolCatalog(expectedCatalog, 57))
assert.throws(() => assertToolCatalog({ ...expectedCatalog, tools: expectedCatalog.tools.slice(0, 56) }, 57), /catalog_mismatch/)
assert.throws(() => assertToolCatalog({ ...expectedCatalog, tools: expectedCatalog.tools.map(tool => ({ ...tool, inputSchema: undefined })) }, 57), /catalog_mismatch/)

const prefixedTools = expectedCatalog.tools.map(tool => ({ ...tool, name: `android_codex_api36_${tool.name}` }))
assert.equal(compareToolCatalog(expectedCatalog, prefixedTools, 'android_codex_api36_'), undefined)
const schemaMismatch = compareToolCatalog(expectedCatalog, prefixedTools.map((tool, index) => index === 0 ? { ...tool, inputSchema: { type: 'object', properties: { changed: { type: 'string' } } } } : tool), 'android_codex_api36_')
assert.equal(schemaMismatch?.code, 'catalog_mismatch')
assert.equal(schemaMismatch?.reason, 'schema')
assert.equal(schemaMismatch?.expectedCount, 57)
assert.equal(schemaMismatch?.actualCount, 57)
assert.equal(schemaMismatch?.expectedPrefix, 'android_codex_api36_')
assert.equal(typeof schemaMismatch?.observedPrefix, 'string')
assert.notEqual(schemaMismatch?.expectedSchemaHash, schemaMismatch?.observedSchemaHash)
const prefixMismatch = compareToolCatalog(expectedCatalog, prefixedTools.map((tool, index) => index === 0 ? { ...tool, name: `android_other_${tool.name.slice('android_codex_api36_'.length)}` } : tool), 'android_codex_api36_')
assert.equal(prefixMismatch?.reason, 'prefix')

assert.equal(isSupervisorReady({ startupPhase: 'ready', bootCompleted: true, adbRegistered: true, companionReady: true }), true)
assert.equal(isSupervisorReady({ startupPhase: 'companion_not_ready', bootCompleted: true, adbRegistered: true, companionReady: false }), false)
assert.equal(isSupervisorReady({ startupPhase: 'guest_boot', bootCompleted: true, adbRegistered: false, companionReady: false }), false)

let reconnects = 0
let calls = 0
const recovered = await callWithSessionRecovery(
  async () => { calls += 1; if (calls === 1) throw new Error('Invalid or missing MCP session'); return 'ok' },
  async () => { reconnects += 1 },
  true,
)
assert.equal(recovered, 'ok')
assert.equal(reconnects, 1)
assert.equal(calls, 2)

let unsafeCalls = 0
await assert.rejects(
  () => callWithSessionRecovery(async () => { unsafeCalls += 1; throw new Error('Transport closed') }, async () => {}, false),
  /session_recovery_required/,
)
assert.equal(unsafeCalls, 1)

const tracker = new LeaseTracker()
tracker.track({ deviceId: 'one', leaseId: 'lease-one' })
tracker.track({ deviceId: 'two', leaseId: 'lease-two' })
const released = []
const failures = await tracker.releaseAll(async lease => {
  released.push(lease.deviceId)
  if (lease.deviceId === 'two') throw new Error('simulated release failure')
})
assert.deepEqual(released, ['one', 'two'])
assert.equal(failures.length, 1)
assert.equal(tracker.values().length, 0)

console.log(JSON.stringify({ status: 'passed', catalog: true, sessionRecovery: true, sideEffectRetryBlocked: true, leaseCleanup: true, skillPolicy: true }))
