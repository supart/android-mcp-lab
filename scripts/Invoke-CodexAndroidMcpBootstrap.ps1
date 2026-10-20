[CmdletBinding()]
param(
  [ValidateSet('Auto','Validate')][string]$Mode = 'Validate',
  [string]$OfflineBundle = '',
  [switch]$RegisterGlobalConfig = $true,
  [switch]$Headless
)

$ErrorActionPreference = 'Stop'
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$install = Join-Path $root 'scripts\Install-AndroidMcpLab.ps1'
$bootstrap = Join-Path $root 'scripts\Bootstrap-AndroidMcpLab.ps1'
$acceptance = Join-Path $root 'scripts\Invoke-AndroidLabAcceptance.ps1'
$bundleRoot = if ($OfflineBundle) { [IO.Path]::GetFullPath($OfflineBundle) } else { $root }

if ($OfflineBundle -and -not (Test-Path -LiteralPath $bundleRoot -PathType Container)) { throw "Offline bundle directory was not found: $bundleRoot" }

$installArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$install)
if ($OfflineBundle) { $installArgs += @('-OfflineBundle', $bundleRoot) }
if ($RegisterGlobalConfig) { $installArgs += '-RegisterGlobalConfig' }
$null = & $pwsh @installArgs 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Global Lab installation failed.' }

$bootstrapArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$bootstrap,'-Mode',$Mode)
if ($OfflineBundle) { $bootstrapArgs += @('-OfflineBundle', $bundleRoot) }
if ($RegisterGlobalConfig) { $bootstrapArgs += '-RegisterGlobalConfig' } else { $bootstrapArgs += '-RegisterGlobalConfig:$false' }
if ($Headless) { $bootstrapArgs += '-Headless' }
$null = & $pwsh @bootstrapArgs 2>&1
$bootstrapExit = $LASTEXITCODE

$acceptanceArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$acceptance,'-Mode','Config')
$null = & $pwsh @acceptanceArgs 2>&1
$acceptanceExit = $LASTEXITCODE

$skillPath = Join-Path $env:USERPROFILE '.codex\skills\ty-android-mcp'
$installPath = Join-Path $env:LOCALAPPDATA 'WhiteCodex\AndroidMcpLab\install\0.1.3'
[ordered]@{
  schemaVersion = 1
  product = 'Android MCP Lab'
  version = '0.1.3'
  status = if ($bootstrapExit -eq 0 -and $acceptanceExit -eq 0) { 'passed' } else { 'blocked' }
  installRoot = $installPath
  skillPath = $skillPath
  skillInstalled = Test-Path -LiteralPath (Join-Path $skillPath 'SKILL.md')
  configAcceptance = ($acceptanceExit -eq 0)
  bootstrap = ($bootstrapExit -eq 0)
  requiresCodexRestart = $true
  nextStep = 'Restart Codex, then call android_lab_devices; do not use direct ADB UI commands.'
  failureClass = if ($bootstrapExit -ne 0) { 'bootstrap_failed' } elseif ($acceptanceExit -ne 0) { 'config_acceptance_failed' } else { $null }
} | ConvertTo-Json -Depth 8
