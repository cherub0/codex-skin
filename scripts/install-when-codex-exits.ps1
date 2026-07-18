[CmdletBinding()]
param(
  [int]$Port = 9335,
  [string]$NodePath,
  [int]$TimeoutMinutes = 30
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)

if ($NodePath) {
  $env:CODEX_QQ_SKIN_NODE = $NodePath
}

function Test-CodexRunning {
  @(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      "$($_.ExecutablePath)" -like '*\OpenAI.Codex_*\app\ChatGPT.exe' -and
      "$($_.CommandLine)" -notmatch '\s--type='
    }).Count -gt 0
}

while ((Get-Date) -lt $deadline) {
  if (-not (Test-CodexRunning)) {
    & (Join-Path $PSScriptRoot 'install-qq-skin.ps1') -Port $Port
    & (Join-Path $PSScriptRoot 'start-qq-skin.ps1') -Port $Port
    exit 0
  }
  Start-Sleep -Seconds 3
}

throw "Timed out waiting for Codex to exit after $TimeoutMinutes minutes."
