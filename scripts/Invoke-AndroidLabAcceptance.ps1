[CmdletBinding()]
param(
  [ValidateSet('Config','Validate','Full')][string]$Mode = 'Full',
  [string]$DeviceId = 'codex_api36',
  [switch]$Headless
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-LabHost
$started = [DateTime]::UtcNow
$checks = [ordered]@{}
$errors = [Collections.Generic.List[string]]::new()

function Add-Check([string]$Name, [bool]$Passed, [string]$Detail) {
  $checks[$Name] = [ordered]@{ passed = $Passed; detail = $Detail }
  if (-not $Passed) { $errors.Add("${Name}: $Detail") }
}

function Get-CodexConfigCheck {
  $path = Join-Path $env:USERPROFILE '.codex\config.toml'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return [ordered]@{ path = $path; exists = $false; androidLab = $false; approvalNever = $false; dangerFullAccess = $false; sensitiveMaterial = $false } }
  $content = Get-Content -Raw -LiteralPath $path
  return [ordered]@{
    path = $path
    exists = $true
    androidLab = ($content -match '(?m)^\[mcp_servers\.android_lab\]')
    approvalNever = ($content -match '(?m)^approval_policy\s*=\s*["'']never["'']')
    dangerFullAccess = ($content -match '(?m)^sandbox_mode\s*=\s*["'']danger-full-access["'']')
    sensitiveMaterial = ($content -match '(?i)(Bearer\s+[A-Za-z0-9._-]{20,}|api[_-]?key\s*[:=]|tokenDpapi\s*[:=])')
  }
}

if ($Mode -eq 'Config') {
  $config = Get-CodexConfigCheck
  Add-Check 'codexConfigExists' ([bool]$config.exists) 'Codex global config exists'
  Add-Check 'androidLabRegistered' ([bool]$config.androidLab) 'android_lab MCP entry is registered'
  Add-Check 'approvalPolicy' ([bool]$config.approvalNever) 'approval_policy remains never'
  Add-Check 'sandboxPolicy' ([bool]$config.dangerFullAccess) 'sandbox_mode remains danger-full-access'
  Add-Check 'configSensitiveScan' (-not [bool]$config.sensitiveMaterial) 'no token-like material detected'
} else {
  if ($Mode -eq 'Full') {
    try {
      $bootstrapArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Bootstrap-AndroidMcpLab.ps1'),'-Mode','Auto')
      if ($Headless) { $bootstrapArgs += '-Headless' }
      $bootstrap = @(& (Get-Command pwsh -ErrorAction Stop).Source @bootstrapArgs 2>&1 | ForEach-Object { $_.ToString() })
      Add-Check 'bootstrap' ($LASTEXITCODE -eq 0) 'SDK, codex_api36, registry and MCP preparation'
    } catch { Add-Check 'bootstrap' $false 'Bootstrap failed before completion' }
  } else {
    try {
      $validateArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Bootstrap-AndroidMcpLab.ps1'),'-Mode','Validate')
      $null = & (Get-Command pwsh -ErrorAction Stop).Source @validateArgs 2>&1
      Add-Check 'bootstrapValidate' ($LASTEXITCODE -eq 0) 'SDK, image and codex_api36 validation'
    } catch { Add-Check 'bootstrapValidate' $false 'Validation failed' }
  }
  try {
    $registry = Discover-LabRegistry
    $device = @($registry.devices | Where-Object deviceId -eq $DeviceId) | Select-Object -First 1
    Add-Check 'deviceRegistered' ($null -ne $device) "registered device $DeviceId"
    Add-Check 'deviceEnabled' ([bool]($device -and $device.mcpEnabled)) 'device is enabled for MCP'
    Add-Check 'deviceIsolation' ([bool]($device -and $device.controlMode -eq 'codex-exclusive' -and $device.credentialPolicy -eq 'no-credentials' -and $device.dataPolicy -ne 'preserve')) 'Codex device is exclusive, credential-free and not preserve-only'
  } catch { Add-Check 'deviceRegistry' $false 'Unable to read device registry' }
  if ($errors.Count -eq 0) {
    try {
      $node = Get-LabNodePath
      $helper = Join-Path $PSScriptRoot 'AndroidLabMcpAcceptance.mjs'
      $output = @(& $node $helper $script:LabRoot $DeviceId 2>$null | ForEach-Object { $_.ToString() })
      $json = $output | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1
      $result = if ($json) { $json | ConvertFrom-Json } else { $null }
      Add-Check 'mcpRoute' ([bool]($result -and $result.status -eq 'passed')) 'tools/list, lease, Settings launch, screenshot and back'
    } catch { Add-Check 'mcpRoute' $false 'MCP route smoke failed' }
  } else {
    Add-Check 'mcpRoute' $false 'Skipped because preflight safety checks failed; no MCP acquire or write was attempted'
  }
  $config = Get-CodexConfigCheck
  Add-Check 'androidLabRegistered' ([bool]$config.androidLab) 'android_lab MCP entry is registered'
  Add-Check 'configSensitiveScan' (-not [bool]$config.sensitiveMaterial) 'no token-like material detected'
}

$report = [ordered]@{
  schemaVersion = 1
  version = $script:LabVersion
  mode = $Mode
  startedAtUtc = $started.ToString('o')
  finishedAtUtc = [DateTime]::UtcNow.ToString('o')
  status = if ($errors.Count -eq 0) { 'passed' } else { 'blocked' }
  checks = $checks
  errors = @($errors)
  forbiddenDataSaved = $false
}
$logDir = Join-Path $script:LocalRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$reportPath = Join-Path $logDir ("acceptance-{0}.json" -f $started.ToString('yyyyMMdd-HHmmss'))
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$verificationDir = Join-Path $script:LabRoot 'verification\android-mcp-global\bootstrap'
New-Item -ItemType Directory -Force -Path $verificationDir | Out-Null
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $verificationDir 'latest.json') -Encoding UTF8
[ordered]@{ status = $report.status; mode = $Mode; report = $reportPath; checks = $checks; errors = @($errors) } | ConvertTo-Json -Depth 10
if ($errors.Count -gt 0) { exit 1 }
