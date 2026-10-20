[CmdletBinding()]
param([switch]$DryRun)
. (Join-Path $PSScriptRoot 'Common.ps1')
if (-not $DryRun) { Assert-LabHost }

$node = Get-LabNodePath
$esbuild = Join-Path $script:LabRoot 'node_modules\esbuild\bin\esbuild'
if (-not (Test-Path -LiteralPath $esbuild -PathType Leaf)) {
  throw "Repository-local esbuild was not found: $esbuild. Run npm ci first."
}
& $node $esbuild (Join-Path $script:LabRoot 'bridge\src\broker.ts') '--bundle' '--platform=node' '--format=esm' ("--outfile={0}" -f (Join-Path $script:LabRoot 'dist\broker.mjs'))
if ($LASTEXITCODE -ne 0) { throw 'Failed to bundle Android Lab broker.' }
& $node $esbuild (Join-Path $script:LabRoot 'bridge\src\proxy.ts') '--bundle' '--platform=node' '--format=esm' ("--outfile={0}" -f (Join-Path $script:LabRoot 'dist\proxy.mjs'))
if ($LASTEXITCODE -ne 0) { throw 'Failed to bundle Android Lab proxy.' }
if ($DryRun) {
  Write-Output 'Android MCP Lab bundle dry run passed.'
  return
}

$artifactRoot = Join-Path $script:LabRoot 'artifacts'
$version = $script:LabVersion
$stage = Join-Path $artifactRoot "staging\Android-Mcp-Lab-$version"
$releaseRoot = Join-Path $artifactRoot $version
$manifestPath = Join-Path $releaseRoot "Android-Mcp-Lab-$version-manifest.json"
$zip = Join-Path $releaseRoot "Android-Mcp-Lab-$version.zip"
$shaPath = Join-Path $releaseRoot "Android-Mcp-Lab-$version.sha256"
foreach ($releaseFile in @($manifestPath, $zip, $shaPath)) {
  if (Test-Path -LiteralPath $releaseFile) {
    throw "Release asset already exists and will not be overwritten: $releaseFile. Update the version before creating a new release."
  }
}
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
New-Item -ItemType Directory -Force -Path $releaseRoot | Out-Null

foreach ($directory in @('bridge','dist','scripts','assets','registry','skill')) { Copy-Item -LiteralPath (Join-Path $script:LabRoot $directory) -Destination (Join-Path $stage $directory) -Recurse -Force }
foreach ($file in @('LICENSE.md','SECURITY.md','CONTRIBUTING.md','UPSTREAM.md','THIRD_PARTY_NOTICES.md')) {
  Copy-Item -LiteralPath (Join-Path $script:LabRoot $file) -Destination (Join-Path $stage $file) -Force
}
Copy-Item -LiteralPath (Join-Path $script:LabRoot 'README.md') -Destination (Join-Path $stage 'README.md') -Force
Copy-Item -LiteralPath (Join-Path $script:LabRoot 'START_HERE_FOR_CODEX.md') -Destination (Join-Path $stage 'START_HERE_FOR_CODEX.md') -Force
New-Item -ItemType Directory -Force -Path (Join-Path $stage 'runtime\node') | Out-Null
Copy-Item -LiteralPath $node -Destination (Join-Path $stage 'runtime\node\node.exe') -Force
$apkTarget = Join-Path $stage 'android-remote-control-mcp-v1.11.1-foss-release.apk'
Copy-Item -LiteralPath $script:McpApk -Destination $apkTarget -Force

$installDoc = Join-Path $script:LabRoot 'docs\INSTALL.md'
if (Test-Path -LiteralPath $installDoc) { Copy-Item -LiteralPath $installDoc -Destination (Join-Path $stage 'INSTALL.md') -Force }
$manifest = [ordered]@{
  schemaVersion = 1
  product = 'Android MCP Lab'
  version = $version
  upstreamVersion = $script:McpVersion
  apkFile = 'android-remote-control-mcp-v1.11.1-foss-release.apk'
  apkSha256 = (Get-FileHash -LiteralPath $apkTarget -Algorithm SHA256).Hash.ToLowerInvariant()
  certificateSha256 = $script:McpCertificateSha256
  upstreamCommit = '2b87d46e91421295cd4893185b694612ec2c94d1'
  skillIncluded = $true
  rollbackVersion = '0.1.2'
  nodeVersion = (& (Join-Path $stage 'runtime\node\node.exe') --version).Trim()
  generatedAtUtc = [DateTime]::UtcNow.ToString('o')
  containsCredentials = $false
  containsAvdSnapshots = $false
  supportedHost = 'Windows 10/11 x64'
  sdkStrategy = 'Reuse Android Studio or environment SDK; install fixed API 36 components with sdkmanager when missing'
  defaultAvdName = 'codex_api36'
  defaultApiLevel = 36
  defaultAbi = 'x86_64'
  networkSdkBootstrap = $true
  requiresCodexRestart = $true
  androidStudioGeminiSharedDefaultAvd = $false
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
Get-FileHash -LiteralPath $zip -Algorithm SHA256 | ForEach-Object { "$($_.Hash.ToLowerInvariant())  Android-Mcp-Lab-$version.zip" } | Set-Content -LiteralPath $shaPath -Encoding ASCII
Write-Output "Bundle: $zip"
Write-Output "SHA256: $((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash)"
