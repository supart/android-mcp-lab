[CmdletBinding()]
param(
  [string]$DeviceId = ''
)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-LabHost
$runtimeRoot = if ($env:ANDROID_LAB_RUNTIME_ROOT) { $env:ANDROID_LAB_RUNTIME_ROOT } else { $script:LabRoot }
$node = if ($env:ANDROID_LAB_NODE) { $env:ANDROID_LAB_NODE } else { (Get-Command node -ErrorAction Stop).Source }
$env:ANDROID_LAB_REGISTRY_PATH = $script:RegistryPath
$env:ANDROID_LAB_LEASE_DIR = $script:LeaseRoot
$env:ANDROID_LAB_DEFAULT_DEVICE = if ($DeviceId) { $DeviceId } else { $env:ANDROID_LAB_DEFAULT_DEVICE }
$env:ANDROID_LAB_EXPECTED_COMPANION_TOOL_COUNT = '57'
$env:NODE_PATH = Join-Path $runtimeRoot 'node_modules'
$entry = Join-Path $script:LabRoot 'bridge\launcher.mjs'
if (-not (Test-Path -LiteralPath $entry -PathType Leaf)) { throw "Android MCP Lab launcher was not found: $entry" }
$psi = [Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $node
$psi.WorkingDirectory = $runtimeRoot
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $false
$psi.RedirectStandardOutput = $false
$psi.RedirectStandardError = $false
foreach ($argument in @($entry)) { $psi.ArgumentList.Add($argument) }
$process = [Diagnostics.Process]::Start($psi)
$process.WaitForExit()
exit $process.ExitCode
