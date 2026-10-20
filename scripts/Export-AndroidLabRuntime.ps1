[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-LabHost
$registry = Read-LabRegistry
if (-not $registry) { $registry = Discover-LabRegistry }
$requested = [string]$env:ANDROID_LAB_DEFAULT_DEVICE
$default = if ($requested -and @($registry.devices.deviceId) -contains $requested) { $requested } else { [string]$registry.defaultDeviceId }
if (-not $default) { throw 'No default Android MCP device is registered.' }
$statePresence = [ordered]@{}
foreach ($device in @((Read-LabRegistry).devices)) {
  $statePath = Join-Path $script:DeviceStateRoot "$($device.deviceId).json"
  $statePresence[$device.deviceId] = Test-Path -LiteralPath $statePath -PathType Leaf
}
[ordered]@{
  registryPath = $script:RegistryPath
  leaseDirectory = $script:LeaseRoot
  defaultDeviceId = $default
  installVersion = $script:LabVersion
  expectedCompanionToolCount = 57
  expectedExposedToolCount = 63
  deviceCount = @($registry.devices).Count
  statePresence = $statePresence
} | ConvertTo-Json -Compress -Depth 5
