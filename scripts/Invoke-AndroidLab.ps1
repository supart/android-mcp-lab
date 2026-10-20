[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidateSet('discover','status','start','up','down','doctor','runtime')][string]$Action,
  [string]$DeviceId = '',
  [switch]$Headless
)
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-LabHost

if ($Action -eq 'discover') {
  $registry = Discover-LabRegistry
  Write-Output ($registry | ConvertTo-Json -Depth 8)
  exit 0
}

$registry = Read-LabRegistry
if (-not $registry) { $registry = Discover-LabRegistry }
$targets = if ($DeviceId) { @($DeviceId) } else { @($registry.devices | ForEach-Object { $_.deviceId }) }

switch ($Action) {
  'start' {
    if ($env:ANDROID_LAB_INTERNAL_CALL -ne '1') { throw 'The start action is internal and cannot be called directly.' }
    if (-not $DeviceId) { throw 'start requires -DeviceId.' }
    $device = Get-LabDevice $DeviceId
    $state = Start-LabAvdProcess -Device $device -Headless:$Headless
    $logs = Get-LabEmulatorLogPaths -Device $device
    $adbRegistered = [bool]$state.serial
    $guestBootFromLogs = Test-LabGuestBootCompletedFromLogs $logs
    $startupPhase = Get-LabStartupPhase -Device $device -BootCompleted ([bool]$state.bootCompleted) -AdbRegistered:$adbRegistered -CompanionReady:$false -AvdProcess $null -GuestBootFromLogs:$guestBootFromLogs
    [ordered]@{ device = $device; status = $state.status; startupPhase = $startupPhase; serial = $state.serial; processId = $state.processId; bootCompleted = $state.bootCompleted; adbRegistered = $adbRegistered; companionReady = $false; logs = [ordered]@{ stdout = $logs.stdout; stderr = $logs.stderr }; failure = $null } | ConvertTo-Json -Compress -Depth 8
  }
  'up' {
    foreach ($id in $targets) { $device = Start-LabDevice -DeviceId $id -Headless:$Headless; Write-Output "Android MCP ready: $($device.deviceId) ($($device.avdName)) hostPort=$($device.hostPort)" }
  }
  'runtime' {
    if ($env:ANDROID_LAB_INTERNAL_CALL -ne '1') { throw 'The runtime action is internal and cannot be called directly.' }
    if (-not $DeviceId) { throw 'runtime requires -DeviceId.' }
    $device = Start-LabDevice -DeviceId $DeviceId -Headless:$Headless
    $statePath = Join-Path $script:DeviceStateRoot "$DeviceId.json"
    $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    [ordered]@{ device = $device; token = Unprotect-LabText ([string]$state.tokenDpapi) } | ConvertTo-Json -Compress -Depth 8
  }
  'down' {
    foreach ($id in $targets) { Stop-LabDevice -DeviceId $id }
    [ordered]@{ status = 'stopped'; deviceIds = @($targets) } | ConvertTo-Json -Compress -Depth 3
  }
  'status' {
    $current = Read-LabRegistry
    $selected = if ($DeviceId) { @($current.devices | Where-Object { $_.deviceId -eq $DeviceId }) } else { @($current.devices) }
    $emulatorVersion = Get-LabEmulatorVersion
    $result = foreach ($device in $selected) {
      $adbPort = if ($device.emulatorAdbPort) { [int]$device.emulatorAdbPort } else { [int]$device.emulatorPort + 1 }
      $serial = Get-LabSerial -AvdName $device.avdName -AdbPort $adbPort -AllowMissing
      $bootCompleted = $false
      if ($serial) {
        $bootCompleted = (((Invoke-LabAdb @('-s', $serial, 'shell', 'getprop', 'sys.boot_completed') -AllowFailure) -join '').Trim()) -eq '1'
      }
      $avdProcess = Get-LabAvdLockProcess -Device $device
      $logs = Get-LabEmulatorLogPaths -Device $device
      $guestBootFromLogs = Test-LabGuestBootCompletedFromLogs $logs
      $adbRegistered = [bool]$serial
      $companionReady = $false
      if ($adbRegistered -and $bootCompleted) {
        $companionReady = (Test-LabMcpDevicePort -Serial $serial) -and (Test-LabMcpAccessibility -Serial $serial)
      }
      $startupPhase = Get-LabStartupPhase -Device $device -BootCompleted:$bootCompleted -AdbRegistered:$adbRegistered -CompanionReady:$companionReady -AvdProcess $avdProcess -GuestBootFromLogs:$guestBootFromLogs
      [ordered]@{
        deviceId = $device.deviceId
        avdName = $device.avdName
        serial = $serial
        hostPort = $device.hostPort
        credentialPolicy = $device.credentialPolicy
        dataPolicy = $device.dataPolicy
        controlMode = if ($device.controlMode) { $device.controlMode } else { 'manual-reuse' }
        reservedFor = $device.reservedFor
        sharedDeviceRisk = if ($device.controlMode -eq 'codex-exclusive') { 'low' } elseif ($device.credentialPolicy -eq 'contains-credentials') { 'high' } else { 'manual-coordination-required' }
        status = if (-not $device.mcpEnabled) { 'failed' } elseif ($bootCompleted) { 'running' } elseif ($serial -or $avdProcess) { 'starting' } else { 'offline' }
        startupPhase = $startupPhase
        bootCompleted = $bootCompleted
        adbRegistered = $adbRegistered
        companionReady = $companionReady
        processId = if ($avdProcess) { $avdProcess.Id } else { $null }
        emulatorPid = if ($avdProcess) { $avdProcess.Id } else { $null }
        emulatorPort = if ($device.emulatorPort) { [int]$device.emulatorPort } else { $null }
        emulatorAdbPort = $adbPort
        sdkRoot = $script:SdkRoot
        emulatorVersion = $emulatorVersion
        logs = [ordered]@{ stdout = $logs.stdout; stderr = $logs.stderr }
        failure = Get-LabStatusFailure -Device $device -BootCompleted:$bootCompleted -AdbRegistered:$adbRegistered -CompanionReady:$companionReady -GuestBootFromLogs:$guestBootFromLogs
      }
    }
    # The Node broker parses the final output line; keep supervisor status on one line.
    $result | ConvertTo-Json -Compress -Depth 5
  }
  'doctor' {
    $current = Read-LabRegistry
    [ordered]@{ status = 'passed'; sdkRoot = $script:SdkRoot; adb = Test-Path $script:Adb; emulator = Test-Path $script:Emulator; registry = $script:RegistryPath; devices = @($current.devices).Count; mcpApk = Test-Path $script:McpApk } | ConvertTo-Json
  }
}
