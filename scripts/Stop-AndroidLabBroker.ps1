[CmdletBinding()]
param()
. (Join-Path $PSScriptRoot 'Common.ps1')
if (-not (Test-Path -LiteralPath (Join-Path $script:LocalRoot 'broker-runtime.json') -PathType Leaf)) { exit 0 }
$runtime = Get-Content -Raw -LiteralPath (Join-Path $script:LocalRoot 'broker-runtime.json') | ConvertFrom-Json
if ($runtime.pid) {
  $process = Get-Process -Id ([int]$runtime.pid) -ErrorAction SilentlyContinue
  if ($process) {
    $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($runtime.pid)" -ErrorAction SilentlyContinue).CommandLine
    if ($commandLine -and $commandLine -match '(?:WhiteCodex[\\/]AndroidMcpLab|android-mcp-lab).*broker\.mjs') { Stop-Process -Id ([int]$runtime.pid) -Force -ErrorAction SilentlyContinue }
  }
}
Remove-Item -LiteralPath (Join-Path $script:LocalRoot 'broker-runtime.json') -Force -ErrorAction SilentlyContinue
Write-Output 'Android MCP Lab broker stopped.'
