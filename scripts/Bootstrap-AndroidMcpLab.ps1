[CmdletBinding()]
param(
  [ValidateSet('Auto','Validate')][string]$Mode = 'Auto',
  [switch]$Headless,
  [switch]$RegisterGlobalConfig = $true,
  [string]$OfflineBundle = ''
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

function Invoke-SdkManager([string[]]$Arguments) {
  $sdkmanager = Get-LabSdkManager
  if (-not $sdkmanager) { throw "Android sdkmanager was not found under $script:SdkRoot. Install Android SDK Command-line Tools from Android Studio, then rerun this command." }
  if ($script:JavaHome) { $env:JAVA_HOME = $script:JavaHome }
  $output = @(& $sdkmanager @Arguments 2>&1 | ForEach-Object { $_.ToString() })
  if ($LASTEXITCODE -ne 0) { throw "sdkmanager failed: $(($output | Select-Object -Last 8) -join ' ')" }
  return $output
}

function Ensure-SdkComponent([string]$Package, [scriptblock]$Present) {
  if (& $Present) { return 'present' }
  if ($Mode -eq 'Validate') { throw "Missing SDK component: $Package" }
  Write-Output "Installing SDK component: $Package"
  Invoke-SdkManager @('--install', $Package) | Out-Null
  if (-not (& $Present)) { throw "SDK component was not available after installation: $Package" }
  return 'installed'
}

function Ensure-CodexAvd {
  $names = @(Get-LabAvdNames)
  if ($names -contains 'codex_api36') { return 'present' }
  if ($Mode -eq 'Validate') { throw 'Codex AVD codex_api36 is missing.' }
  $avdmanager = Get-LabAvdManager
  if (-not $avdmanager) { throw "Android avdmanager was not found under $script:SdkRoot. Install Android SDK Command-line Tools first." }
  $package = 'system-images;android-36;google_apis;x86_64'
  $inputText = "no`n"
  $inputText | & $avdmanager create avd --name codex_api36 --package $package --force 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Unable to create codex_api36 AVD.' }
  $config = Join-Path $env:USERPROFILE '.android\avd\codex_api36.avd\config.ini'
  if (Test-Path -LiteralPath $config -PathType Leaf) {
    Add-Content -LiteralPath $config -Value @('snapshot.present=false','snapshot.save_on_exit=no','hw.keyboard=yes') -Encoding ASCII
  }
  if (-not ((Get-LabAvdNames) -contains 'codex_api36')) { throw 'codex_api36 was not listed after creation.' }
  return 'created'
}

Assert-LabHost
$sdkResults = [ordered]@{
  sdkRoot = $script:SdkRoot
  adb = (Test-Path -LiteralPath $script:Adb -PathType Leaf)
  emulator = (Test-Path -LiteralPath $script:Emulator -PathType Leaf)
  sdkmanager = [bool](Get-LabSdkManager)
  avdmanager = [bool](Get-LabAvdManager)
}
if (-not $sdkResults.adb -or -not $sdkResults.emulator) { throw "Android SDK host tools are missing under $script:SdkRoot. Install Android Studio SDK tools or set ANDROID_SDK_ROOT." }

if ($Mode -eq 'Auto' -and (Get-LabSdkManager)) {
  $licenseInput = ((1..40 | ForEach-Object { 'y' }) -join "`n") + "`n"
  $licenseInput | & (Get-LabSdkManager) --licenses 2>&1 | Out-Null
}

$components = [ordered]@{}
$components.platformTools = Ensure-SdkComponent 'platform-tools' { Test-Path (Join-Path $script:SdkRoot 'platform-tools\adb.exe') }
$components.emulator = Ensure-SdkComponent 'emulator' { Test-Path (Join-Path $script:SdkRoot 'emulator\emulator.exe') }
$components.platform36 = Ensure-SdkComponent 'platforms;android-36' { Test-Path (Join-Path $script:SdkRoot 'platforms\android-36\android.jar') }
$components.systemImage36 = Ensure-SdkComponent 'system-images;android-36;google_apis;x86_64' { Test-Path (Join-Path $script:SdkRoot 'system-images\android-36\google_apis\x86_64\package.xml') }
$components.buildTools = Ensure-SdkComponent 'build-tools;35.0.0' { Test-Path (Join-Path $script:SdkRoot 'build-tools\35.0.0\aapt2.exe') }
$avdResult = Ensure-CodexAvd

$registry = Discover-LabRegistry
if (-not ($registry.devices.deviceId -contains 'codex_api36')) { throw 'codex_api36 is not present in the Android MCP Lab registry.' }
if ($RegisterGlobalConfig) {
  if ($OfflineBundle) {
    & (Join-Path $PSScriptRoot 'Install-AndroidMcpLab.ps1') -OfflineBundle $OfflineBundle -RegisterGlobalConfig | Out-Null
  } else {
    & (Join-Path $PSScriptRoot 'Install-AndroidMcpLab.ps1') -RegisterGlobalConfig | Out-Null
  }
  $registry = Read-LabRegistry
}
$codex = Get-LabDevice 'codex_api36'
if (-not $codex.mcpEnabled) { throw "codex_api36 is disabled: $($codex.failure)" }
if ($Mode -eq 'Auto') {
  $null = Start-LabDevice -DeviceId 'codex_api36' -Headless:$Headless
  $codex = Get-LabDevice 'codex_api36'
}
[ordered]@{
  status = 'passed'
  mode = $Mode
  sdk = $sdkResults
  components = $components
  codexAvd = $avdResult
  defaultDeviceId = (Read-LabRegistry).defaultDeviceId
  codexDevice = $codex
  nextStep = 'Restart Codex, then call android_lab_devices.'
} | ConvertTo-Json -Depth 10
