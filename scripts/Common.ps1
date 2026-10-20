$ErrorActionPreference = 'Stop'

$script:LabRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$script:LabVersion = '0.1.3'
$script:LocalRoot = Join-Path $env:LOCALAPPDATA 'WhiteCodex\AndroidMcpLab'
$savedSdkRootPath = Join-Path $script:LocalRoot 'sdk-root.txt'
$savedSdkRoot = if (Test-Path -LiteralPath $savedSdkRootPath -PathType Leaf) { (Get-Content -Raw -LiteralPath $savedSdkRootPath).Trim() } else { '' }
$sdkCandidates = @(
  $env:ANDROID_SDK_ROOT,
  $env:ANDROID_HOME,
  $savedSdkRoot,
  (Join-Path $env:LOCALAPPDATA 'Android\Sdk'),
  (Join-Path $env:ProgramData 'Android\Sdk')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }
function Test-LabSdkCandidate([string]$Root) {
  if (-not $Root -or -not (Test-Path -LiteralPath $Root -PathType Container)) { return $false }
  return (Test-Path (Join-Path $Root 'platform-tools\adb.exe')) -and (Test-Path (Join-Path $Root 'emulator\emulator.exe'))
}
function Get-LabSdkScore([string]$Root) {
  if (-not (Test-LabSdkCandidate $Root)) { return -1 }
  $score = 10
  if (Test-Path (Join-Path $Root 'cmdline-tools\latest\bin\sdkmanager.bat')) { $score += 100 }
  if (Test-Path (Join-Path $Root 'system-images\android-36\google_apis\x86_64\package.xml')) { $score += 50 }
  if (Test-Path (Join-Path $Root 'platforms\android-36\android.jar')) { $score += 20 }
  return $score
}
$script:SdkRoot = ($sdkCandidates | Where-Object { Test-LabSdkCandidate $_ } | Sort-Object { Get-LabSdkScore $_ } -Descending | Select-Object -First 1)
if (-not $script:SdkRoot) { $script:SdkRoot = if ($sdkCandidates) { $sdkCandidates[0] } else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' } }
$script:Adb = Join-Path $script:SdkRoot 'platform-tools\adb.exe'
$script:Emulator = Join-Path $script:SdkRoot 'emulator\emulator.exe'
$script:AvdManager = Join-Path $script:SdkRoot 'cmdline-tools\latest\bin\avdmanager.bat'
$script:SdkManager = Join-Path $script:SdkRoot 'cmdline-tools\latest\bin\sdkmanager.bat'
$javaCandidates = @(
  $env:JAVA_HOME,
  (Join-Path $env:ProgramFiles 'Android\Android Studio\jbr')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) }
$script:JavaHome = if ($javaCandidates) { $javaCandidates[0] } else { '' }
$script:RegistryPath = Join-Path $script:LocalRoot 'registry.json'
$script:DeviceStateRoot = Join-Path $script:LocalRoot 'devices'
$script:LeaseRoot = Join-Path $script:LocalRoot 'leases'
$script:McpPackage = 'com.danielealbano.androidremotecontrolmcp'
$script:McpVersion = '1.11.1'
$script:McpDevicePort = 8080
$script:DefaultHostPort = 18080
$script:DefaultEmulatorPort = 16000
$script:BrokerPort = 18190
$script:McpApk = if ($env:ANDROID_MCP_APK) { $env:ANDROID_MCP_APK } else {
  Join-Path $env:LOCALAPPDATA 'WhiteCodex\AndroidMcp\cache\v1.11.1\android-remote-control-mcp-v1.11.1-foss-release.apk'
}
$script:McpApkSha256 = '39fbe125840ebd68eb8c6af7c509f1e8e65ed61f0890f841e29bf83830f3c581'
$script:McpCertificateSha256 = '2c44a5870e8a222bf790d45843fd57391e01f28212adea8c50ccce2d68dc2d4b'
$script:BridgeEntry = Join-Path $script:LabRoot 'bridge\launcher.mjs'
$script:FallbackRuntimeRoot = $script:LabRoot

function Assert-LabHost {
  foreach ($item in @($script:Adb, $script:Emulator)) {
    if (-not (Test-Path -LiteralPath $item -PathType Leaf)) { throw "Android tool was not found: $item" }
  }
  New-Item -ItemType Directory -Force -Path $script:LocalRoot, $script:DeviceStateRoot, $script:LeaseRoot | Out-Null
  if (Test-LabSdkCandidate $script:SdkRoot) {
    Set-Content -LiteralPath (Join-Path $script:LocalRoot 'sdk-root.txt') -Value $script:SdkRoot -Encoding UTF8
  }
}

function Get-LabSdkManager {
  $paths = @(
    $script:SdkManager,
    (Join-Path $script:SdkRoot 'cmdline-tools\bin\sdkmanager.bat')
  ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
  if ($paths) { return @($paths)[0] }
  return $null
}

function Get-LabAvdManager {
  $paths = @(
    $script:AvdManager,
    (Join-Path $script:SdkRoot 'cmdline-tools\bin\avdmanager.bat')
  ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
  if ($paths) { return @($paths)[0] }
  return $null
}

function Get-LabNodePath {
  $bundled = Join-Path $script:LabRoot 'runtime\node\node.exe'
  if (Test-Path -LiteralPath $bundled -PathType Leaf) { return $bundled }
  if ($env:ANDROID_LAB_NODE -and (Test-Path -LiteralPath $env:ANDROID_LAB_NODE -PathType Leaf)) { return $env:ANDROID_LAB_NODE }
  return (Get-Command node -ErrorAction Stop).Source
}

function Get-OrCreateLabBrokerToken([string]$StatePath) {
  if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
    $state = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
    if ($state.tokenDpapi) { return Unprotect-LabText ([string]$state.tokenDpapi) }
  }
  $bytes = [byte[]]::new(32); [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  try { $token = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_') } finally { [Array]::Clear($bytes, 0, $bytes.Length) }
  [ordered]@{ schemaVersion = 1; purpose = 'android-mcp-lab-broker'; tokenDpapi = Protect-LabText $token; createdAtUtc = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding UTF8
  return $token
}

function ConvertTo-SafeId([string]$Value) {
  $id = ($Value.ToLowerInvariant() -replace '[^a-z0-9_-]+', '-') -replace '^-+', '' -replace '-+$', ''
  if ([string]::IsNullOrWhiteSpace($id)) { throw "Cannot derive a device id from $Value" }
  if ($id.Length -gt 48) { $id = $id.Substring(0, 48).TrimEnd('-') }
  return $id
}

function Read-LabRegistry {
  if (-not (Test-Path -LiteralPath $script:RegistryPath -PathType Leaf)) { return $null }
  $value = Get-Content -Raw -LiteralPath $script:RegistryPath | ConvertFrom-Json
  if ([int]$value.schemaVersion -ne 1 -or $null -eq $value.devices) { throw 'Android MCP Lab registry is invalid.' }
  return $value
}

function Write-LabRegistry([object]$Registry) {
  $temp = "$script:RegistryPath.$PID.tmp"
  New-Item -ItemType Directory -Force -Path $script:LocalRoot | Out-Null
  try {
    $Registry | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $script:RegistryPath -Force
  } finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
}

function Get-LabAvdNames {
  @(& $script:Emulator -list-avds 2>$null | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ })
}

function Get-LabDevicePolicy([string]$AvdName) {
  $lower = $AvdName.ToLowerInvariant()
  if ($lower -eq 'codex_api36') {
    return [pscustomobject]@{ credentialPolicy = 'no-credentials'; dataPolicy = 'destructive-test-allowed' }
  }
  if ($lower -eq 'dsh_api36') {
    return [pscustomobject]@{ credentialPolicy = 'contains-credentials'; dataPolicy = 'preserve' }
  }
  if ($lower -match 'test|openminis|api26') {
    return [pscustomobject]@{ credentialPolicy = 'no-credentials'; dataPolicy = 'test' }
  }
  return [pscustomobject]@{ credentialPolicy = 'no-credentials'; dataPolicy = 'preserve' }
}

function Get-LabControlMode([string]$AvdName) {
  if ($AvdName.ToLowerInvariant() -eq 'codex_api36') { return 'codex-exclusive' }
  return 'manual-reuse'
}

function Get-LabAvdAbi([string]$AvdName) {
  $avdRoot = Join-Path $env:USERPROFILE ".android\avd\$AvdName.avd"
  $config = Join-Path $avdRoot 'config.ini'
  if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { return '' }
  $line = Get-Content -LiteralPath $config | Where-Object { $_ -match '^abi.type=' } | Select-Object -First 1
  if ($line -match '^abi.type=(.+)$') { return $Matches[1].Trim() }
  return ''
}

function Get-LabAvdApiLevel([string]$AvdName) {
  $avdRoot = Join-Path $env:USERPROFILE ".android\avd\$AvdName.avd"
  $config = Join-Path $avdRoot 'config.ini'
  if (-not (Test-Path -LiteralPath $config -PathType Leaf)) { return 0 }
  $line = Get-Content -LiteralPath $config | Where-Object { $_ -match '^image.sysdir.1=' } | Select-Object -First 1
  if ($line -match 'android-(\d+)') { return [int]$Matches[1] }
  if ($AvdName -match 'api(\d+)') { return [int]$Matches[1] }
  return 0
}

function Get-NextHostPort([object[]]$Devices) {
  $used = @($Devices | ForEach-Object { [int]$_.hostPort })
  $port = $script:DefaultHostPort
  while ($used -contains $port) { $port++ }
  return $port
}

function Get-NextEmulatorPort([int[]]$UsedPorts) {
  $port = $script:DefaultEmulatorPort
  while (($UsedPorts -contains $port) -or -not (Test-LabEmulatorPortPairAvailable -ConsolePort $port)) {
    $port += 2
    if ($port -ge 49000) { throw 'No available loopback emulator port pair was found.' }
  }
  return $port
}

function Discover-LabRegistry {
  $existing = Read-LabRegistry
  $oldById = @{}
  if ($existing) { foreach ($device in $existing.devices) { $oldById[[string]$device.deviceId] = $device } }
  $devices = [Collections.Generic.List[object]]::new()
  $avdNames = @(Get-LabAvdNames | Sort-Object { if ($_ -eq 'codex_api36') { 0 } elseif ($_ -eq 'dsh_api36') { 1 } else { 2 } }, { $_ })
  $usedEmulatorPorts = @()
  foreach ($avd in $avdNames) {
    $id = ConvertTo-SafeId $avd
    $policy = Get-LabDevicePolicy $avd
    $old = $oldById[$id]
    $reservedHostPorts = @($oldById.GetEnumerator() | Where-Object { $_.Key -ne $id } | ForEach-Object { if ($_.Value.hostPort) { [int]$_.Value.hostPort } })
    $hostPort = if ($id -eq 'dsh_api36') { 18080 } elseif ($old -and $reservedHostPorts -notcontains [int]$old.hostPort) { [int]$old.hostPort } else {
      $candidate = $script:DefaultHostPort
      while (($reservedHostPorts -contains $candidate) -or (@($devices | ForEach-Object { [int]$_.hostPort }) -contains $candidate)) { $candidate++ }
      $candidate
    }
    $slug = if ($id -eq 'dsh_api36') { 'dsh36' } elseif ($id -eq 'codex_api36') { 'codex36' } else { "lab_$id" }
    $abi = Get-LabAvdAbi $avd
    $apiLevel = Get-LabAvdApiLevel $avd
    $unsupportedAbi = ([Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE') -match 'AMD64|x86') -and $abi -and $abi -notmatch 'x86_64'
    $unsupportedApi = $apiLevel -gt 0 -and $apiLevel -lt 33
    $enabled = -not ($unsupportedAbi -or $unsupportedApi)
    $oldEmulatorPort = if ($old -and $old.emulatorPort) { [int]$old.emulatorPort } else { 0 }
    $emulatorPort = if ($oldEmulatorPort -gt 0 -and $usedEmulatorPorts -notcontains $oldEmulatorPort -and (Test-LabEmulatorPortPairAvailable -ConsolePort $oldEmulatorPort)) { $oldEmulatorPort } else { Get-NextEmulatorPort $usedEmulatorPorts }
    if ($usedEmulatorPorts -notcontains $emulatorPort) { $usedEmulatorPorts += $emulatorPort }
    $devices.Add([ordered]@{
      deviceId = $id
      avdName = $avd
      deviceSlug = $slug
      devicePort = $script:McpDevicePort
      hostPort = $hostPort
      emulatorPort = $emulatorPort
      emulatorAdbPort = $emulatorPort + 1
      abi = $abi
      apiLevel = $apiLevel
      mcpPackage = $script:McpPackage
      upstreamVersion = $script:McpVersion
      apkSha256 = $script:McpApkSha256
      certificateSha256 = $script:McpCertificateSha256
      credentialPolicy = $policy.credentialPolicy
      dataPolicy = $policy.dataPolicy
      mcpEnabled = $enabled
      controlMode = Get-LabControlMode $avd
      reservedFor = if ($id -eq 'codex_api36') { 'android_lab' } else { $null }
      registeredAtUtc = if ($old) { [string]$old.registeredAtUtc } else { [DateTime]::UtcNow.ToString('o') }
      status = if ($enabled) { 'offline' } else { 'failed' }
      failure = if ($unsupportedAbi) { "Unsupported host/AVD ABI combination: $abi" } elseif ($unsupportedApi) { "Pinned MCP APK requires API 33+; AVD is API $apiLevel" } else { $null }
    })
  }
  if ($devices.Count -eq 0) { throw 'No Android AVDs were found.' }
  $default = if ($devices.deviceId -contains 'codex_api36') { 'codex_api36' } elseif ($existing.defaultDeviceId -and ($devices.deviceId -contains $existing.defaultDeviceId)) { $existing.defaultDeviceId } elseif ($devices.deviceId -contains 'dsh_api36') { 'dsh_api36' } else { $devices[0].deviceId }
  $registry = [ordered]@{ schemaVersion = 1; installVersion = $script:LabVersion; defaultDeviceId = $default; devices = @($devices) }
  Write-LabRegistry $registry
  return $registry
}

function Protect-LabText([string]$Value) {
  $secure = ConvertTo-SecureString -String $Value -AsPlainText -Force
  ConvertFrom-SecureString -SecureString $secure
}

function Unprotect-LabText([string]$Ciphertext) {
  $secure = ConvertTo-SecureString -String $Ciphertext
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Get-LabDevice([string]$DeviceId) {
  $registry = Read-LabRegistry
  if (-not $registry) { throw 'Android MCP Lab registry is missing; run discover first.' }
  $device = @($registry.devices | Where-Object { $_.deviceId -eq $DeviceId }) | Select-Object -First 1
  if (-not $device) { throw "Unknown Android MCP device: $DeviceId" }
  return $device
}

function Invoke-LabAdb([string[]]$Arguments, [switch]$AllowFailure) {
  $output = @(& $script:Adb @Arguments 2>&1 | ForEach-Object { $_.ToString() })
  if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) { throw "adb failed: $(($output | Select-Object -Last 3) -join ' ')" }
  return $output
}

function Test-LabHostPortAvailable([int]$Port) {
  $client = [Net.Sockets.TcpClient]::new()
  try {
    $task = $client.ConnectAsync('127.0.0.1', $Port)
    if (-not $task.Wait(250)) { return $true }
    return -not $client.Connected
  } catch { return $true } finally { $client.Dispose() }
}

function Test-LabTcpPortBindable([int]$Port) {
  $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
  try {
    $listener.Start()
    return $true
  } catch {
    return $false
  } finally {
    $listener.Stop()
  }
}

function Test-LabEmulatorPortPairAvailable([int]$ConsolePort) {
  return (Test-LabTcpPortBindable -Port $ConsolePort) -and (Test-LabTcpPortBindable -Port ($ConsolePort + 1))
}

function Test-LabAllowedSerial([string]$Serial, [string]$ExpectedLoopbackSerial = '') {
  return ($Serial -match '^emulator-\d+$') -or ($ExpectedLoopbackSerial -and $Serial -eq $ExpectedLoopbackSerial)
}

function Get-LabSerial([string]$AvdName, [int]$AdbPort = 0, [switch]$AllowMissing) {
  $lines = @(Invoke-LabAdb @('devices'))
  $expectedLoopbackSerial = if ($AdbPort -gt 0) { "127.0.0.1:$AdbPort" } else { '' }
  if ($expectedLoopbackSerial -and -not ($lines | Where-Object { $_ -match "^$([regex]::Escape($expectedLoopbackSerial))\s+device\b" })) {
    Invoke-LabAdb @('connect', $expectedLoopbackSerial) -AllowFailure | Out-Null
    $lines = @(Invoke-LabAdb @('devices'))
  }
  foreach ($line in @($lines | Where-Object {
    $_ -match '^(\S+)\s+device\b' -and (Test-LabAllowedSerial -Serial $Matches[1] -ExpectedLoopbackSerial $expectedLoopbackSerial)
  })) {
    $serial = ($line -split '\s+')[0]
    $name = ((Invoke-LabAdb @('-s', $serial, 'shell', 'getprop', 'ro.boot.qemu.avd_name') -AllowFailure) -join '').Trim()
    if (-not $name -and $serial -match '^emulator-\d+$') {
      $name = @((Invoke-LabAdb @('-s', $serial, 'emu', 'avd', 'name') -AllowFailure) | Where-Object { $_ -and $_ -ne 'OK' })[0]
    }
    if ($name -eq $AvdName) { return $serial }
  }
  if ($AllowMissing) { return $null }
  throw "AVD $AvdName is not running."
}

function Get-LabAvdLockProcess([object]$Device) {
  $pidPath = Join-Path $env:USERPROFILE ".android\avd\$($Device.avdName).avd\hardware-qemu.ini.lock\pid"
  if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) { return $null }
  $rawPid = (Get-Content -Raw -LiteralPath $pidPath -ErrorAction SilentlyContinue).Trim()
  if ($rawPid -notmatch '^\d+$') { return $null }
  $process = Get-Process -Id ([int]$rawPid) -ErrorAction SilentlyContinue
  if (-not $process -or $process.ProcessName -notmatch '^(emulator|qemu)') { return $null }
  return $process
}

function Get-LabEmulatorLogPaths([object]$Device) {
  $logDirectory = Join-Path $script:LocalRoot 'logs'
  New-Item -ItemType Directory -Force -Path $logDirectory | Out-Null
  return [pscustomobject]@{
    stdout = Join-Path $logDirectory "emulator-$($Device.deviceId).stdout.log"
    stderr = Join-Path $logDirectory "emulator-$($Device.deviceId).stderr.log"
  }
}

function Get-LabEmulatorFailureSummary([object]$Logs) {
  $lines = foreach ($path in @($Logs.stderr, $Logs.stdout)) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      Get-Content -LiteralPath $path -Tail 20 -ErrorAction SilentlyContinue
    }
  }
  $summary = (($lines | Where-Object { $_ -and $_.Trim() } | Select-Object -Last 12) -join ' | ')
  $summary = $summary -replace 'Bearer\s+\S+', 'Bearer [redacted]' -replace '(?i)(token|secret|key)=[^\s]+', '$1=[redacted]'
  if ($summary.Length -gt 1200) { $summary = $summary.Substring($summary.Length - 1200) }
  return $summary
}

function Get-LabEmulatorVersion {
  try {
    $line = @(& $script:Emulator -version 2>&1 | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }) | Select-Object -First 1
    if ($line) { return $line }
  } catch { }
  return 'unknown'
}

function Test-LabGuestBootCompletedFromLogs([object]$Logs) {
  foreach ($path in @($Logs.stderr, $Logs.stdout)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $matches = Select-String -LiteralPath $path -Pattern '(?i)boot completed|sys\.boot_completed\s*[=:]\s*1|boot_completed' -Quiet -ErrorAction SilentlyContinue
    if ($matches) { return $true }
  }
  return $false
}

function Get-LabStartupPhase([object]$Device, [bool]$BootCompleted, [bool]$AdbRegistered, [bool]$CompanionReady, [object]$AvdProcess, [bool]$GuestBootFromLogs = $false) {
  if (-not $Device.mcpEnabled) { return 'disabled' }
  if ($CompanionReady) { return 'ready' }
  if ($BootCompleted -and $AdbRegistered) { return 'companion_not_ready' }
  if ($GuestBootFromLogs -and -not $AdbRegistered -and $AvdProcess) { return 'adb_unavailable' }
  if ($AdbRegistered -or $AvdProcess) {
    if ($BootCompleted) { return 'guest_boot' }
    return 'starting'
  }
  return 'offline'
}

function Get-LabStatusFailure([object]$Device, [bool]$BootCompleted, [bool]$AdbRegistered, [bool]$CompanionReady, [bool]$GuestBootFromLogs) {
  if (-not $Device.mcpEnabled) { return $Device.failure }
  if ($GuestBootFromLogs -and -not $AdbRegistered) { return 'ADB transport is not registered after guest boot.' }
  if ($BootCompleted -and $AdbRegistered -and -not $CompanionReady) { return 'MCP companion is not ready.' }
  return $Device.failure
}

function Remove-StaleLabAvdLocks([object]$Device) {
  $avdRoot = Join-Path $env:USERPROFILE ".android\avd\$($Device.avdName).avd"
  $lockDirectory = Join-Path $avdRoot 'hardware-qemu.ini.lock'
  if (-not (Test-Path -LiteralPath $lockDirectory -PathType Container)) { return }
  if (Get-LabAvdLockProcess -Device $Device) { return }

  Remove-Item -LiteralPath $lockDirectory -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Join-Path $avdRoot 'multiinstance.lock') -Force -ErrorAction SilentlyContinue
}

function Start-LabAvdProcess([object]$Device, [switch]$Headless) {
  if (-not $Device.mcpEnabled) { throw "Android AVD $($Device.avdName) is disabled: $($Device.failure)" }
  $adbPort = if ($Device.emulatorAdbPort) { [int]$Device.emulatorAdbPort } else { [int]$Device.emulatorPort + 1 }
  $running = Get-LabSerial -AvdName $Device.avdName -AdbPort $adbPort -AllowMissing
  if ($running) {
    $boot = ((Invoke-LabAdb @('-s', $running, 'shell', 'getprop', 'sys.boot_completed') -AllowFailure) -join '').Trim()
    return [pscustomobject]@{ status = if ($boot -eq '1') { 'running' } else { 'starting' }; serial = $running; processId = $null; bootCompleted = $boot -eq '1' }
  }
  $active = Get-LabAvdLockProcess -Device $Device
  if ($active) {
    return [pscustomobject]@{ status = 'starting'; serial = $null; processId = $active.Id; bootCompleted = $false }
  }
  Remove-StaleLabAvdLocks -Device $Device
  $emulatorPort = if ($Device.emulatorPort) { [int]$Device.emulatorPort } else { $script:DefaultEmulatorPort }
  $adbPort = if ($Device.emulatorAdbPort) { [int]$Device.emulatorAdbPort } else { $emulatorPort + 1 }
  if (-not (Test-LabEmulatorPortPairAvailable -ConsolePort $emulatorPort)) {
    throw "Emulator ports $emulatorPort/$adbPort are unavailable; run Android Lab discovery to refresh the registry."
  }
  $args = @(
    '-avd', $Device.avdName,
    '-no-snapshot',
    '-no-snapshot-save',
    '-no-boot-anim',
    '-ports', "$emulatorPort,$adbPort",
    '-no-direct-adb',
    '-adb-path', $script:Adb
  )
  if ($Headless) { $args += @('-no-window', '-no-audio', '-gpu', 'swiftshader_indirect') }
  $logs = Get-LabEmulatorLogPaths -Device $Device
  $params = @{
    FilePath = $script:Emulator
    ArgumentList = $args
    PassThru = $true
    RedirectStandardOutput = $logs.stdout
    RedirectStandardError = $logs.stderr
  }
  if ($Headless) { $params.WindowStyle = 'Hidden' }
  $previousSdkRoot = $env:ANDROID_SDK_ROOT
  $previousAndroidHome = $env:ANDROID_HOME
  try {
    $env:ANDROID_SDK_ROOT = $script:SdkRoot
    $env:ANDROID_HOME = $script:SdkRoot
    $process = Start-Process @params
  } finally {
    if ($null -eq $previousSdkRoot) { Remove-Item Env:ANDROID_SDK_ROOT -ErrorAction SilentlyContinue } else { $env:ANDROID_SDK_ROOT = $previousSdkRoot }
    if ($null -eq $previousAndroidHome) { Remove-Item Env:ANDROID_HOME -ErrorAction SilentlyContinue } else { $env:ANDROID_HOME = $previousAndroidHome }
  }
  Start-Sleep -Milliseconds 1500
  if ($process.HasExited) {
    $summary = Get-LabEmulatorFailureSummary -Logs $logs
    throw "AVD $($Device.avdName) exited during launch (exit code $($process.ExitCode)); logs: $($logs.stderr), $($logs.stdout); summary: $summary"
  }
  return [pscustomobject]@{ status = 'starting'; serial = $null; processId = $process.Id; bootCompleted = $false }
}

function Start-LabAvd([object]$Device, [switch]$Headless) {
  $launch = Start-LabAvdProcess -Device $Device -Headless:$Headless
  if ($launch.serial -and $launch.bootCompleted) { return $launch.serial }
  $deadline = [DateTime]::UtcNow.AddSeconds(240)
  do {
    $adbPort = if ($Device.emulatorAdbPort) { [int]$Device.emulatorAdbPort } else { [int]$Device.emulatorPort + 1 }
    $serial = Get-LabSerial -AvdName $Device.avdName -AdbPort $adbPort -AllowMissing
    if ($serial) {
      $boot = ((Invoke-LabAdb @('-s', $serial, 'shell', 'getprop', 'sys.boot_completed') -AllowFailure) -join '').Trim()
      if ($boot -eq '1') { return $serial }
    }
    $process = if ($launch.processId) { Get-Process -Id $launch.processId -ErrorAction SilentlyContinue } else { Get-LabAvdLockProcess -Device $Device }
    if (-not $process -and -not $serial) {
      $logs = Get-LabEmulatorLogPaths -Device $Device
      $summary = Get-LabEmulatorFailureSummary -Logs $logs
      throw "AVD $($Device.avdName) exited before boot; logs: $($logs.stderr), $($logs.stdout); summary: $summary"
    }
    Start-Sleep -Seconds 2
  } while ([DateTime]::UtcNow -lt $deadline)
  throw "AVD $($Device.avdName) did not boot within 240 seconds."
}

function Set-LabMcpConfiguration([object]$Device, [string]$Serial, [string]$Token) {
  $component = "$script:McpPackage/com.danielealbano.androidremotecontrolmcp.services.mcp.AdbConfigReceiver"
  $safeToken = $Token.Replace("'", "'\\''")
  $toolPermissions = '{"disabled_tools":[],"disabled_params":{}}'
  $command = @(
    'am broadcast'
    '-a com.danielealbano.androidremotecontrolmcp.ADB_CONFIGURE'
    "-n $component"
    "--es bearer_token '$safeToken'"
    '--ez bearer_token_enabled true'
    '--ez oauth_enabled false'
    "--es public_url_override ''"
    '--ez https_enabled false'
    '--ez tunnel_enabled false'
    "--es binding_address '127.0.0.1'"
    "--ei port $script:McpDevicePort"
    '--ez auto_start_on_boot false'
    '--ei file_size_limit_mb 50'
    '--ez allow_http_downloads false'
    '--ez allow_unverified_https_certs false'
    '--ei download_timeout_seconds 60'
    "--es device_slug '$($Device.deviceSlug)'"
    "--es tool_permissions '$toolPermissions'"
    '>/dev/null'
  ) -join ' '
  $psi = [Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $script:Adb; $psi.UseShellExecute = $false; $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  foreach ($arg in @('-s', $Serial, 'shell')) { $psi.ArgumentList.Add($arg) }
  $proc = [Diagnostics.Process]::Start($psi)
  $proc.StandardInput.WriteLine($command); $proc.StandardInput.Close(); $null = $proc.StandardOutput.ReadToEnd(); $null = $proc.StandardError.ReadToEnd(); $proc.WaitForExit()
  if ($proc.ExitCode -ne 0) { throw "MCP configuration failed for $($Device.deviceId)." }
}

function Test-LabMcpDevicePort([string]$Serial) {
  if (-not $Serial) { return $false }
  $lines = @(Invoke-LabAdb @('-s', $Serial, 'shell', 'ss', '-ltn') -AllowFailure)
  return [bool]($lines | Where-Object { $_ -match "(?:^|:)$script:McpDevicePort\b" })
}

function Wait-LabMcpDevicePort([string]$Serial, [bool]$Listening, [int]$TimeoutSeconds = 15) {
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  do {
    if ((Test-LabMcpDevicePort -Serial $Serial) -eq $Listening) { return $true }
    Start-Sleep -Milliseconds 250
  } while ([DateTime]::UtcNow -lt $deadline)
  return $false
}

function Test-LabMcpAccessibility([string]$Serial) {
  if (-not $Serial) { return $false }
  $component = "$script:McpPackage/com.danielealbano.androidremotecontrolmcp.services.accessibility.McpAccessibilityService"
  $enabled = ((Invoke-LabAdb @('-s', $Serial, 'shell', 'settings', 'get', 'secure', 'enabled_accessibility_services') -AllowFailure) -join '').Trim()
  if ($enabled -notmatch [regex]::Escape($component)) { return $false }
  $state = (Invoke-LabAdb @('-s', $Serial, 'shell', 'dumpsys', 'accessibility') -AllowFailure) -join "`n"
  return $state -match [regex]::Escape($component) -and $state -match 'Bound services:'
}

function Wait-LabMcpAccessibility([string]$Serial, [int]$TimeoutSeconds = 30) {
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  do {
    if (Test-LabMcpAccessibility -Serial $Serial) { return $true }
    Start-Sleep -Milliseconds 500
  } while ([DateTime]::UtcNow -lt $deadline)
  return $false
}

function Ensure-LabMcpInstalled([object]$Device, [string]$Serial) {
  if (-not (Test-Path -LiteralPath $script:McpApk -PathType Leaf)) { throw "Pinned MCP APK not found: $script:McpApk" }
  $hash = (Get-FileHash -LiteralPath $script:McpApk -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($hash -ne $script:McpApkSha256) { throw 'Pinned MCP APK SHA-256 changed.' }
  Invoke-LabAdb @('-s', $Serial, 'install', '-r', $script:McpApk) | Out-Null
  foreach ($permission in @('android.permission.POST_NOTIFICATIONS','android.permission.CAMERA','android.permission.RECORD_AUDIO','android.permission.ACCESS_FINE_LOCATION','android.permission.ACCESS_COARSE_LOCATION','android.permission.NEARBY_WIFI_DEVICES','android.permission.READ_MEDIA_IMAGES','android.permission.READ_MEDIA_VIDEO','android.permission.READ_MEDIA_AUDIO')) {
    Invoke-LabAdb @('-s', $Serial, 'shell', 'pm', 'grant', $script:McpPackage, $permission) -AllowFailure | Out-Null
  }
  $access = "$script:McpPackage/com.danielealbano.androidremotecontrolmcp.services.accessibility.McpAccessibilityService"
  Invoke-LabAdb @('-s', $Serial, 'shell', 'settings', 'put', 'secure', 'enabled_accessibility_services', $access) | Out-Null
  Invoke-LabAdb @('-s', $Serial, 'shell', 'settings', 'put', 'secure', 'accessibility_enabled', '1') | Out-Null
  $listener = "$script:McpPackage/com.danielealbano.androidremotecontrolmcp.services.notifications.McpNotificationListenerService"
  Invoke-LabAdb @('-s', $Serial, 'shell', 'cmd', 'notification', 'allow_listener', $listener) -AllowFailure | Out-Null
  $forwards = @(Invoke-LabAdb @('-s', $Serial, 'forward', '--list') -AllowFailure)
  $exact = $forwards | Where-Object { $_ -match "^$([regex]::Escape($Serial))\s+tcp:$($Device.hostPort)\s+tcp:$script:McpDevicePort$" }
  if (-not $exact) {
    $conflict = $forwards | Where-Object { $_ -match "\stcp:$($Device.hostPort)\s" }
    if ($conflict) { throw "Android MCP host port $($Device.hostPort) is already forwarded to another endpoint." }
    if (-not (Test-LabHostPortAvailable -Port ([int]$Device.hostPort))) { throw "Android MCP host port $($Device.hostPort) is already occupied." }
    Invoke-LabAdb @('-s', $Serial, 'forward', '--no-rebind', "tcp:$($Device.hostPort)", "tcp:$script:McpDevicePort") | Out-Null
  }
}

function Get-OrCreateLabToken([object]$Device) {
  $statePath = Join-Path $script:DeviceStateRoot "$($Device.deviceId).json"
  if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    if ($state.tokenDpapi) { return Unprotect-LabText $state.tokenDpapi }
  }
  if ($Device.deviceId -eq 'dsh_api36') {
    $legacyPath = Join-Path $env:LOCALAPPDATA ('WhiteCodex\AndroidMcp\dsh_' + 'api36.json')
    if (Test-Path -LiteralPath $legacyPath -PathType Leaf) {
      $legacy = Get-Content -Raw -LiteralPath $legacyPath | ConvertFrom-Json
      if ($legacy.tokenDpapi) {
        $legacyToken = Unprotect-LabText ([string]$legacy.tokenDpapi)
        $state = [ordered]@{ schemaVersion = 1; deviceId = $Device.deviceId; avdName = $Device.avdName; deviceSlug = $Device.deviceSlug; hostPort = $Device.hostPort; tokenDpapi = Protect-LabText $legacyToken; createdAtUtc = [DateTime]::UtcNow.ToString('o'); compatibilitySource = 'legacy-dsh36' }
        $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
        return $legacyToken
      }
    }
  }
  $bytes = [byte[]]::new(32); [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  try { $token = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_') } finally { [Array]::Clear($bytes, 0, $bytes.Length) }
  $state = [ordered]@{ schemaVersion = 1; deviceId = $Device.deviceId; avdName = $Device.avdName; deviceSlug = $Device.deviceSlug; hostPort = $Device.hostPort; tokenDpapi = Protect-LabText $token; createdAtUtc = [DateTime]::UtcNow.ToString('o') }
  $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
  return $token
}

function Start-LabDevice([string]$DeviceId, [switch]$Headless) {
  $device = Get-LabDevice $DeviceId
  $serial = Start-LabAvd -Device $device -Headless:$Headless
  $token = Get-OrCreateLabToken $device
  Ensure-LabMcpInstalled -Device $device -Serial $serial
  if ($DeviceId -ne 'dsh_api36') {
    Invoke-LabAdb @('-s', $serial, 'shell', 'am', 'start', '-W', '-n', "$script:McpPackage/com.danielealbano.androidremotecontrolmcp.services.mcp.AdbServiceTrampolineActivity", '--es', 'action', 'stop') -AllowFailure | Out-Null
    Invoke-LabAdb @('-s', $serial, 'shell', 'am', 'force-stop', $script:McpPackage) -AllowFailure | Out-Null
    if (-not (Wait-LabMcpDevicePort -Serial $serial -Listening:$false -TimeoutSeconds 15)) {
      throw "MCP service on $($device.deviceId) did not release port $script:McpDevicePort after stop."
    }
  }
  Set-LabMcpConfiguration -Device $device -Serial $serial -Token $token
  $access = "$script:McpPackage/com.danielealbano.androidremotecontrolmcp.services.accessibility.McpAccessibilityService"
  Invoke-LabAdb @('-s', $serial, 'shell', 'settings', 'put', 'secure', 'enabled_accessibility_services', $access) | Out-Null
  Invoke-LabAdb @('-s', $serial, 'shell', 'settings', 'put', 'secure', 'accessibility_enabled', '1') | Out-Null
  $listener = "$script:McpPackage/com.danielealbano.androidremotecontrolmcp.services.notifications.McpNotificationListenerService"
  Invoke-LabAdb @('-s', $serial, 'shell', 'cmd', 'notification', 'allow_listener', $listener) -AllowFailure | Out-Null
  Invoke-LabAdb @('-s', $serial, 'shell', 'am', 'start', '-W', '-n', "$script:McpPackage/com.danielealbano.androidremotecontrolmcp.services.mcp.AdbServiceTrampolineActivity", '--es', 'action', 'start') | Out-Null
  if (-not (Wait-LabMcpDevicePort -Serial $serial -Listening:$true -TimeoutSeconds 30)) {
    throw "MCP service on $($device.deviceId) did not listen on port $script:McpDevicePort after start."
  }
  if (-not (Wait-LabMcpAccessibility -Serial $serial -TimeoutSeconds 30)) {
    throw "Accessibility service on $($device.deviceId) did not become ready."
  }
  $forwards = @(Invoke-LabAdb @('-s', $serial, 'forward', '--list') -AllowFailure)
  if (-not ($forwards | Where-Object { $_ -match "^$([regex]::Escape($serial))\s+tcp:$($device.hostPort)\s+tcp:$script:McpDevicePort$" })) {
    Invoke-LabAdb @('-s', $serial, 'forward', '--no-rebind', "tcp:$($device.hostPort)", "tcp:$script:McpDevicePort") | Out-Null
  }
  $lastSeen = [DateTime]::UtcNow.ToString('o')
  $registry = Read-LabRegistry
  foreach ($entry in $registry.devices) {
    if ($entry.deviceId -eq $DeviceId) {
      $entry | Add-Member -NotePropertyName serial -NotePropertyValue $serial -Force
      $entry | Add-Member -NotePropertyName status -NotePropertyValue 'ready' -Force
      $entry | Add-Member -NotePropertyName lastSeenAtUtc -NotePropertyValue $lastSeen -Force
    }
  }
  Write-LabRegistry $registry
  return $device
}

function Stop-LabDevice([string]$DeviceId) {
  $device = Get-LabDevice $DeviceId
  $adbPort = if ($device.emulatorAdbPort) { [int]$device.emulatorAdbPort } else { [int]$device.emulatorPort + 1 }
  $serial = Get-LabSerial -AvdName $device.avdName -AdbPort $adbPort -AllowMissing
  if ($serial) {
    Invoke-LabAdb @('-s', $serial, 'shell', 'am', 'start', '-W', '-n', "$script:McpPackage/com.danielealbano.androidremotecontrolmcp.services.mcp.AdbServiceTrampolineActivity", '--es', 'action', 'stop') -AllowFailure | Out-Null
    Invoke-LabAdb @('-s', $serial, 'forward', '--remove', "tcp:$($device.hostPort)") -AllowFailure | Out-Null
    if ($device.dataPolicy -ne 'preserve') { Invoke-LabAdb @('-s', $serial, 'emu', 'kill') -AllowFailure | Out-Null }
  } elseif ($device.dataPolicy -ne 'preserve') {
    $process = Get-LabAvdLockProcess -Device $device
    if ($process) { Stop-Process -Id $process.Id -Force -ErrorAction Stop }
  }
}
