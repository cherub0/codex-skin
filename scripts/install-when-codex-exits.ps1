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

function Stop-QQSkinTrayForReinstall {
  $trayScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'tray-qq-skin.ps1'))
  @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
      $_.CommandLine -and
      $_.ProcessId -ne $PID -and
      $_.CommandLine.IndexOf($trayScript, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    }) | ForEach-Object {
      Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
    }
}

while ((Get-Date) -lt $deadline) {
  if (-not (Test-CodexRunning)) {
    Stop-QQSkinTrayForReinstall
    & (Join-Path $PSScriptRoot 'install-qq-skin.ps1') -Port $Port
    & (Join-Path $PSScriptRoot 'start-qq-skin.ps1') -Port $Port
    exit 0
  }
  Start-Sleep -Seconds 3
}

throw "Timed out waiting for Codex to exit after $TimeoutMinutes minutes."
