[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-LabHost
& (Join-Path $PSScriptRoot 'Install-AndroidMcpLab.ps1') -RegisterGlobalConfig
& (Join-Path $PSScriptRoot 'Invoke-AndroidLab.ps1') -Action doctor
