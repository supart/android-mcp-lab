import { randomUUID } from 'node:crypto';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
import { readOnlyOperations } from './runtime.js';
import { callWithSessionRecovery, LeaseTracker } from './session-lifecycle.js';
const brokerUrl = process.env.ANDROID_LAB_BROKER_URL ?? '';
const brokerToken = process.env.ANDROID_LAB_BROKER_TOKEN ?? '';
const legacyDevice = process.env.ANDROID_LAB_LEGACY_DEVICE ?? '';
const legacyPrefix = process.env.ANDROID_LAB_LEGACY_PREFIX ?? 'android_dsh36_';
if (!brokerUrl || brokerToken.length < 32)
    throw new Error('Android Lab broker runtime is missing');
let client;
let upstream;
let listed = { tools: [] };
let brokerSessionState = 'fresh';
const expectedExposedToolCount = Number.parseInt(process.env.ANDROID_LAB_EXPECTED_EXPOSED_TOOL_COUNT ?? '63', 10);
const management = new Set(['android_lab_devices', 'android_lab_acquire', 'android_lab_release', 'android_lab_start', 'android_lab_stop', 'android_lab_status']);
const leases = new LeaseTracker();
async function connectBroker() {
    if (client)
        await client.close().catch(() => undefined);
    client = new Client({ name: legacyDevice ? 'whitecodex-android-lab-legacy-proxy' : 'whitecodex-android-lab-proxy', version: '0.1.3' }, { capabilities: {} });
    upstream = new StreamableHTTPClientTransport(new URL(brokerUrl), { requestInit: { headers: { Authorization: `Bearer ${brokerToken}` } } });
    await client.connect(upstream);
    listed = await client.listTools();
    if (listed.tools.length !== expectedExposedToolCount)
        throw new Error(`catalog_mismatch: expected ${expectedExposedToolCount} exposed tools, got ${listed.tools.length}`);
    brokerSessionState = brokerSessionState === 'fresh' ? 'fresh' : 'recovered';
}
await connectBroker();
function brokerClient() {
    if (!client)
        throw new Error('Android Lab broker session is not connected');
    return client;
}
function shouldRetry(name) {
    if (name === 'android_lab_status' || name === 'android_lab_devices')
        return true;
    const operation = name.startsWith('android_lab_') ? name.slice('android_lab_'.length) : name;
    return readOnlyOperations.has(operation);
}
async function callBroker(params) {
    const name = params.name;
    return await callWithSessionRecovery(() => brokerClient().callTool(params), async () => {
        brokerSessionState = 'invalidated';
        await connectBroker();
    }, shouldRetry(name));
}
function recordLease(result) {
    const content = result.content?.find(item => item.type === 'text');
    if (content?.type !== 'text')
        return;
    try {
        const value = JSON.parse(content.text);
        if (value.deviceId && value.leaseId)
            leases.track({ deviceId: value.deviceId, leaseId: value.leaseId });
    }
    catch { /* non-JSON tool result */ }
}
function legacyTool(source) {
    const schema = structuredClone(source.inputSchema);
    delete schema.properties?.deviceId;
    delete schema.properties?.leaseId;
    if (Array.isArray(schema.required))
        schema.required = schema.required.filter(name => name !== 'deviceId' && name !== 'leaseId');
    return { ...source, name: `${legacyPrefix}${source.name.slice('android_lab_'.length)}`, inputSchema: schema };
}
const visibleTools = legacyDevice ? listed.tools.filter(tool => tool.name.startsWith('android_lab_') && !management.has(tool.name)).map(legacyTool) : listed.tools;
async function ensureLegacyLease() {
    const current = leases.values().find(lease => lease.deviceId === legacyDevice);
    if (current)
        return current.leaseId;
    const result = await callBroker({ name: 'android_lab_acquire', arguments: { deviceId: legacyDevice, owner: `legacy-proxy-${process.pid}-${randomUUID()}`, ttlSeconds: 900 } });
    const content = result.content?.find(item => item.type === 'text');
    const value = JSON.parse(content?.type === 'text' ? content.text : '{}');
    if (!value.leaseId)
        throw new Error(`Unable to acquire compatibility lease for ${legacyDevice}`);
    leases.track({ deviceId: legacyDevice, leaseId: value.leaseId });
    return value.leaseId;
}
const server = new Server({ name: legacyDevice ? 'whitecodex-android-lab-legacy' : 'whitecodex-android-lab', version: '0.1.3' }, { capabilities: { tools: {} } });
server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: visibleTools }));
server.setRequestHandler(CallToolRequestSchema, async (request) => {
    if (!legacyDevice) {
        const result = await callBroker(request.params);
        if (request.params.name === 'android_lab_acquire')
            recordLease(result);
        if (request.params.name === 'android_lab_release') {
            const args = request.params.arguments;
            if (typeof args?.deviceId === 'string')
                leases.forget(args.deviceId);
        }
        return result;
    }
    if (!request.params.name.startsWith(legacyPrefix))
        throw new Error(`Unknown legacy Android tool: ${request.params.name}`);
    const operation = request.params.name.slice(legacyPrefix.length);
    const args = { ...(request.params.arguments ?? {}), deviceId: legacyDevice };
    if (!readOnlyOperations.has(operation))
        args.leaseId = await ensureLegacyLease();
    const result = await callBroker({ name: `android_lab_${operation}`, arguments: args });
    if (operation === 'release')
        leases.forget(legacyDevice);
    return result;
});
let cleaned = false;
async function cleanup() {
    if (cleaned)
        return;
    cleaned = true;
    const failures = await leases.releaseAll(async (lease) => {
        await callBroker({ name: 'android_lab_release', arguments: { deviceId: lease.deviceId, leaseId: lease.leaseId } });
    });
    if (failures.length)
        process.stderr.write(`android-lab-proxy: lease cleanup incomplete ${failures.join('; ')}\n`);
    await client?.close().catch(() => undefined);
}
const gracefulExit = () => { void cleanup().finally(() => process.exit(0)); };
const stdio = new StdioServerTransport();
await server.connect(stdio);
process.stderr.write(`android-lab-proxy: ready${legacyDevice ? ` legacy=${legacyDevice}` : ''}\n`);
process.once('SIGINT', gracefulExit);
process.once('SIGTERM', gracefulExit);
process.stdin.once('end', gracefulExit);
