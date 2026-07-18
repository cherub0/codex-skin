[CmdletBinding()]
param(
  [int]$Port = 9335,
  [switch]$NoShortcuts
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
$SkillRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')

$operationLock = Enter-QQSkinOperationLock
try {
  Assert-QQSkinPort -Port $Port
  $null = Get-QQSkinNodeRuntime
  $registeredInstalls = @(Get-QQSkinRegisteredCodexInstalls)
  if ($registeredInstalls.Count -eq 0) {
    throw 'The official OpenAI.Codex Store package is not installed or its identity cannot be validated.'
  }
  foreach ($registeredCodex in $registeredInstalls) {
    if ((Get-QQSkinCodexProcesses -Codex $registeredCodex).Count -gt 0) {
      throw 'Close Codex before installing Retro QQ Skin so config.toml cannot change during the transaction.'
    }
  }

  $StateRoot = Join-Path $env:LOCALAPPDATA 'CodexQQSkin'
  $themePaths = Get-QQSkinThemePaths -StateRoot $StateRoot
  Ensure-QQSkinManagedDirectory -Path $themePaths.Root -Root $themePaths.Root
  $StatePath = Join-Path $StateRoot 'state.json'
  $existingState = Read-QQSkinState -Path $StatePath
  $savedPathCandidate = Get-QQSkinCodexStatePathCandidate -State $existingState
  $savedCodex = Resolve-QQSkinCodexInstallFromState -State $existingState -RegisteredInstalls $registeredInstalls
  if ($null -ne $savedPathCandidate -and $null -eq $savedCodex -and
    (Get-QQSkinCodexProcesses -Codex $savedPathCandidate).Count -gt 0) {
    throw 'The saved Codex path is still running but no longer matches a registered Store package. Close it manually before installing.'
  }
  if (Test-QQSkinTrayActive) {
    throw 'Exit the Codex Retro QQ Skin tray before reinstalling so every shortcut can move to the new runtime safely.'
  }
  $engine = Install-QQSkinRuntimeEngine -SkillRoot $SkillRoot -StateRoot $StateRoot
  $null = Initialize-QQSkinThemeStore -SkillRoot $engine.Root -StateRoot $StateRoot
  $ConfigPath = Join-Path $HOME '.codex\config.toml'
  $BackupPath = Join-Path $StateRoot 'config.before-qq-skin.toml'
  Install-QQSkinBaseTheme -ConfigPath $ConfigPath -BackupPath $BackupPath

  if (-not $NoShortcuts) {
    $shell = New-Object -ComObject WScript.Shell
    $desktop = [Environment]::GetFolderPath('Desktop')
    $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    $startScript = $engine.Start
    $restoreScript = $engine.Restore
    $trayScript = $engine.Tray
    $portArgument = if ($PortExplicit) { " -Port $Port" } else { '' }

    foreach ($folder in @($desktop, $startMenu)) {
      $shortcut = $shell.CreateShortcut((Join-Path $folder 'Codex Retro QQ Skin.lnk'))
      $shortcut.TargetPath = $powershell
      $shortcut.Arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$startScript`"$portArgument -PromptRestart"
      $shortcut.WorkingDirectory = $engine.Root
      $shortcut.Description = 'Launch the official Codex app with Codex Retro QQ Skin'
      $shortcut.Save()
    }

    $restore = $shell.CreateShortcut((Join-Path $desktop 'Codex Retro QQ Skin - Restore.lnk'))
    $restore.TargetPath = $powershell
    $restore.Arguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$restoreScript`"$portArgument -RestoreBaseTheme -PromptRestart"
    $restore.WorkingDirectory = $engine.Root
    $restore.Description = 'Restore the official Codex appearance and close the CDP session'
    $restore.Save()

    foreach ($folder in @($desktop, $startMenu)) {
      $tray = $shell.CreateShortcut((Join-Path $folder 'Codex Retro QQ Skin - Tray.lnk'))
      $tray.TargetPath = $powershell
      $tray.Arguments = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File `"$trayScript`"$portArgument"
      $tray.WorkingDirectory = $engine.Root
      $tray.Description = 'Open Codex Retro QQ Skin status and theme controls in the system tray'
      $tray.Save()
    }
    Start-Process -FilePath $powershell -ArgumentList `
      "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File `"$trayScript`"$portArgument" `
      -WindowStyle Hidden | Out-Null
  }

  if ($NoShortcuts) {
    Write-Host "Codex Retro QQ Skin base theme installed at $($engine.Root). Run $($engine.Start) to launch it."
  } else {
    Write-Host 'Codex Retro QQ Skin installed. The launch shortcut asks before restarting an open Codex window.'
  }
} finally {
  Exit-QQSkinOperationLock -Mutex $operationLock
}
