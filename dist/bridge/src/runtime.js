import { execFile } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { CallToolRequestSchema, ListToolsRequestSchema } from '@modelcontextprotocol/sdk/types.js';
const execFileAsync = promisify(execFile);
const root = process.env.ANDROID_LAB_ROOT ?? path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const registryPath = process.env.ANDROID_LAB_REGISTRY_PATH ?? path.join(root, 'state', 'registry.json');
const leaseDirectory = process.env.ANDROID_LAB_LEASE_DIR ?? path.join(root, 'state', 'leases');
const catalogPath = process.env.ANDROID_LAB_TOOL_CATALOG ?? path.join(root, 'assets', 'upstream-tools-v1.11.1.json');
const supervisorScript = process.env.ANDROID_LAB_SUPERVISOR_SCRIPT ?? path.join(root, 'scripts', 'Invoke-AndroidLab.ps1');
const pwsh = process.env.ANDROID_LAB_PWSH ?? 'pwsh.exe';
const expectedToolCount = Number.parseInt(process.env.ANDROID_LAB_EXPECTED_COMPANION_TOOL_COUNT ?? process.env.ANDROID_LAB_EXPECTED_TOOL_COUNT ?? '57', 10);
export const readOnlyOperations = new Set([
    'get_screen_state', 'find_nodes', 'get_node_details', 'list_storage_locations', 'list_files', 'read_file',
    'list_apps', 'list_cameras', 'list_camera_photo_resolutions', 'list_camera_video_resolutions',
    'notification_list', 'get_location', 'get_shared_content', 'wait_for_node', 'wait_for_idle', 'get_clipboard',
]);
const managementTools = new Set([
    'android_lab_devices', 'android_lab_acquire', 'android_lab_release', 'android_lab_start', 'android_lab_stop', 'android_lab_status',
]);
export class CatalogMismatchError extends Error {
    code = 'catalog_mismatch';
    diagnostic;
    constructor(diagnostic) {
        super(`catalog_mismatch: ${JSON.stringify(diagnostic)}`);
        this.name = 'CatalogMismatchError';
        this.diagnostic = diagnostic;
    }
}
function isRecord(value) {
    return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}
function isTool(value) {
    if (!isRecord(value) || typeof value.name !== 'string' || value.name.length === 0)
        return false;
    return isRecord(value.inputSchema);
}
function sanitizeToolName(value) {
    if (typeof value !== 'string')
        return '<invalid>';
    return value.replace(/[^A-Za-z0-9_.:-]/gu, '?').slice(0, 120);
}
function commonPrefix(values) {
    if (values.length === 0)
        return '';
    let prefix = values[0];
    for (const value of values.slice(1)) {
        while (prefix.length > 0 && !value.startsWith(prefix))
            prefix = prefix.slice(0, -1);
        if (prefix.length === 0)
            break;
    }
    return prefix;
}
function stableValue(value) {
    if (Array.isArray(value))
        return value.map(item => stableValue(item));
    if (!isRecord(value))
        return value;
    return Object.fromEntries(Object.entries(value).sort(([left], [right]) => left.localeCompare(right)).map(([key, item]) => [key, stableValue(item)]));
}
function stableJson(value) {
    return JSON.stringify(stableValue(value)) ?? 'null';
}
/**
 * Hash only the tool names and input schemas. Descriptions are intentionally
 * excluded because upstream may reword them without changing the MCP contract.
 */
export function toolCatalogFingerprint(tools) {
    const signatures = tools.map(tool => ({ name: tool.name, inputSchema: stableValue(tool.inputSchema) })).sort((left, right) => left.name.localeCompare(right.name));
    return createHash('sha256').update(stableJson(signatures), 'utf8').digest('hex');
}
function diagnosticForCatalog(value, expectedCount) {
    const catalog = isRecord(value) ? value : undefined;
    const tools = Array.isArray(catalog?.tools) ? catalog.tools : [];
    const names = tools.map(tool => sanitizeToolName(isRecord(tool) ? tool.name : undefined));
    if (catalog?.schemaVersion !== 1) {
        return {
            code: 'catalog_mismatch', reason: 'schema_version', expectedCount, actualCount: tools.length,
            expectedPrefix: '', observedPrefix: commonPrefix(names), expectedUpstreamVersion: typeof catalog?.upstreamVersion === 'string' ? catalog.upstreamVersion : undefined,
        };
    }
    if (!Array.isArray(catalog.tools) || tools.length !== expectedCount) {
        return {
            code: 'catalog_mismatch', reason: 'count', expectedCount, actualCount: tools.length,
            expectedPrefix: '', observedPrefix: commonPrefix(names),
            expectedUpstreamVersion: typeof catalog.upstreamVersion === 'string' ? catalog.upstreamVersion : undefined,
        };
    }
    if (typeof catalog.upstreamVersion !== 'string' || catalog.upstreamVersion.length === 0 || !tools.every(isTool) || new Set(tools.map(tool => tool.name)).size !== tools.length) {
        return {
            code: 'catalog_mismatch', reason: 'schema', expectedCount, actualCount: tools.length,
            expectedPrefix: '', observedPrefix: commonPrefix(names),
            expectedUpstreamVersion: typeof catalog.upstreamVersion === 'string' ? catalog.upstreamVersion : undefined,
        };
    }
    return undefined;
}
export function assertToolCatalog(value, expectedCount) {
    const diagnostic = diagnosticForCatalog(value, expectedCount);
    if (diagnostic)
        throw new CatalogMismatchError(diagnostic);
}
export function compareToolCatalog(expected, actualTools, expectedPrefix) {
    const names = actualTools.map(tool => sanitizeToolName(tool?.name));
    const normalized = actualTools.map(tool => ({
        ...tool,
        name: typeof tool?.name === 'string' && tool.name.startsWith(expectedPrefix) ? tool.name.slice(expectedPrefix.length) : tool?.name,
    }));
    const expectedSchemaHash = toolCatalogFingerprint(expected.tools);
    const observedSchemaHash = actualTools.every(isTool) ? toolCatalogFingerprint(normalized) : undefined;
    const base = {
        code: 'catalog_mismatch',
        expectedCount: expected.tools.length,
        actualCount: actualTools.length,
        expectedPrefix: sanitizeToolName(expectedPrefix),
        observedPrefix: commonPrefix(names),
        expectedSchemaHash,
        observedSchemaHash,
        expectedUpstreamVersion: expected.upstreamVersion,
    };
    if (actualTools.length !== expected.tools.length)
        return { ...base, reason: 'count' };
    if (actualTools.some(tool => typeof tool?.name !== 'string' || !tool.name.startsWith(expectedPrefix)))
        return { ...base, reason: 'prefix' };
    if (!actualTools.every(isTool) || new Set(normalized.map(tool => tool.name)).size !== normalized.length || observedSchemaHash !== expectedSchemaHash)
        return { ...base, reason: 'schema' };
    return undefined;
}
export function isSupervisorReady(value) {
    if (!isRecord(value))
        return false;
    return value.startupPhase === 'ready' && value.bootCompleted === true && value.adbRegistered === true && value.companionReady === true;
}
function redactDiagnostic(value) {
    return String(value).replace(/Bearer\s+\S+/giu, 'Bearer [redacted]').replace(/"token"\s*:\s*"[^"]+"/giu, '"token":"[redacted]"').slice(0, 2000);
}
export class AndroidLabRuntime {
    sessions = new Map();
    sessionStates = new Map();
    // Tokens are returned transiently by the supervisor for the selected device.
    // Do not import a multi-device token map from the process environment.
    tokens = new Map();
    catalogPromise;
    async readRegistry() {
        const value = JSON.parse(await fs.readFile(registryPath, 'utf8'));
        if (value.schemaVersion !== 1 || !Array.isArray(value.devices))
            throw new Error('Invalid Android MCP Lab registry');
        return value;
    }
    async deviceFor(deviceId) {
        const registry = await this.readRegistry();
        const device = registry.devices.find(item => item.deviceId === deviceId);
        if (!device || !device.mcpEnabled)
            throw new Error(`Unknown or disabled Android device: ${deviceId}`);
        return device;
    }
    async catalog() {
        this.catalogPromise ??= fs.readFile(catalogPath, 'utf8').then(value => JSON.parse(value));
        const catalog = await this.catalogPromise;
        assertToolCatalog(catalog, expectedToolCount);
        return catalog;
    }
    leasePath(deviceId) {
        if (!/^[a-z0-9][a-z0-9_-]{1,63}$/u.test(deviceId))
            throw new Error('Invalid Android device id');
        return path.join(leaseDirectory, `${deviceId}.json`);
    }
    async readLease(deviceId) {
        const target = this.leasePath(deviceId);
        try {
            const value = JSON.parse(await fs.readFile(target, 'utf8'));
            if (Date.parse(value.expiresAtUtc) <= Date.now()) {
                await fs.rm(target, { force: true });
                return undefined;
            }
            return value;
        }
        catch {
            return undefined;
        }
    }
    async requireLease(deviceId, leaseId) {
        const lease = await this.readLease(deviceId);
        if (!lease || lease.leaseId !== leaseId)
            throw new Error(`A valid lease is required for ${deviceId}`);
    }
    async acquire(deviceId, owner, ttlSeconds = 900) {
        await this.deviceFor(deviceId);
        await fs.mkdir(leaseDirectory, { recursive: true });
        const target = this.leasePath(deviceId);
        for (let attempt = 0; attempt < 2; attempt += 1) {
            const lease = { schemaVersion: 1, leaseId: randomUUID(), deviceId, owner: owner.slice(0, 120), createdAtUtc: new Date().toISOString(), expiresAtUtc: new Date(Date.now() + Math.max(30, Math.min(ttlSeconds, 3600)) * 1000).toISOString() };
            try {
                const handle = await fs.open(target, 'wx');
                try {
                    await handle.writeFile(JSON.stringify(lease, null, 2), 'utf8');
                }
                finally {
                    await handle.close();
                }
                return lease;
            }
            catch {
                const current = await this.readLease(deviceId);
                if (current)
                    throw new Error(`Android device ${deviceId} is already leased by ${current.owner}`);
                await fs.rm(target, { force: true });
            }
        }
        throw new Error(`Unable to acquire Android device ${deviceId}`);
    }
    async release(deviceId, leaseId) {
        const current = await this.readLease(deviceId);
        if (!current || current.leaseId !== leaseId)
            throw new Error(`Lease does not belong to ${deviceId}`);
        await fs.rm(this.leasePath(deviceId), { force: true });
    }
    async invokeSupervisor(action, deviceId, headless = false) {
        const args = ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', supervisorScript, '-Action', action];
        if (deviceId)
            args.push('-DeviceId', deviceId);
        if (headless)
            args.push('-Headless');
        try {
            const result = await execFileAsync(pwsh, args, { cwd: root, windowsHide: true, maxBuffer: 4 * 1024 * 1024, timeout: action === 'runtime' ? 250_000 : 30_000, env: { ...process.env, ANDROID_LAB_INTERNAL_CALL: '1' } });
            const output = result.stdout.trim().split(/\r?\n/u).filter(Boolean).at(-1);
            return output ? JSON.parse(output) : undefined;
        }
        catch (error) {
            throw new Error(`Android Lab supervisor ${action} failed: ${redactDiagnostic(error)}`);
        }
    }
    async prepareDevice(deviceId, headless = false) {
        const prepared = await this.invokeSupervisor('runtime', deviceId, headless);
        if (!prepared?.device || typeof prepared.token !== 'string' || prepared.token.length < 32)
            throw new Error(`Android Lab supervisor returned an invalid runtime for ${deviceId}`);
        this.tokens.set(deviceId, prepared.token);
        return prepared;
    }
    async connect(deviceId) {
        const prepared = await this.prepareDevice(deviceId);
        const device = prepared.device;
        const token = this.tokens.get(deviceId);
        if (!token)
            throw new Error(`No transient token available for ${deviceId}`);
        process.stderr.write(`android-lab-broker: connecting ${deviceId} port=${device.hostPort}\n`);
        let client;
        let transport;
        let listedTools = [];
        let lastError;
        for (let attempt = 0; attempt < 6; attempt += 1) {
            client = new Client({ name: 'whitecodex-android-lab-broker', version: '0.1.3' }, { capabilities: {} });
            transport = new StreamableHTTPClientTransport(new URL(`http://127.0.0.1:${device.hostPort}/mcp`), { requestInit: { headers: { Authorization: `Bearer ${token}` } } });
            try {
                await client.connect(transport);
                listedTools = [];
                let cursor;
                do {
                    const page = await client.listTools(cursor === undefined ? undefined : { cursor });
                    listedTools.push(...page.tools);
                    cursor = page.nextCursor;
                } while (cursor !== undefined);
                break;
            }
            catch (error) {
                lastError = error;
                await transport.close().catch(() => undefined);
                if (attempt === 5)
                    throw new Error(`Upstream MCP connection failed for ${deviceId}: ${redactDiagnostic(error)}`);
                await new Promise(resolve => setTimeout(resolve, 500 * (attempt + 1)));
            }
        }
        if (!client || !transport || listedTools.length === 0)
            throw new Error(`Upstream MCP connection failed for ${deviceId}: ${redactDiagnostic(lastError)}`);
        const catalog = await this.catalog();
        const prefix = `android_${device.deviceSlug}_`;
        const mismatch = compareToolCatalog(catalog, listedTools, prefix);
        if (mismatch) {
            await transport.close().catch(() => undefined);
            throw new CatalogMismatchError(mismatch);
        }
        process.stderr.write(`android-lab-broker: connected ${deviceId} tools=${listedTools.length}\n`);
        this.sessionStates.set(deviceId, this.sessionStates.has(deviceId) ? 'recovered' : 'fresh');
        return { client, transport, tools: listedTools, prefix };
    }
    async sessionFor(deviceId) {
        const current = this.sessions.get(deviceId);
        if (current)
            return current;
        const promise = this.connect(deviceId);
        this.sessions.set(deviceId, promise);
        try {
            return await promise;
        }
        catch (error) {
            this.sessions.delete(deviceId);
            throw error;
        }
    }
    async closeSession(deviceId) {
        const pending = this.sessions.get(deviceId);
        this.sessions.delete(deviceId);
        if (!pending)
            return;
        try {
            await (await pending).client.close();
        }
        catch { /* device may already be offline */ }
    }
    async callUpstream(deviceId, operation, args) {
        for (let attempt = 0; attempt < 2; attempt += 1) {
            const session = await this.sessionFor(deviceId);
            const source = session.tools.find(tool => tool.name === `${session.prefix}${operation}`);
            if (!source)
                throw new Error(`Operation is not present in upstream inventory: ${operation}`);
            try {
                return await session.client.callTool({ name: source.name, arguments: args });
            }
            catch (error) {
                const message = redactDiagnostic(error);
                if (attempt === 0 && readOnlyOperations.has(operation) && /session\s+not\s+found|streamable\s+http\s+error|status\s*404/iu.test(message)) {
                    this.sessionStates.set(deviceId, 'invalidated');
                    await this.closeSession(deviceId);
                    continue;
                }
                if (/session\s+not\s+found|streamable\s+http\s+error|status\s*404/iu.test(message)) {
                    throw new Error(`session_recovery_required: operation ${operation} was not retried after session invalidation`);
                }
                throw error;
            }
        }
        throw new Error(`Upstream MCP operation failed after reconnect: ${operation}`);
    }
    mergedSchema(source) {
        const schema = source.inputSchema;
        const properties = { ...(schema.properties ?? {}) };
        properties.deviceId = { type: 'string', description: 'Registered local Android emulator device id' };
        properties.leaseId = { type: 'string', description: 'Lease returned by android_lab_acquire; required for mutating calls' };
        return { ...schema, properties, required: Array.from(new Set(['deviceId', ...(Array.isArray(schema.required) ? schema.required : [])])) };
    }
    async buildTools() {
        const catalog = await this.catalog();
        const tools = [
            { name: 'android_lab_devices', description: 'List registered local Android emulators and their protection policy', inputSchema: { type: 'object', properties: {} } },
            { name: 'android_lab_acquire', description: 'Acquire an exclusive cross-task lease for one Android emulator', inputSchema: { type: 'object', properties: { deviceId: { type: 'string' }, owner: { type: 'string' }, ttlSeconds: { type: 'integer', minimum: 30, maximum: 3600 } }, required: ['deviceId'] } },
            { name: 'android_lab_release', description: 'Release an Android emulator lease', inputSchema: { type: 'object', properties: { deviceId: { type: 'string' }, leaseId: { type: 'string' } }, required: ['deviceId', 'leaseId'] } },
            { name: 'android_lab_start', description: 'Start and prepare a registered Android emulator', inputSchema: { type: 'object', properties: { deviceId: { type: 'string' }, leaseId: { type: 'string' }, headless: { type: 'boolean' } }, required: ['deviceId', 'leaseId'] } },
            { name: 'android_lab_stop', description: 'Stop Android MCP for a registered emulator; test AVDs are also shut down', inputSchema: { type: 'object', properties: { deviceId: { type: 'string' }, leaseId: { type: 'string' } }, required: ['deviceId', 'leaseId'] } },
            { name: 'android_lab_status', description: 'Return sanitized supervisor status for registered Android emulators', inputSchema: { type: 'object', properties: { deviceId: { type: 'string' } } } },
        ];
        for (const source of catalog.tools)
            tools.push({ ...source, name: `android_lab_${source.name}`, inputSchema: this.mergedSchema(source) });
        return tools;
    }
    createServer() {
        const server = new Server({ name: 'whitecodex-android-lab', version: '0.1.3' }, { capabilities: { tools: {} } });
        server.setRequestHandler(ListToolsRequestSchema, async () => ({ tools: await this.buildTools() }));
        server.setRequestHandler(CallToolRequestSchema, async (request) => {
            const name = request.params.name;
            const args = { ...(request.params.arguments ?? {}) };
            if (name === 'android_lab_devices')
                return { content: [{ type: 'text', text: JSON.stringify((await this.readRegistry()).devices) }] };
            if (name === 'android_lab_acquire')
                return { content: [{ type: 'text', text: JSON.stringify(await this.acquire(String(args.deviceId ?? ''), String(args.owner ?? 'codex-task'), Number(args.ttlSeconds ?? 900))) }] };
            if (name === 'android_lab_release') {
                await this.release(String(args.deviceId ?? ''), String(args.leaseId ?? ''));
                return { content: [{ type: 'text', text: 'released' }] };
            }
            if (name === 'android_lab_start') {
                const deviceId = String(args.deviceId ?? '');
                await this.requireLease(deviceId, typeof args.leaseId === 'string' ? args.leaseId : undefined);
                await this.deviceFor(deviceId);
                const started = await this.invokeSupervisor('start', deviceId, args.headless === true);
                if (started.bootCompleted) {
                    const prepared = await this.prepareDevice(deviceId, args.headless === true);
                    const live = await this.invokeSupervisor('status', deviceId);
                    // Supervisor status is authoritative. Do not promote guest boot to ready
                    // or overwrite companion/ADB failures with optimistic values.
                    return { content: [{ type: 'text', text: JSON.stringify({ ...live, device: prepared.device }) }] };
                }
                return { content: [{ type: 'text', text: JSON.stringify(started) }] };
            }
            if (name === 'android_lab_stop') {
                const deviceId = String(args.deviceId ?? '');
                await this.requireLease(deviceId, typeof args.leaseId === 'string' ? args.leaseId : undefined);
                await this.closeSession(deviceId);
                await this.invokeSupervisor('down', deviceId);
                return { content: [{ type: 'text', text: JSON.stringify({ deviceId, status: 'stopped' }) }] };
            }
            if (name === 'android_lab_status') {
                const deviceId = typeof args.deviceId === 'string' ? args.deviceId : undefined;
                const status = await this.invokeSupervisor('status', deviceId);
                const annotate = (value) => {
                    if (Array.isArray(value))
                        return value.map(item => annotate(item));
                    if (!value || typeof value !== 'object')
                        return value;
                    const item = value;
                    const id = typeof item.deviceId === 'string' ? item.deviceId : deviceId;
                    const sessionState = id ? (this.sessionStates.get(id) ?? 'not_started') : 'not_started';
                    return { ...item, session: { state: sessionState, recovery: sessionState === 'invalidated' ? 'reconnect_required' : null } };
                };
                return { content: [{ type: 'text', text: JSON.stringify(annotate(status)) }] };
            }
            if (!name.startsWith('android_lab_') || managementTools.has(name))
                throw new Error(`Unknown Android Lab tool: ${name}`);
            const operation = name.slice('android_lab_'.length);
            const deviceId = String(args.deviceId ?? '');
            await this.deviceFor(deviceId);
            if (!readOnlyOperations.has(operation))
                await this.requireLease(deviceId, typeof args.leaseId === 'string' ? args.leaseId : undefined);
            delete args.deviceId;
            delete args.leaseId;
            return await this.callUpstream(deviceId, operation, args);
        });
        return server;
    }
    async close() { await Promise.all([...this.sessions.keys()].map(deviceId => this.closeSession(deviceId))); }
}
