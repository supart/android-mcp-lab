[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-LabHost

$brokerPort = 18190
$brokerStatePath = Join-Path $script:LocalRoot 'broker.json'
$brokerRuntimePath = Join-Path $script:LocalRoot 'broker-runtime.json'
$brokerLogDirectory = Join-Path $script:LocalRoot 'logs'
$mutex = [Threading.Mutex]::new($false, 'Local\WhiteCodex.AndroidMcpLab.Broker')
$taken = $false
try {
  $taken = $mutex.WaitOne([TimeSpan]::FromSeconds(30))
  if (-not $taken) { throw 'Timed out waiting for the Android MCP Lab broker lock.' }
  $health = $null
  try { $health = Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:$brokerPort/health" -TimeoutSec 2 } catch { $health = $null }
  if ($health -and $health.status -eq 'ready') {
    $token = Get-OrCreateLabBrokerToken -StatePath $brokerStatePath
    [ordered]@{ brokerUrl = "http://127.0.0.1:$brokerPort/mcp"; brokerToken = $token } | ConvertTo-Json -Compress
    exit 0
  }

  $token = Get-OrCreateLabBrokerToken -StatePath $brokerStatePath
  New-Item -ItemType Directory -Force -Path $brokerLogDirectory | Out-Null
  $node = Get-LabNodePath
  $entry = if (Test-Path -LiteralPath (Join-Path $script:LabRoot 'dist\broker.mjs')) { Join-Path $script:LabRoot 'dist\broker.mjs' } else { Join-Path $script:LabRoot 'bridge\src\broker.ts' }
  $arguments = if ($entry.EndsWith('.ts')) { @('--import', 'tsx/esm', $entry) } else { @($entry) }
  $stdoutPath = Join-Path $brokerLogDirectory 'broker.stdout.log'
  $stderrPath = Join-Path $brokerLogDirectory 'broker.stderr.log'
  $quotedArguments = @($arguments | ForEach-Object {
      if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    })
  $environmentNames = @('ANDROID_LAB_BROKER_TOKEN','ANDROID_LAB_BROKER_PORT','ANDROID_LAB_REGISTRY_PATH','ANDROID_LAB_LEASE_DIR','ANDROID_LAB_ROOT','ANDROID_LAB_TOOL_CATALOG','ANDROID_LAB_SUPERVISOR_SCRIPT','ANDROID_LAB_PWSH')
  $environmentValues = @{
    ANDROID_LAB_BROKER_TOKEN = $token
    ANDROID_LAB_BROKER_PORT = [string]$brokerPort
    ANDROID_LAB_REGISTRY_PATH = $script:RegistryPath
    ANDROID_LAB_LEASE_DIR = $script:LeaseRoot
    ANDROID_LAB_ROOT = $script:LabRoot
    ANDROID_LAB_TOOL_CATALOG = Join-Path $script:LabRoot 'assets\upstream-tools-v1.11.1.json'
    ANDROID_LAB_SUPERVISOR_SCRIPT = Join-Path $script:LabRoot 'scripts\Invoke-AndroidLab.ps1'
    ANDROID_LAB_PWSH = if ($env:ANDROID_LAB_PWSH) { $env:ANDROID_LAB_PWSH } else { (Get-Command pwsh -ErrorAction Stop).Source }
  }
  $previousEnvironment = @{}
  foreach ($name in $environmentNames) { $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name); [Environment]::SetEnvironmentVariable($name, [string]$environmentValues[$name], 'Process') }
  try {
    $process = Start-Process -FilePath $node -ArgumentList $quotedArguments -WorkingDirectory $script:LabRoot -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
  } finally {
    foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], 'Process') }
  }
  [ordered]@{ pid = $process.Id; port = $brokerPort; startedAtUtc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json -Compress | Set-Content -LiteralPath $brokerRuntimePath -Encoding UTF8
  $deadline = [DateTime]::UtcNow.AddSeconds(30)
  do {
    Start-Sleep -Milliseconds 250
    try { $health = Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:$brokerPort/health" -TimeoutSec 2 } catch { $health = $null }
    if ($health -and $health.status -eq 'ready') {
      [ordered]@{ brokerUrl = "http://127.0.0.1:$brokerPort/mcp"; brokerToken = $token } | ConvertTo-Json -Compress
      exit 0
    }
  } while ([DateTime]::UtcNow -lt $deadline)
  if (-not $process.HasExited) { $process.Kill($true) }
  throw 'Android MCP Lab broker did not become healthy within 30 seconds.'
} finally {
  if ($taken) { $mutex.ReleaseMutex() }
  $mutex.Dispose()
}
