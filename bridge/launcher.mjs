import { spawn } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const bridgeRoot = path.dirname(fileURLToPath(import.meta.url))
const labRoot = path.resolve(bridgeRoot, '..')
const pwsh = process.env.ANDROID_LAB_PWSH ?? 'pwsh.exe'
const ensureScript = path.join(labRoot, 'scripts', 'Ensure-AndroidLabBroker.ps1')

function redact(value) {
  return String(value)
    .replace(/Bearer\s+\S+/giu, 'Bearer [redacted]')
    .replace(/"(brokerToken|token)"\s*:\s*"[^"]+"/giu, '"$1":"[redacted]"')
}

function ensureBroker() {
  return new Promise((resolve, reject) => {
    const child = spawn(pwsh, ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', ensureScript], {
      cwd: labRoot,
      windowsHide: true,
      env: { ...process.env, ANDROID_LAB_INTERNAL_CALL: '1' },
      stdio: ['ignore', 'pipe', 'pipe'],
    })
    let stdout = ''
    let stderr = ''
    let settled = false

    const finish = (error, runtime) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      if (error) reject(error)
      else resolve(runtime)
    }

    const parseRuntime = () => {
      const lines = stdout.trim().split(/\r?\n/u)
      for (let index = lines.length - 1; index >= 0; index -= 1) {
        try {
          const runtime = JSON.parse(lines[index])
          if (runtime?.brokerUrl && runtime?.brokerToken) {
            child.stdout.destroy()
            child.stderr.destroy()
            child.unref()
            finish(null, runtime)
            return
          }
        } catch {
          // Ignore non-JSON lines emitted during broker preparation.
        }
      }
    }

    const timer = setTimeout(() => {
      child.kill()
      finish(new Error('Android MCP Lab broker preparation timed out.'))
    }, 45_000)

    child.stdout.on('data', chunk => {
      stdout += chunk.toString()
      parseRuntime()
    })
    child.stderr.on('data', chunk => {
      stderr += chunk.toString()
    })
    child.on('error', error => finish(error))
    child.on('exit', code => {
      parseRuntime()
      if (!settled) {
        const detail = redact(stderr || stdout || 'Android MCP Lab broker preparation failed')
        finish(new Error(`Android MCP Lab broker preparation exited with code ${code ?? 'unknown'}: ${detail}`))
      }
    })
  })
}

let runtime
try {
  runtime = await ensureBroker()
} catch (error) {
  process.stderr.write(redact(error?.message ?? error))
  process.exit(1)
}
const entry = process.env.ANDROID_LAB_PROXY_ENTRY ?? (await import('node:fs').then(({ existsSync }) => existsSync(path.join(bridgeRoot, '..', 'dist', 'proxy.mjs')) ? path.join(bridgeRoot, '..', 'dist', 'proxy.mjs') : path.join(bridgeRoot, 'src', 'proxy.ts')))
const args = entry.endsWith('.ts') ? ['--import', 'tsx/esm', entry] : [entry]
const child = spawn(process.execPath, args, { cwd: labRoot, stdio: 'inherit', windowsHide: true, env: { ...process.env, ANDROID_LAB_BROKER_URL: runtime.brokerUrl, ANDROID_LAB_BROKER_TOKEN: runtime.brokerToken } })
child.on('exit', code => { process.exitCode = code ?? 1 })
