[CmdletBinding()]
param(
  [string]$OfflineBundle = '',
  [switch]$RegisterGlobalConfig,
  [switch]$DiscoverOnly,
  [switch]$PrepareDevices
)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-LabHost

function Install-CodexSkill([string]$Root) {
  $source = Join-Path $Root 'skill\ty-android-mcp'
  $target = Join-Path $env:USERPROFILE '.codex\skills\ty-android-mcp'
  if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    return [ordered]@{ status = 'missing'; source = $source; target = $target }
  }
  $backup = $null
  if (Test-Path -LiteralPath $target -PathType Container) {
    $backupRoot = Join-Path $script:LocalRoot 'skill-backups'
    $backup = Join-Path $backupRoot ("ty-android-mcp-{0}" -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    Copy-Item -LiteralPath $target -Destination $backup -Recurse -Force
    Remove-Item -LiteralPath $target -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $target | Out-Null
  Get-ChildItem -LiteralPath $source -Force | Copy-Item -Destination $target -Recurse -Force
  return [ordered]@{ status = 'installed'; source = $source; target = $target; backup = $backup }
}

$sourceRoot = if ($OfflineBundle) { [IO.Path]::GetFullPath($OfflineBundle) } else { $script:LabRoot }
$installRoot = Join-Path $script:LocalRoot (Join-Path 'install' $script:LabVersion)
$bundleApk = Join-Path $sourceRoot 'android-remote-control-mcp-v1.11.1-foss-release.apk'
if (-not (Test-Path -LiteralPath $bundleApk -PathType Leaf)) { $bundleApk = Join-Path $sourceRoot 'assets\android-remote-control-mcp-v1.11.1-foss-release.apk' }

if ($OfflineBundle) {
  if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) { throw "Offline bundle directory was not found: $sourceRoot" }
  if (Test-Path -LiteralPath $installRoot -PathType Container) {
    Remove-Item -LiteralPath $installRoot -Recurse -Force
  }
  New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
  Get-ChildItem -LiteralPath $sourceRoot -Force | Where-Object { $_.Name -notin @('state','verification','artifacts') } | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $installRoot -Recurse -Force
  }
  if (Test-Path -LiteralPath $bundleApk -PathType Leaf) {
    $cache = Join-Path $env:LOCALAPPDATA 'WhiteCodex\AndroidMcp\cache\v1.11.1'
    New-Item -ItemType Directory -Force -Path $cache | Out-Null
    Copy-Item -LiteralPath $bundleApk -Destination (Join-Path $cache 'android-remote-control-mcp-v1.11.1-foss-release.apk') -Force
  }
  $script:LabRoot = $installRoot
  $script:RegistryPath = Join-Path $script:LocalRoot 'registry.json'
  $script:DeviceStateRoot = Join-Path $script:LocalRoot 'devices'
  $script:LeaseRoot = Join-Path $script:LocalRoot 'leases'
  $script:McpApk = Join-Path $env:LOCALAPPDATA 'WhiteCodex\AndroidMcp\cache\v1.11.1\android-remote-control-mcp-v1.11.1-foss-release.apk'
}

$registry = Discover-LabRegistry
$skill = Install-CodexSkill -Root $sourceRoot
if ($DiscoverOnly) { Write-Output ($registry | ConvertTo-Json -Depth 8); exit 0 }

if ($PrepareDevices) {
  foreach ($device in $registry.devices | Where-Object { $_.mcpEnabled }) {
    $null = Start-LabDevice -DeviceId $device.deviceId
    Write-Output "Android MCP prepared: $($device.deviceId)"
  }
}

if ($RegisterGlobalConfig) {
  $configPath = Join-Path $env:USERPROFILE '.codex\config.toml'
  if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw "Codex global config was not found at $configPath" }
  $content = Get-Content -Raw -LiteralPath $configPath
  $begin = '# BEGIN WHITE_CODEX_ANDROID_LAB'; $end = '# END WHITE_CODEX_ANDROID_LAB'
  $content = [regex]::Replace($content, "(?ms)^$([regex]::Escape($begin)).*?$([regex]::Escape($end))\s*", '')
  $configBackup = "$configPath.android-lab.$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')).bak"
  Copy-Item -LiteralPath $configPath -Destination $configBackup -Force
  $slash = [string][char]92
  $root = $script:LabRoot.Replace($slash, $slash + $slash)
  $sdkRoot = $script:SdkRoot.Replace($slash, $slash + $slash)
  $node = if (Test-Path -LiteralPath (Join-Path $script:LabRoot 'runtime\node\node.exe')) { (Join-Path $script:LabRoot 'runtime\node\node.exe').Replace($slash, $slash + $slash) } else { 'node.exe' }
  $block = @"
$begin
[mcp_servers.android_lab]
command = "$node"
args = ["$root\\bridge\\launcher.mjs"]
cwd = "$root"
required = true
startup_timeout_sec = 300
tool_timeout_sec = 300
default_tools_approval_mode = "approve"
[mcp_servers.android_lab.env]
ANDROID_SDK_ROOT = "$sdkRoot"
ANDROID_HOME = "$sdkRoot"
$end
"@
  ($content.TrimEnd() + "`r`n`r`n" + $block.Trim() + "`r`n") | Set-Content -LiteralPath $configPath -Encoding UTF8
  Write-Output "Registered android_lab in $configPath; backup=$configBackup"
}

Write-Output "Android MCP Lab registry ready: $script:RegistryPath"
Write-Output ($skill | ConvertTo-Json -Compress)
Write-Output ($registry | ConvertTo-Json -Depth 8)
