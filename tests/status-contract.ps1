$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\Common.ps1')

$device = [pscustomobject]@{ mcpEnabled = $true; failure = $null }
$active = [pscustomobject]@{ Id = 4242 }

if (-not (Test-LabAllowedSerial -Serial 'emulator-5564')) { throw 'emulator serial was rejected' }
if (-not (Test-LabAllowedSerial -Serial '127.0.0.1:16001' -ExpectedLoopbackSerial '127.0.0.1:16001')) { throw 'loopback emulator serial was rejected' }
if (Test-LabAllowedSerial -Serial 'physical-serial') { throw 'physical serial was accepted' }
if ((Get-LabStartupPhase -Device $device -BootCompleted $false -AdbRegistered $false -CompanionReady $false -AvdProcess $active -GuestBootFromLogs $false) -ne 'starting') { throw 'active emulator was not classified as starting' }
if ((Get-LabStartupPhase -Device $device -BootCompleted $false -AdbRegistered $false -CompanionReady $false -AvdProcess $active -GuestBootFromLogs $true) -ne 'adb_unavailable') { throw 'guest boot without ADB was not classified as adb_unavailable' }
if ((Get-LabStartupPhase -Device $device -BootCompleted $true -AdbRegistered $true -CompanionReady $false -AvdProcess $active -GuestBootFromLogs $false) -ne 'companion_not_ready') { throw 'booted ADB device without companion was not classified as companion_not_ready' }
if ((Get-LabStartupPhase -Device $device -BootCompleted $true -AdbRegistered $true -CompanionReady $true -AvdProcess $active -GuestBootFromLogs $false) -ne 'ready') { throw 'ready device was not classified as ready' }
if ((Get-LabStartupPhase -Device $device -BootCompleted $false -AdbRegistered $false -CompanionReady $false -AvdProcess $null -GuestBootFromLogs $true) -ne 'offline') { throw 'stale boot log incorrectly changed offline state' }
if ((Get-LabStatusFailure -Device $device -BootCompleted $false -AdbRegistered $false -CompanionReady $false -GuestBootFromLogs $true) -ne 'ADB transport is not registered after guest boot.') { throw 'ADB failure summary mismatch' }

Write-Output 'Android Lab status contract passed.'
