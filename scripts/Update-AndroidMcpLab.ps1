[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Manifest)
. (Join-Path $PSScriptRoot 'Common.ps1')
if (-not (Test-Path -LiteralPath $Manifest -PathType Leaf)) { throw "Manifest not found: $Manifest" }
$manifestValue = Get-Content -Raw -LiteralPath $Manifest | ConvertFrom-Json
if ([string]$manifestValue.upstreamVersion -ne $script:McpVersion) { throw 'Manifest upstream version is not the approved fixed version.' }
if ([string]$manifestValue.apkSha256 -ne $script:McpApkSha256) { throw 'Manifest APK hash does not match the approved fixed binary.' }
Write-Output 'Manifest matches the approved Android MCP release. No automatic upgrade was performed.'
