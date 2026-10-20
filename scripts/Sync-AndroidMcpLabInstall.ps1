[CmdletBinding()]
param(
  [string]$InstallRoot = ''
)

$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$expectedRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'WhiteCodex\AndroidMcpLab\install\0.1.3'))
$targetRoot = if ($InstallRoot) { [IO.Path]::GetFullPath($InstallRoot) } else { $expectedRoot }
if ($targetRoot -ne $expectedRoot) { throw "Refusing to sync unexpected install root: $targetRoot" }
if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) { throw "Install root does not exist: $targetRoot" }

# Remove only nested directories created by an earlier directory-copy attempt.
foreach ($nested in @('bridge\bridge', 'dist\dist', 'scripts\scripts', 'registry\registry', 'tests\tests')) {
  $path = Join-Path $targetRoot $nested
  if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
}

foreach ($name in @('bridge', 'dist', 'scripts', 'registry', 'tests', 'skill')) {
  $source = Join-Path $sourceRoot $name
  $target = Join-Path $targetRoot $name
  Copy-Item -Path (Join-Path $source '*') -Destination $target -Recurse -Force
}

foreach ($file in @('README.md','START_HERE_FOR_CODEX.md','LICENSE.md','SECURITY.md','CONTRIBUTING.md','UPSTREAM.md','THIRD_PARTY_NOTICES.md')) {
  $source = Join-Path $sourceRoot $file
  if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-Item -LiteralPath $source -Destination (Join-Path $targetRoot $file) -Force }
}

[ordered]@{
  status = 'synced'
  installRoot = $targetRoot
  sourceRoot = $sourceRoot
  runtime = (Test-Path -LiteralPath (Join-Path $targetRoot 'dist\bridge\src\session-lifecycle.js'))
  supervisor = (Test-Path -LiteralPath (Join-Path $targetRoot 'scripts\Invoke-AndroidLab.ps1'))
} | ConvertTo-Json -Compress
