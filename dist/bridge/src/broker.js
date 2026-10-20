import { randomUUID, timingSafeEqual } from 'node:crypto';
import { createServer as createHttpServer } from 'node:http';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { isInitializeRequest } from '@modelcontextprotocol/sdk/types.js';
import { AndroidLabRuntime } from './runtime.js';
const host = '127.0.0.1';
const port = Number.parseInt(process.env.ANDROID_LAB_BROKER_PORT ?? '18190', 10);
const expectedToken = process.env.ANDROID_LAB_BROKER_TOKEN ?? '';
if (expectedToken.length < 32)
    throw new Error('Android Lab broker token is missing');
const runtime = new AndroidLabRuntime();
const transports = new Map();
function authorized(req) {
    const actual = req.headers.authorization ?? '';
    const wanted = `Bearer ${expectedToken}`;
    const a = Buffer.from(actual);
    const b = Buffer.from(wanted);
    return a.length === b.length && timingSafeEqual(a, b);
}
async function readJson(req) {
    const chunks = [];
    let size = 0;
    for await (const chunk of req) {
        const value = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
        size += value.length;
        if (size > 4 * 1024 * 1024)
            throw new Error('MCP request body is too large');
        chunks.push(value);
    }
    return chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : undefined;
}
function json(res, status, value) {
    const body = JSON.stringify(value);
    res.writeHead(status, { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) });
    res.end(body);
}
const http = createHttpServer(async (req, res) => {
    try {
        if (req.url === '/health' && req.method === 'GET') {
            json(res, 200, { status: 'ready', version: '0.1.3', pid: process.pid });
            return;
        }
        if (req.url !== '/mcp') {
            json(res, 404, { error: 'not_found' });
            return;
        }
        if (!authorized(req)) {
            json(res, 401, { error: 'unauthorized' });
            return;
        }
        const sessionId = typeof req.headers['mcp-session-id'] === 'string' ? req.headers['mcp-session-id'] : undefined;
        let transport = sessionId ? transports.get(sessionId) : undefined;
        if (req.method === 'POST') {
            const body = await readJson(req);
            if (!transport && !sessionId && isInitializeRequest(body)) {
                transport = new StreamableHTTPServerTransport({
                    sessionIdGenerator: () => randomUUID(), enableJsonResponse: true,
                    onsessioninitialized: id => { transports.set(id, transport); },
                });
                const server = runtime.createServer();
                transport.onclose = () => { const id = transport?.sessionId; if (id)
                    transports.delete(id); };
                await server.connect(transport);
                await transport.handleRequest(req, res, body);
                return;
            }
            if (!transport) {
                json(res, 400, { jsonrpc: '2.0', error: { code: -32000, message: 'Invalid or missing MCP session' }, id: null });
                return;
            }
            await transport.handleRequest(req, res, body);
            return;
        }
        if (req.method === 'DELETE' && transport) {
            await transport.handleRequest(req, res);
            return;
        }
        res.writeHead(405, { allow: 'POST, DELETE' });
        res.end('Method Not Allowed');
    }
    catch (error) {
        process.stderr.write(`android-lab-broker: request failed: ${String(error).slice(0, 1000)}\n`);
        if (!res.headersSent)
            json(res, 500, { jsonrpc: '2.0', error: { code: -32603, message: 'Android Lab broker error' }, id: null });
        else
            res.end();
    }
});
http.listen(port, host, () => process.stderr.write(`android-lab-broker: ready http://${host}:${port}\n`));
async function shutdown() {
    http.close();
    await Promise.all([...transports.values()].map(transport => transport.close().catch(() => undefined)));
    await runtime.close();
    process.exit(0);
}
process.once('SIGINT', () => void shutdown());
process.once('SIGTERM', () => void shutdown());
