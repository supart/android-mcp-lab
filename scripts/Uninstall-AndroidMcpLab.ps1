[CmdletBinding()]
param([switch]$RemoveLocalState)
. (Join-Path $PSScriptRoot 'Common.ps1')

& (Join-Path $PSScriptRoot 'Stop-AndroidLabBroker.ps1') | Out-Null
$registry = Read-LabRegistry
if ($registry) {
  foreach ($device in $registry.devices) {
    $adbPort = if ($device.emulatorAdbPort) { [int]$device.emulatorAdbPort } else { [int]$device.emulatorPort + 1 }
    $serial = Get-LabSerial -AvdName $device.avdName -AdbPort $adbPort -AllowMissing
    if ($serial) {
      Invoke-LabAdb @('-s', $serial, 'forward', '--remove', "tcp:$($device.hostPort)") -AllowFailure | Out-Null
      Invoke-LabAdb @('-s', $serial, 'uninstall', $script:McpPackage) -AllowFailure | Out-Null
    }
  }
}

$configPath = Join-Path $env:USERPROFILE '.codex\config.toml'
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
  $content = Get-Content -Raw -LiteralPath $configPath
  $content = [regex]::Replace($content, '(?ms)^# BEGIN WHITE_CODEX_ANDROID_LAB.*?# END WHITE_CODEX_ANDROID_LAB\s*', '')
  Set-Content -LiteralPath $configPath -Value ($content.TrimEnd() + "`r`n") -Encoding UTF8
}

$installParent = Join-Path $script:LocalRoot 'install'
if (Test-Path -LiteralPath $installParent -PathType Container) {
  Get-ChildItem -LiteralPath $installParent -Directory | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
}
if ($RemoveLocalState -and (Test-Path -LiteralPath $script:LocalRoot)) { Remove-Item -LiteralPath $script:LocalRoot -Recurse -Force }
Write-Output 'Android MCP Lab global configuration and companion APK removed. AVDs, SDK and project data were not deleted.'
