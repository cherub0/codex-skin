[CmdletBinding()]
param(
  [int]$Port = 9335,
  [switch]$Uninstall,
  [switch]$RestoreBaseTheme,
  [switch]$RecoverConfigBackup,
  [switch]$PromptRestart,
  [switch]$ForceRestart,
  [switch]$NoRelaunch
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')

function Stop-QQSkinTrayProcess {
  $trayScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'tray-qq-skin.ps1'))
  try {
    $processes = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" `
      -ErrorAction Stop
    foreach ($process in $processes) {
      if ($process.ProcessId -eq $PID -or -not $process.CommandLine) { continue }
      if ($process.CommandLine.IndexOf($trayScript, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
      }
    }
  } catch {
    Write-Warning "Could not close the Retro QQ Skin tray automatically: $($_.Exception.Message)"
  }
}

$operationLock = Enter-QQSkinOperationLock
try {
  if ($RestoreBaseTheme -and $RecoverConfigBackup) {
    throw 'Choose either -RestoreBaseTheme or -RecoverConfigBackup, not both.'
  }
  Assert-QQSkinPort -Port $Port

  $StateRoot = Join-Path $env:LOCALAPPDATA 'CodexQQSkin'
  $themePaths = Get-QQSkinThemePaths -StateRoot $StateRoot
  Ensure-QQSkinManagedDirectory -Path $themePaths.Root -Root $themePaths.Root
  $StatePath = Join-Path $StateRoot 'state.json'
  $state = Read-QQSkinState -Path $StatePath
  if (-not $PortExplicit -and $null -ne $state -and $state.port) {
    $Port = [int]$state.port
    Assert-QQSkinPort -Port $Port
  }

  $currentCodex = $null
  try { $currentCodex = Get-QQSkinCodexInstall } catch { Write-Warning $_.Exception.Message }
  $savedPathCandidate = Get-QQSkinCodexStatePathCandidate -State $state
  $savedCodex = Get-QQSkinCodexInstallFromState -State $state
  $candidateMatchesCurrent = [bool]($null -ne $savedPathCandidate -and $null -ne $currentCodex -and
    (Test-QQSkinPathEqual -Left $savedPathCandidate.PackageRoot -Right $currentCodex.PackageRoot) -and
    (Test-QQSkinPathEqual -Left $savedPathCandidate.Executable -Right $currentCodex.Executable))
  if ($null -ne $savedPathCandidate -and $null -eq $savedCodex -and -not $candidateMatchesCurrent) {
    $unverifiedSavedRunning = (Get-QQSkinCodexProcesses -Codex $savedPathCandidate).Count -gt 0
    $unverifiedSavedOwnsPort = Test-QQSkinCodexPortOwner -Port $Port -Codex $savedPathCandidate
    if ($unverifiedSavedRunning -or $unverifiedSavedOwnsPort) {
      throw 'The saved Codex path is still active but no longer matches a registered OpenAI.Codex package. Close it manually; state and configuration were preserved.'
    }
  }
  $savedIsDifferent = [bool]($null -ne $savedCodex -and $null -ne $currentCodex -and
    -not (Test-QQSkinPathEqual -Left $savedCodex.Executable -Right $currentCodex.Executable))
  $currentRunning = $null -ne $currentCodex -and (Get-QQSkinCodexProcesses -Codex $currentCodex).Count -gt 0
  $savedRunning = $null -ne $savedCodex -and (Get-QQSkinCodexProcesses -Codex $savedCodex).Count -gt 0
  $savedOwnsPort = $null -ne $savedCodex -and (Test-QQSkinCodexPortOwner -Port $Port -Codex $savedCodex)
  if ($savedIsDifferent -and $currentRunning -and ($savedRunning -or $savedOwnsPort)) {
    throw 'Multiple Codex package versions are active. Close them manually before restore; state and configuration were preserved.'
  }

  $codex = $currentCodex
  if ($savedRunning -or $savedOwnsPort -or $null -eq $currentCodex) {
    $codex = $savedCodex
    if ($null -ne $codex -and $savedIsDifferent) {
      Write-Warning 'Using the saved Codex package identity to close its older active CDP session.'
    } elseif ($null -ne $codex -and $null -eq $currentCodex) {
      Write-Warning 'Using the saved Codex identity after revalidating it against the registered Store package.'
    }
  }
  $relaunchCodex = if ($null -ne $currentCodex) { $currentCodex } else { $codex }
  $codexRunning = $null -ne $codex -and (Get-QQSkinCodexProcesses -Codex $codex).Count -gt 0
  $portOwnedByCodex = $null -ne $codex -and (Test-QQSkinCodexPortOwner -Port $Port -Codex $codex)
  if ($portOwnedByCodex -and -not $codexRunning) {
    throw 'A Codex-owned listener exists without a manageable Codex process; state was preserved.'
  }
  if ($null -ne $state -and $null -eq $codex -and -not (Test-QQSkinPortAvailable -Port $Port)) {
    throw "Port $Port is still active, but Codex ownership cannot be verified. State and configuration were preserved."
  }

  $shouldCloseCodex = $codexRunning
  $forceAuthorized = [bool]$ForceRestart
  if ($shouldCloseCodex -and $PromptRestart) {
    $restartMessage = if ($NoRelaunch) {
      'Restore will close Codex and remove Retro QQ Skin plus its CDP session. Continue?'
    } else {
      'Restore will close Codex, remove Retro QQ Skin and its CDP session, then reopen the official app. Continue?'
    }
    $forceAuthorized = Confirm-QQSkinRestart -Message $restartMessage
    if (-not $forceAuthorized) {
      Write-Host 'Restore was cancelled; no state or configuration was changed.'
      exit 0
    }
  }

  $backup = Join-Path $StateRoot 'config.before-qq-skin.toml'
  $config = Join-Path $HOME '.codex\config.toml'
  if ($RecoverConfigBackup) {
    if (-not (Test-Path -LiteralPath $backup)) { throw 'No pre-install config backup is available.' }
    $null = Read-QQSkinUtf8File -Path $backup
  } elseif ($RestoreBaseTheme) {
    if (-not (Test-Path -LiteralPath $backup)) { throw 'No pre-install config backup is available.' }
    $null = Read-QQSkinUtf8File -Path $backup
    $null = Read-QQSkinUtf8File -Path $config
  }

  $restoreError = $null
  try {
    Stop-QQSkinTrayProcess
    if ($shouldCloseCodex) {
      Stop-QQSkinCodex -Codex $codex -AllowForce:$forceAuthorized
      if ($portOwnedByCodex -and -not (Wait-QQSkinPortAvailable -Port $Port -TimeoutSeconds 5)) {
        throw "Port $Port is still listening after Codex closed; state was preserved for inspection."
      }
    }

    $recordedInjectorStopped = Stop-QQSkinRecordedInjector -State $state
    if (-not $recordedInjectorStopped) {
      $staleStatePath = Archive-QQSkinStateFile -Path $StatePath
      Write-Warning "Archived stale Retro QQ Skin state at $staleStatePath"
    }

    if ($RecoverConfigBackup) {
      $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N')
      $recoveryBackup = Join-Path $StateRoot "config.before-recovery-$stamp.toml"
      Restore-QQSkinConfigBackup -ConfigPath $config -BackupPath $backup -RecoveryBackupPath $recoveryBackup
      Write-Host "Recovered the exact pre-install config; previous current config saved at $recoveryBackup"
    } elseif ($RestoreBaseTheme) {
      Restore-QQSkinBaseTheme -ConfigPath $config -BackupPath $backup
    }
    if ($RecoverConfigBackup -or $RestoreBaseTheme) {
      $archiveStamp = (Get-Date).ToString('yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N')
      $archivePath = Join-Path $StateRoot "config.restored-$archiveStamp.toml"
      Archive-QQSkinConfigBackup -BackupPath $backup -ArchivePath $archivePath
      Write-Host "Archived the completed pre-install backup at $archivePath"
    }

    Remove-Item -LiteralPath $StatePath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $StateRoot 'paused') -Force -ErrorAction SilentlyContinue
    if ($Uninstall) {
      $desktop = [Environment]::GetFolderPath('Desktop')
      $startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
      @(
        (Join-Path $desktop 'Codex Retro QQ Skin.lnk'),
        (Join-Path $desktop 'Codex Retro QQ Skin - Restore.lnk'),
        (Join-Path $desktop 'Codex Retro QQ Skin - Tray.lnk'),
        (Join-Path $startMenu 'Codex Retro QQ Skin.lnk'),
        (Join-Path $startMenu 'Codex Retro QQ Skin - Tray.lnk')
      ) | ForEach-Object { Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue }
    }

    if ($shouldCloseCodex -and -not $NoRelaunch) {
      if ($null -eq $relaunchCodex -or -not (Test-Path -LiteralPath $relaunchCodex.Executable)) {
        throw 'Codex cannot be reopened because its current executable is unavailable.'
      }
      $null = Start-QQSkinCodex -Codex $relaunchCodex
    }
  } catch {
    $restoreError = $_
    if ($shouldCloseCodex -and -not $NoRelaunch -and $null -ne $relaunchCodex -and
      (Get-QQSkinCodexProcesses -Codex $codex).Count -eq 0 -and (Test-Path -LiteralPath $relaunchCodex.Executable)) {
      try { $null = Start-QQSkinCodex -Codex $relaunchCodex } catch {
        Write-Warning 'Restore failed and Codex could not be reopened automatically.'
      }
    }
    throw $restoreError
  }

  Write-Host 'Retro QQ Skin restore actions completed; any saved CDP session was closed.'
} finally {
  Exit-QQSkinOperationLock -Mutex $operationLock
}
