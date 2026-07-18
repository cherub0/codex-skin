[CmdletBinding()]
param([switch]$EngineOnly)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
. (Join-Path $Root 'scripts\common-windows.ps1')
. (Join-Path $Root 'scripts\theme-windows.ps1')

$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) "codex-qq-skin-tests-$PID-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null

try {
  $runtimeSourceName = 'runtime source ' + (-join @([char]0x6D4B, [char]0x8BD5))
  $runtimeSourceRoot = Join-Path $temporaryRoot $runtimeSourceName
  $runtimeStateRoot = Join-Path $temporaryRoot 'runtime-state'
  New-Item -ItemType Directory -Path $runtimeSourceRoot | Out-Null
  foreach ($directoryName in @('assets', 'scripts')) {
    Copy-Item -LiteralPath (Join-Path $Root $directoryName) -Destination $runtimeSourceRoot `
      -Recurse -Force -ErrorAction Stop
  }
  $zoneMarkedSourceScript = Join-Path $runtimeSourceRoot 'scripts\start-qq-skin.ps1'
  Set-Content -LiteralPath $zoneMarkedSourceScript -Stream 'Zone.Identifier' `
    -Value "[ZoneTransfer]`r`nZoneId=3`r`n" -Encoding Ascii
  if (@(Get-Item -LiteralPath $zoneMarkedSourceScript -Stream 'Zone.Identifier').Count -ne 1) {
    throw 'Runtime test could not create an Internet-zone marker on its source fixture.'
  }

  $engine = Install-QQSkinRuntimeEngine -SkillRoot $runtimeSourceRoot -StateRoot $runtimeStateRoot
  $sourcePrefix = $runtimeSourceRoot.TrimEnd('\') + '\'
  $runtimeSourceFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $runtimeSourceRoot 'assets'), (Join-Path $runtimeSourceRoot 'scripts') `
      -Recurse -File -Force
  )
  $runtimeEngineFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $engine.Root 'assets'), (Join-Path $engine.Root 'scripts') `
      -Recurse -File -Force
  )
  if ($runtimeSourceFiles.Count -ne $runtimeEngineFiles.Count -or
    -not (Test-QQSkinPathWithin -Path $engine.Start -Root $runtimeStateRoot) -or
    -not (Test-QQSkinPathWithin -Path $engine.Restore -Root $runtimeStateRoot) -or
    -not (Test-QQSkinPathWithin -Path $engine.Tray -Root $runtimeStateRoot)) {
    throw 'Installed runtime paths are incomplete or still point outside the managed state root.'
  }
  foreach ($sourceFile in $runtimeSourceFiles) {
    $relative = $sourceFile.FullName.Substring($sourcePrefix.Length)
    $installedFile = Join-Path $engine.Root $relative
    if (-not (Test-Path -LiteralPath $installedFile -PathType Leaf) -or
      (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceFile.FullName).Hash -cne
      (Get-FileHash -Algorithm SHA256 -LiteralPath $installedFile).Hash) {
      throw "Installed runtime hash does not match its source: $relative"
    }
  }
  if (@(Get-Item -LiteralPath $engine.Start -Stream 'Zone.Identifier' `
    -ErrorAction SilentlyContinue).Count -ne 0) {
    throw 'Installed runtime retained an Internet-zone marker and cannot use RemoteSigned safely.'
  }

  [System.IO.File]::WriteAllText((Join-Path $engine.Root 'stale-runtime.txt'), 'stale')
  [System.IO.File]::WriteAllText((Join-Path $runtimeSourceRoot 'scripts\runtime-update.test'), 'updated')
  $realRuntimeCleanup = (Get-Command Remove-QQSkinRuntimeTree -CommandType Function).ScriptBlock
  $previousWarningPreference = $WarningPreference
  $runtimeCleanupFailure = @{ Triggered = $false }
  try {
    $WarningPreference = 'Stop'
    function Remove-QQSkinRuntimeTree {
      param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$StateRoot
      )
      if ([System.IO.Path]::GetFileName($Path) -like '.engine-backup-*') {
        $runtimeCleanupFailure.Triggered = $true
        throw 'forced runtime backup cleanup failure'
      }
      & $realRuntimeCleanup -Path $Path -StateRoot $StateRoot
    }

    $runtimeUpdateReportedFailure = $false
    try {
      $engine = Install-QQSkinRuntimeEngine -SkillRoot $runtimeSourceRoot -StateRoot $runtimeStateRoot
    } catch {
      $runtimeUpdateReportedFailure = $true
    }
    if (-not $runtimeCleanupFailure.Triggered -or $runtimeUpdateReportedFailure -or
      (Test-Path -LiteralPath (Join-Path $engine.Root 'stale-runtime.txt')) -or
      (Read-QQSkinUtf8File -Path (Join-Path $engine.Root 'scripts\runtime-update.test')) -cne 'updated') {
      throw 'Runtime reinstall did not commit cleanly when old-engine cleanup failed.'
    }
  } finally {
    $WarningPreference = $previousWarningPreference
    Set-Item -Path Function:\Remove-QQSkinRuntimeTree -Value $realRuntimeCleanup
  }
  foreach ($runtimeBackup in Get-ChildItem -LiteralPath $runtimeStateRoot -Directory -Force |
    Where-Object { $_.Name -like '.engine-backup-*' }) {
    Remove-QQSkinRuntimeTree -Path $runtimeBackup.FullName -StateRoot $runtimeStateRoot
  }

  $invalidRuntimeRoot = Join-Path $temporaryRoot 'invalid-runtime-source'
  New-Item -ItemType Directory -Path $invalidRuntimeRoot | Out-Null
  foreach ($directoryName in @('assets', 'scripts')) {
    Copy-Item -LiteralPath (Join-Path $runtimeSourceRoot $directoryName) -Destination $invalidRuntimeRoot `
      -Recurse -Force -ErrorAction Stop
  }
  Remove-Item -LiteralPath (Join-Path $invalidRuntimeRoot 'scripts\start-qq-skin.ps1') -Force
  $invalidRuntimeRejected = $false
  try {
    $null = Install-QQSkinRuntimeEngine -SkillRoot $invalidRuntimeRoot -StateRoot $runtimeStateRoot
  } catch {
    $invalidRuntimeRejected = $true
  }
  if (-not $invalidRuntimeRejected -or
    -not (Test-Path -LiteralPath $engine.Start -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $engine.Root 'scripts\runtime-update.test') -PathType Leaf) -or
    @(Get-ChildItem -LiteralPath $runtimeStateRoot -Force | Where-Object {
      $_.Name -like '.engine-staging-*' -or $_.Name -like '.engine-backup-*'
    }).Count -ne 0) {
    throw 'An invalid runtime source changed the installed engine or left transaction artifacts.'
  }

  $nestedStateRoot = Join-Path $runtimeSourceRoot 'scripts\nested-state'
  $nestedStateRejected = $false
  try {
    $null = Install-QQSkinRuntimeEngine -SkillRoot $runtimeSourceRoot -StateRoot $nestedStateRoot
  } catch {
    $nestedStateRejected = $true
  }
  if (-not $nestedStateRejected -or (Test-Path -LiteralPath $nestedStateRoot)) {
    throw 'Runtime install allowed its state root to recurse into the copied source tree.'
  }

  $installSource = Read-QQSkinUtf8File -Path (Join-Path $Root 'scripts\install-qq-skin.ps1')
  $commonSource = Read-QQSkinUtf8File -Path (Join-Path $Root 'scripts\common-windows.ps1')
  $hashVerificationIndex = $commonSource.IndexOf(
    'Staged Retro QQ Skin runtime failed hash verification', [System.StringComparison]::Ordinal
  )
  $unblockIndex = $commonSource.IndexOf(
    'Unblock-File -LiteralPath $runtimeScript.FullName', [System.StringComparison]::Ordinal
  )
  if ($hashVerificationIndex -lt 0 -or $unblockIndex -le $hashVerificationIndex) {
    throw 'Runtime scripts are not unblocked only after staged byte-content verification.'
  }
  $trayGuardIndex = $installSource.IndexOf('if (Test-QQSkinTrayActive)', [System.StringComparison]::Ordinal)
  $engineInstallIndex = $installSource.IndexOf('$engine = Install-QQSkinRuntimeEngine', [System.StringComparison]::Ordinal)
  if ($trayGuardIndex -lt 0 -or $engineInstallIndex -le $trayGuardIndex) {
    throw 'Installer does not reject an active source-bound tray before replacing the runtime engine.'
  }
  foreach ($requiredShortcutBinding in @(
    '$startScript = $engine.Start',
    '$restoreScript = $engine.Restore',
    '$trayScript = $engine.Tray',
    '$shortcut.WorkingDirectory = $engine.Root',
    '$restore.WorkingDirectory = $engine.Root',
    '$tray.WorkingDirectory = $engine.Root'
  )) {
    if (-not $installSource.Contains($requiredShortcutBinding)) {
      throw "Installer shortcut still depends on its source checkout: $requiredShortcutBinding"
    }
  }
  if ([regex]::Matches($installSource, '-ExecutionPolicy RemoteSigned').Count -ne 4 -or
    $installSource.Contains('-ExecutionPolicy Bypass')) {
    throw 'Installer shortcuts or tray launch still bypass the PowerShell execution policy.'
  }

  Remove-Item -LiteralPath $runtimeSourceRoot -Recurse -Force
  foreach ($installedScript in Get-ChildItem -LiteralPath $engine.Scripts -Filter '*.ps1' -File) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
      $installedScript.FullName, [ref]$tokens, [ref]$parseErrors
    ) | Out-Null
    if ($parseErrors.Count -gt 0) {
      throw "Installed runtime script failed to parse after its source checkout was removed: $($installedScript.Name)"
    }
  }
  if (-not (Test-Path -LiteralPath $engine.Start -PathType Leaf) -or
    -not (Test-Path -LiteralPath $engine.Restore -PathType Leaf) -or
    -not (Test-Path -LiteralPath $engine.Tray -PathType Leaf)) {
    throw 'Installed launch, restore, or tray entry point disappeared with the source checkout.'
  }
  Remove-Item -LiteralPath $invalidRuntimeRoot, $runtimeStateRoot -Recurse -Force

  if ($EngineOnly) {
    Write-Host 'PASS: managed runtime staging, replacement, invalid-source guard, and source-independent shortcuts.'
    return
  }

  $atomicReplacePath = Join-Path $temporaryRoot 'atomic-replace.txt'
  [System.IO.File]::WriteAllText($atomicReplacePath, 'before')
  Write-QQSkinUtf8FileAtomically -Path $atomicReplacePath -Content 'after'
  if ((Read-QQSkinUtf8File -Path $atomicReplacePath) -cne 'after') {
    throw 'Atomic writer did not replace an existing file under Windows PowerShell.'
  }
  $atomicArtifacts = @(Get-ChildItem -LiteralPath $temporaryRoot -Force |
    Where-Object { $_.FullName -ne $atomicReplacePath })
  if ($atomicArtifacts.Count -ne 0) {
    throw 'Atomic writer left internal replacement artifacts behind.'
  }
  Remove-Item -LiteralPath $atomicReplacePath -Force

  $realAtomicCleanup = (Get-Command Remove-QQSkinAtomicArtifact -CommandType Function).ScriptBlock
  $previousWarningPreference = $WarningPreference
  $cleanupFailure = @{ Triggered = $false }
  try {
    $WarningPreference = 'Stop'
    function Remove-QQSkinAtomicArtifact {
      param([Parameter(Mandatory = $true)][string]$Path)
      if ($Path -like '*.replace-backup') {
        $cleanupFailure.Triggered = $true
        throw 'forced atomic replacement-backup cleanup failure'
      }
      if ([System.IO.File]::Exists($Path)) {
        [System.IO.File]::Delete($Path)
      }
    }

    $cleanupFailurePath = Join-Path $temporaryRoot 'atomic-cleanup-failure.txt'
    [System.IO.File]::WriteAllText($cleanupFailurePath, 'before')
    $cleanupFailureReported = $false
    try {
      Write-QQSkinUtf8FileAtomically -Path $cleanupFailurePath -Content 'after'
    } catch {
      $cleanupFailureReported = $true
    }
    if (-not $cleanupFailure.Triggered -or $cleanupFailureReported -or
      (Read-QQSkinUtf8File -Path $cleanupFailurePath) -cne 'after') {
      throw 'A committed atomic write was reported as failed when cleanup failed.'
    }

    $cleanupConfigPath = Join-Path $temporaryRoot 'cleanup-failure-config.toml'
    $cleanupBackupPath = Join-Path $temporaryRoot 'cleanup-failure-config.before.toml'
    $cleanupOriginal = "model = `"gpt-5`"`r`n`r`n[desktop]`r`nappearanceTheme = `"system`"`r`n"
    [System.IO.File]::WriteAllText(
      $cleanupConfigPath,
      $cleanupOriginal,
      [System.Text.UTF8Encoding]::new($false, $true)
    )
    $cleanupOriginalBytes = [System.IO.File]::ReadAllBytes($cleanupConfigPath)
    Install-QQSkinBaseTheme -ConfigPath $cleanupConfigPath -BackupPath $cleanupBackupPath
    if (-not (Test-Path -LiteralPath $cleanupBackupPath) -or
      -not (Test-QQSkinBytesEqual -Left $cleanupOriginalBytes `
        -Right ([System.IO.File]::ReadAllBytes($cleanupBackupPath)))) {
      throw 'Atomic cleanup failure removed or changed the durable pre-install config backup.'
    }
  } finally {
    $WarningPreference = $previousWarningPreference
    Set-Item -Path Function:\Remove-QQSkinAtomicArtifact -Value $realAtomicCleanup
  }

  $configPath = Join-Path $temporaryRoot 'config.toml'
  $backupPath = Join-Path $temporaryRoot 'config.before-qq-skin.toml'
  $projectName = -join @([char]0x4EE3, [char]0x7801, [char]0x9879, [char]0x76EE, [char]0x7532)
  $laterValue = -join @([char]0x4FDD, [char]0x7559)
  $sample = "model = `"gpt-5`"`r`n`r`n[other]`r`nappearanceTheme = `"keep-other`"`r`n`r`n[projects.'C:\$projectName']`r`ntrust_level = `"trusted`"`r`n`r`n[desktop]`r`nappearanceTheme = `"system`"`r`nappearanceLightCodeThemeId = `"theme-`$special`"`r`n"
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false, $true)
  [System.IO.File]::WriteAllText($configPath, $sample, $utf8NoBom)
  $originalBytes = [System.IO.File]::ReadAllBytes($configPath)

  Install-QQSkinBaseTheme -ConfigPath $configPath -BackupPath $backupPath
  $installed = Read-QQSkinUtf8File -Path $configPath
  if (-not $installed.Contains($projectName) -or $installed -notmatch 'appearanceTheme = "system"' -or
    $installed -notmatch 'appearanceLightCodeThemeId = "codex"') {
    throw 'Install changed a non-ASCII project name or failed to preserve the native appearance.'
  }
  if (-not (Test-Path -LiteralPath (Get-QQSkinAppearanceMarkerPath -BackupPath $backupPath))) {
    throw 'Install did not record the appearance-preservation marker.'
  }
  $backupBytes = [System.IO.File]::ReadAllBytes($backupPath)
  if ([Convert]::ToBase64String($backupBytes) -cne [Convert]::ToBase64String($originalBytes)) {
    throw 'Install did not preserve an exact pre-change config backup.'
  }

  $written = [System.IO.File]::ReadAllBytes($configPath)
  if ($written.Length -ge 3 -and $written[0] -eq 0xEF -and $written[1] -eq 0xBB -and $written[2] -eq 0xBF) {
    throw 'Config writer added an unexpected UTF-8 BOM.'
  }

  $installed += "afterInstall = `"$laterValue`"`r`n"
  $installed = $installed -replace 'appearanceTheme = "system"', 'appearanceTheme = "dark"'
  Write-QQSkinUtf8FileAtomically -Path $configPath -Content $installed
  Restore-QQSkinBaseTheme -ConfigPath $configPath -BackupPath $backupPath
  $restored = Read-QQSkinUtf8File -Path $configPath
  if (-not $restored.Contains($projectName) -or -not $restored.Contains($laterValue)) {
    throw 'Restore changed a project name or unrelated post-install setting.'
  }
  if ($restored -notmatch 'appearanceTheme = "dark"' -or -not $restored.Contains('appearanceLightCodeThemeId = "theme-$special"')) {
    throw 'Restore overwrote the user appearance or failed to restore the light code theme.'
  }
  if ($restored -notmatch '(?ms)^\[other\].*?appearanceTheme = "keep-other"') {
    throw 'Restore changed an appearance key outside the desktop section.'
  }

  $legacyConfigPath = Join-Path $temporaryRoot 'legacy-light.toml'
  $legacyBackupPath = Join-Path $temporaryRoot 'legacy-light.before.toml'
  $legacyCurrent = "[desktop]`r`n$($script:QQSkinLegacyAppearanceTheme)`r`n$($script:QQSkinManagedLightCodeTheme)`r`n$($script:QQSkinManagedLightChromeTheme)`r`n"
  $legacyOriginal = "[desktop]`r`nappearanceTheme = `"system`"`r`nappearanceLightCodeThemeId = `"theme-original`"`r`nappearanceLightChromeTheme = { surface = `"original`" }`r`n"
  [System.IO.File]::WriteAllText($legacyConfigPath, $legacyCurrent, $utf8NoBom)
  [System.IO.File]::WriteAllText($legacyBackupPath, $legacyOriginal, $utf8NoBom)
  Install-QQSkinBaseTheme -ConfigPath $legacyConfigPath -BackupPath $legacyBackupPath
  $legacyMigrated = Read-QQSkinUtf8File -Path $legacyConfigPath
  if ($legacyMigrated -notmatch 'appearanceTheme = "system"' -or
    $legacyMigrated -notmatch 'appearanceLightCodeThemeId = "codex"') {
    throw 'Exact legacy managed light trio was not migrated to the saved native appearance.'
  }
  $legacyMigrated = $legacyMigrated -replace 'appearanceTheme = "system"', 'appearanceTheme = "dark"'
  Write-QQSkinUtf8FileAtomically -Path $legacyConfigPath -Content $legacyMigrated
  Restore-QQSkinBaseTheme -ConfigPath $legacyConfigPath -BackupPath $legacyBackupPath
  if ((Read-QQSkinUtf8File -Path $legacyConfigPath) -notmatch 'appearanceTheme = "dark"') {
    throw 'A current install restore overwrote the user appearance after legacy migration.'
  }

  $lfConfigPath = Join-Path $temporaryRoot 'config-lf.toml'
  $lfBackupPath = Join-Path $temporaryRoot 'config-lf.before.toml'
  $lfOriginal = "model = `"gpt-5`"`n[projects.'C:\$projectName']`ntrust_level = `"trusted`"`n"
  [System.IO.File]::WriteAllText($lfConfigPath, $lfOriginal, $utf8NoBom)
  Install-QQSkinBaseTheme -ConfigPath $lfConfigPath -BackupPath $lfBackupPath
  $lfInstalled = Read-QQSkinUtf8File -Path $lfConfigPath
  if ($lfInstalled.Contains("`r") -or $lfInstalled -notmatch '(?m)^\[desktop\]$') {
    throw 'Install did not preserve LF line endings or create the desktop section.'
  }
  Restore-QQSkinBaseTheme -ConfigPath $lfConfigPath -BackupPath $lfBackupPath
  $lfRestored = Read-QQSkinUtf8File -Path $lfConfigPath
  if ($lfRestored.Contains("`r") -or $lfRestored -match '(?m)^\[desktop\]$' -or -not $lfRestored.Contains($projectName)) {
    throw 'Restore did not preserve LF content or remove the generated empty desktop section.'
  }

  $quotedConfigPath = Join-Path $temporaryRoot 'config-quoted.toml'
  $quotedBackupPath = Join-Path $temporaryRoot 'config-quoted.before.toml'
  $quotedOriginal = "[`"desktop`"] # retained comment`r`n`"appearanceTheme`" = `"system`"`r`n'appearanceLightCodeThemeId' = `"theme-`$special`"`r`n"
  [System.IO.File]::WriteAllText($quotedConfigPath, $quotedOriginal, $utf8NoBom)
  Install-QQSkinBaseTheme -ConfigPath $quotedConfigPath -BackupPath $quotedBackupPath
  $quotedInstalled = Read-QQSkinUtf8File -Path $quotedConfigPath
  if ([regex]::Matches($quotedInstalled, '(?m)^\s*\[(?:"desktop"|desktop)\]').Count -ne 1) {
    throw 'A commented or quoted desktop table was duplicated during install.'
  }
  Restore-QQSkinBaseTheme -ConfigPath $quotedConfigPath -BackupPath $quotedBackupPath
  if ((Read-QQSkinUtf8File -Path $quotedConfigPath) -cne $quotedOriginal) {
    throw 'Quoted desktop keys or a table-header comment were not restored exactly.'
  }

  $nestedConfigPath = Join-Path $temporaryRoot 'config-nested-themes.toml'
  $nestedBackupPath = Join-Path $temporaryRoot 'config-nested-themes.before.toml'
  $nestedTables = "[desktop.appearanceDarkChromeTheme]`r`naccent = `"#112233`"`r`n`r`n[desktop.appearanceDarkChromeTheme.fonts]`r`ncode = `"Cascadia Code`"`r`n`r`n[desktop.appearanceDarkChromeTheme.semanticColors]`r`ndiffAdded = `"#234567`"`r`n`r`n[desktop.appearanceLightChromeTheme]`r`naccent = `"#abcdef`"`r`n`r`n[desktop.appearanceLightChromeTheme.fonts]`r`nui = `"Microsoft YaHei UI`"`r`n`r`n[desktop.appearanceLightChromeTheme.semanticColors]`r`ndiffRemoved = `"#fedcba`"`r`n`r`n[`"desktop`".layout]`r`ndensity = `"compact`"`r`n"
  $nestedOriginal = "[desktop]`r`nappearanceTheme = `"system`"`r`nappearanceLightCodeThemeId = `"github-light`"`r`n`r`n$nestedTables"
  [System.IO.File]::WriteAllText($nestedConfigPath, $nestedOriginal, $utf8NoBom)
  Install-QQSkinBaseTheme -ConfigPath $nestedConfigPath -BackupPath $nestedBackupPath
  $nestedInstalled = Read-QQSkinUtf8File -Path $nestedConfigPath
  $nestedDesktop = Get-QQSkinDesktopSection -Content $nestedInstalled
  if (-not $nestedDesktop.Body.Contains('appearanceTheme = "system"') -or
    -not $nestedDesktop.Body.Contains('appearanceLightCodeThemeId = "codex"')) {
    throw 'Install did not update scalar appearance settings beside nested desktop theme tables.'
  }
  if ([regex]::IsMatch($nestedDesktop.Body, '(?m)^[\t ]*appearanceLightChromeTheme[\t ]*=')) {
    throw 'Install wrote an inline light chrome theme beside the equivalent nested table.'
  }
  if (-not $nestedInstalled.Contains($nestedTables)) {
    throw 'Install changed native Codex chrome theme or unrelated nested desktop tables.'
  }
  Restore-QQSkinBaseTheme -ConfigPath $nestedConfigPath -BackupPath $nestedBackupPath
  if ((Read-QQSkinUtf8File -Path $nestedConfigPath) -cne $nestedOriginal) {
    throw 'Nested desktop theme tables were not preserved through install and restore.'
  }

  $singleLineArrayPath = Join-Path $temporaryRoot 'config-single-line-array.toml'
  $singleLineArrayBackup = Join-Path $temporaryRoot 'config-single-line-array.before.toml'
  $singleLineArray = "labels = [`"name[1]`", `"#tag]`"]`r`n"
  [System.IO.File]::WriteAllText($singleLineArrayPath, $singleLineArray, $utf8NoBom)
  Install-QQSkinBaseTheme -ConfigPath $singleLineArrayPath -BackupPath $singleLineArrayBackup
  if (-not (Read-QQSkinUtf8File -Path $singleLineArrayPath).Contains($singleLineArray.TrimEnd())) {
    throw 'A safe single-line array containing bracket text was changed or rejected.'
  }

  foreach ($unsupported in @(
    'desktop.appearanceTheme = "system"',
    'desktop = { appearanceTheme = "system" }',
    '[[desktop]]',
    '[[desktop.layout]]',
    '[desktop.appearanceTheme]',
    '[desktop.appearanceLightCodeThemeId]',
    "[desktop]`r`nappearanceLightChromeTheme = { accent = `"#ffffff`" }`r`n`r`n[desktop.appearanceLightChromeTheme]`r`naccent = `"#000000`"",
    '["desk\u0074op".layout]',
    '["desk\u0074op"]',
    "note = `"`"`"fake`r`n[desktop]`r`nappearanceTheme = `"dark`"`r`n`"`"`"",
    "[desktop]`r`nappearanceTheme = [`r`n  `"light`"`r`n]",
    "[desktop]`r`nlayout = [`r`n  [1, 2],`r`n  [3, 4],`r`n]`r`nappearanceTheme = `"dark`"",
    "[desktop]`r`nlayout = [`"]`",`r`n  [`"[`", `"]`"],`r`n]`r`nappearanceTheme = `"dark`""
  )) {
    $unsupportedPath = Join-Path $temporaryRoot ("unsupported-$([guid]::NewGuid().ToString('N')).toml")
    $unsupportedBackup = "$unsupportedPath.before"
    [System.IO.File]::WriteAllText($unsupportedPath, $unsupported, $utf8NoBom)
    $unsupportedRejected = $false
    try { Install-QQSkinBaseTheme -ConfigPath $unsupportedPath -BackupPath $unsupportedBackup } catch { $unsupportedRejected = $true }
    if (-not $unsupportedRejected -or (Test-Path -LiteralPath $unsupportedBackup)) {
      throw "Unsupported TOML desktop representation was not rejected safely: $unsupported"
    }
  }

  $recoveryPath = Join-Path $temporaryRoot 'config.before-recovery.toml'
  Write-QQSkinUtf8FileAtomically -Path $configPath -Content 'intentionally changed'
  Restore-QQSkinConfigBackup -ConfigPath $configPath -BackupPath $backupPath -RecoveryBackupPath $recoveryPath
  $recoveredBytes = [System.IO.File]::ReadAllBytes($configPath)
  if ([Convert]::ToBase64String($recoveredBytes) -cne [Convert]::ToBase64String($originalBytes)) {
    throw 'Exact config recovery did not restore the original bytes.'
  }
  if ((Read-QQSkinUtf8File -Path $recoveryPath) -cne 'intentionally changed') {
    throw 'Exact config recovery did not preserve the replaced current config.'
  }
  $archivePath = Join-Path $temporaryRoot 'config.restored.toml'
  Archive-QQSkinConfigBackup -BackupPath $backupPath -ArchivePath $archivePath
  if ((Test-Path -LiteralPath $backupPath) -or -not (Test-Path -LiteralPath $archivePath)) {
    throw 'Completed config backup was not archived for a safe future reinstall.'
  }
  $secondBaseline = "[desktop]`r`nappearanceTheme = `"dark`"`r`n"
  [System.IO.File]::WriteAllText($configPath, $secondBaseline, $utf8NoBom)
  $secondBaselineBytes = [System.IO.File]::ReadAllBytes($configPath)
  Install-QQSkinBaseTheme -ConfigPath $configPath -BackupPath $backupPath
  if (-not (Test-QQSkinBytesEqual -Left $secondBaselineBytes -Right ([System.IO.File]::ReadAllBytes($backupPath)))) {
    throw 'Reinstall did not capture a fresh config baseline after completed restore.'
  }

  $invalidPath = Join-Path $temporaryRoot 'invalid.toml'
  $invalidBackupPath = Join-Path $temporaryRoot 'invalid.before.toml'
  [System.IO.File]::WriteAllBytes($invalidPath, [byte[]](0x66, 0x6f, 0x80))
  $rejected = $false
  try { Install-QQSkinBaseTheme -ConfigPath $invalidPath -BackupPath $invalidBackupPath } catch { $rejected = $true }
  if (-not $rejected -or (Test-Path -LiteralPath $invalidBackupPath)) {
    throw 'Invalid UTF-8 input was not rejected before backup creation.'
  }
  $utf16Path = Join-Path $temporaryRoot 'utf16.toml'
  $utf16BackupPath = Join-Path $temporaryRoot 'utf16.before.toml'
  [System.IO.File]::WriteAllText($utf16Path, 'model = "gpt-5"', [System.Text.Encoding]::Unicode)
  $utf16Rejected = $false
  try { Install-QQSkinBaseTheme -ConfigPath $utf16Path -BackupPath $utf16BackupPath } catch { $utf16Rejected = $true }
  if (-not $utf16Rejected -or (Test-Path -LiteralPath $utf16BackupPath)) {
    throw 'A UTF-16 config was silently transcoded instead of being rejected.'
  }
  $utf16NoBomPath = Join-Path $temporaryRoot 'utf16-no-bom.toml'
  $utf16NoBomBackupPath = Join-Path $temporaryRoot 'utf16-no-bom.before.toml'
  [System.IO.File]::WriteAllBytes($utf16NoBomPath, [System.Text.Encoding]::Unicode.GetBytes('model = "gpt-5"'))
  $utf16NoBomRejected = $false
  try { Install-QQSkinBaseTheme -ConfigPath $utf16NoBomPath -BackupPath $utf16NoBomBackupPath } catch { $utf16NoBomRejected = $true }
  if (-not $utf16NoBomRejected -or (Test-Path -LiteralPath $utf16NoBomBackupPath)) {
    throw 'A BOM-less UTF-16 config was silently treated as UTF-8 instead of being rejected.'
  }
  $racePath = Join-Path $temporaryRoot 'race.toml'
  [System.IO.File]::WriteAllText($racePath, 'before', $utf8NoBom)
  $raceExpected = [System.IO.File]::ReadAllBytes($racePath)
  [System.IO.File]::WriteAllText($racePath, 'after', $utf8NoBom)
  $raceRejected = $false
  try { Assert-QQSkinFileUnchanged -Path $racePath -ExpectedBytes $raceExpected } catch { $raceRejected = $true }
  if (-not $raceRejected) { throw 'Concurrent config modification was not detected.' }
  $conditionalWriteRejected = $false
  try {
    Write-QQSkinUtf8FileAtomically -Path $racePath -Content 'replacement' -ExpectedBytes $raceExpected
  } catch {
    $conditionalWriteRejected = $true
  }
  if (-not $conditionalWriteRejected -or (Read-QQSkinUtf8File -Path $racePath) -cne 'after') {
    throw 'Conditional atomic write replaced newer config content.'
  }

  if (-not (Test-QQSkinWebSocketUrl -Value 'ws://127.0.0.1:9335/devtools/page/test' -Port 9335)) {
    throw 'PowerShell loopback WebSocket validation rejected a safe target.'
  }
  foreach ($unsafe in @(
    'ws://example.com:9335/devtools/page/test',
    'ws://127.0.0.1:9336/devtools/page/test',
    'wss://127.0.0.1:9335/devtools/page/test',
    'ws://user@127.0.0.1:9335/devtools/page/test',
    'ws://127.0.0.1:9335/unexpected/test',
    'ws://127.0.0.1:9335/devtools/page/test?query=1'
  )) {
    if (Test-QQSkinWebSocketUrl -Value $unsafe -Port 9335) { throw "Accepted unsafe CDP target: $unsafe" }
  }
  $safePageTarget = [pscustomobject]@{
    id = 'page-123'
    type = 'page'
    url = 'app://codex/'
    webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/page/page-123'
  }
  if (-not (Test-QQSkinCdpPageTarget -Target $safePageTarget -Port 9335)) {
    throw 'A valid same-ID CDP page target was rejected.'
  }
  foreach ($unsafePageTarget in @(
    [pscustomobject]@{ id = 'page-123'; type = 'page'; url = 'app://codex/'; webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/browser/page-123' },
    [pscustomobject]@{ id = 'other-page'; type = 'page'; url = 'app://codex/'; webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/page/page-123' },
    [pscustomobject]@{ id = 123; type = 'page'; url = 'app://codex/'; webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/page/123' },
    [pscustomobject]@{ id = 'page-123'; type = 'other'; url = 'app://codex/'; webSocketDebuggerUrl = 'ws://127.0.0.1:9335/devtools/page/page-123' }
  )) {
    if (Test-QQSkinCdpPageTarget -Target $unsafePageTarget -Port 9335) {
      throw 'Accepted an inconsistent CDP page target.'
    }
  }
  $watchCommand = '"C:\Program Files\nodejs\node.exe" "C:\Retro QQ Skin\injector.mjs" --watch --port 9335 --browser-id browser-123'
  if (-not (Test-QQSkinCommandLineToken -CommandLine $watchCommand -Token 'C:\Retro QQ Skin\injector.mjs') -or
    (Test-QQSkinCommandLineToken -CommandLine $watchCommand -Token 'Retro QQ Skin\injector.mjs')) {
    throw 'Injector command-line token validation is not boundary-safe.'
  }
  if (-not (Test-QQSkinBrowserId -Value 'browser-123') -or
    (Test-QQSkinBrowserId -Value 'browser 123')) {
    throw 'CDP browser ID validation is not boundary-safe.'
  }
  $quotedProfile = ConvertTo-QQSkinProcessArgument -Value '--user-data-dir=C:\Retro QQ Skin\Profile\'
  if ($quotedProfile -cne '"--user-data-dir=C:\Retro QQ Skin\Profile\\"') {
    throw 'Process argument quoting did not protect spaces and a trailing backslash.'
  }
  $argumentLine = ConvertTo-QQSkinArgumentLine -Arguments @(
    '--remote-debugging-address=127.0.0.1',
    '--user-data-dir=C:\Retro QQ Skin\Profile\',
    ''
  )
  if ($argumentLine -cne '--remote-debugging-address=127.0.0.1 "--user-data-dir=C:\Retro QQ Skin\Profile\\" ""') {
    throw 'Packaged-app argument line quoting failed.'
  }
  Initialize-QQSkinPackageLauncher
  if (-not ('CodexQQSkin.PackageLauncher' -as [type])) {
    throw 'Packaged-app activation helper did not compile.'
  }
  $invalidActivationRejected = $false
  try { $null = Start-QQSkinCodex -Codex ([pscustomobject]@{ AppUserModelId = 'invalid app' }) } catch {
    $invalidActivationRejected = $true
  }
  if (-not $invalidActivationRejected) { throw 'An invalid AppUserModelId reached package activation.' }

  $statePath = Join-Path $temporaryRoot 'state.json'
  $state = [pscustomobject]@{
    schemaVersion = 3
    platform = 'windows'
    port = 9335
    injectorPid = 1234
    injectorStartedAt = '2026-01-01T00:00:00.0000000Z'
    injectorPath = 'C:\Retro QQ Skin\injector.mjs'
    nodePath = 'C:\Program Files\nodejs\node.exe'
    codexExe = 'C:\Program Files\WindowsApps\OpenAI.Codex\app\ChatGPT.exe'
    codexPackageRoot = 'C:\Program Files\WindowsApps\OpenAI.Codex'
    codexPackageFullName = 'OpenAI.Codex_1.2.3.4_x64__test'
    codexPackageFamilyName = 'OpenAI.Codex_test'
    browserId = 'browser-123'
  }
  Write-QQSkinState -Path $statePath -State $state
  $loadedState = Read-QQSkinState -Path $statePath
  if ($loadedState.schemaVersion -ne 3 -or $loadedState.port -ne 9335 -or
    $loadedState.browserId -cne 'browser-123') { throw 'State round-trip failed.' }
  $missingIdentityState = [pscustomobject]@{ schemaVersion = 3; platform = 'windows'; port = 9335 }
  Write-QQSkinState -Path $statePath -State $missingIdentityState
  $missingIdentityRejected = $false
  try { $null = Read-QQSkinState -Path $statePath } catch { $missingIdentityRejected = $true }
  if (-not $missingIdentityRejected) { throw 'Schema 3 accepted a state missing process and package identity.' }
  $legacyState = [pscustomobject]@{ schemaVersion = 2; platform = 'windows'; port = 9335; injectorPid = 1234 }
  Write-QQSkinState -Path $statePath -State $legacyState
  if ((Read-QQSkinState -Path $statePath).schemaVersion -ne 2) {
    throw 'A supported schema 2 state was rejected.'
  }

  $fakePackageRoot = Join-Path $temporaryRoot 'OpenAI.Codex_1.2.3.4_x64__test'
  $fakeExecutable = Join-Path $fakePackageRoot 'app\ChatGPT.exe'
  New-Item -ItemType Directory -Path (Split-Path -Parent $fakeExecutable) -Force | Out-Null
  [System.IO.File]::WriteAllBytes($fakeExecutable, [byte[]]@())
  $fakePackage = [pscustomobject]@{
    Name = 'OpenAI.Codex'
    InstallLocation = $fakePackageRoot
    PackageFullName = 'OpenAI.Codex_1.2.3.4_x64__test'
    PackageFamilyName = 'OpenAI.Codex_test'
    SignatureKind = 'Store'
    IsDevelopmentMode = $false
    Version = [version]'1.2.3.4'
  }
  $fakeManifest = [pscustomobject]@{
    Package = [pscustomobject]@{
      Applications = [pscustomobject]@{
        Application = @(
          [pscustomobject]@{ Id = 'Other'; Executable = 'other\Other.exe' },
          [pscustomobject]@{ Id = 'App'; Executable = 'app/ChatGPT.exe' }
        )
      }
    }
  }
  $fakeInstall = ConvertTo-QQSkinCodexInstall -Package $fakePackage -Manifest $fakeManifest
  if ($null -eq $fakeInstall -or $fakeInstall.PackageFullName -cne $fakePackage.PackageFullName -or
    $fakeInstall.AppUserModelId -cne 'OpenAI.Codex_test!App' -or
    -not (Test-QQSkinPathEqual -Left $fakeInstall.Executable -Right $fakeExecutable)) {
    throw 'Registered Appx package identity conversion failed.'
  }
  $fakeManifest.Package.Applications.Application[1].Id = 'Invalid App'
  if ($null -ne (ConvertTo-QQSkinCodexInstall -Package $fakePackage -Manifest $fakeManifest)) {
    throw 'An invalid packaged-app application ID was accepted.'
  }
  $fakeManifest.Package.Applications.Application[1].Id = 'App'
  $fakeManifest.Package.Applications.Application += [pscustomobject]@{ Id = 'Duplicate'; Executable = 'app\ChatGPT.exe' }
  if ($null -ne (ConvertTo-QQSkinCodexInstall -Package $fakePackage -Manifest $fakeManifest)) {
    throw 'An ambiguous packaged-app manifest was accepted.'
  }
  $fakeManifest.Package.Applications.Application = @($fakeManifest.Package.Applications.Application[0..1])
  $fakePackage.SignatureKind = 'Developer'
  if ($null -ne (ConvertTo-QQSkinCodexInstall -Package $fakePackage -Manifest $fakeManifest)) {
    throw 'A non-Store Appx package was accepted as official Codex.'
  }
  $fakePackage.SignatureKind = 'Store'
  $pathOnlyState = [pscustomobject]@{
    codexExe = $fakeExecutable
    codexPackageRoot = $fakePackageRoot
    codexVersion = '1.2.3.4'
  }
  if ($null -eq (Get-QQSkinCodexStatePathCandidate -State $pathOnlyState)) {
    throw 'A structurally valid legacy Codex path was not recognized for read-only activity checks.'
  }
  if ($null -eq (Resolve-QQSkinCodexInstallFromState -State $pathOnlyState `
    -RegisteredInstalls @($fakeInstall))) {
    throw 'A legacy state path was not revalidated against a registered Store package.'
  }
  $verifiedPackageState = [pscustomobject]@{
    codexExe = $fakeExecutable
    codexPackageRoot = $fakePackageRoot
    codexVersion = '1.2.3.4'
    codexPackageFullName = $fakePackage.PackageFullName
    codexPackageFamilyName = $fakePackage.PackageFamilyName
  }
  $resolvedInstall = Resolve-QQSkinCodexInstallFromState -State $verifiedPackageState `
    -RegisteredInstalls @($fakeInstall)
  if ($null -eq $resolvedInstall -or -not $resolvedInstall.RegisteredPackageVerified -or
    $resolvedInstall.AppUserModelId -cne $fakeInstall.AppUserModelId) {
    throw 'State package identity did not resolve against the registered Appx package.'
  }
  $verifiedPackageState.codexPackageFamilyName = 'OpenAI.Codex_wrong'
  if ($null -ne (Resolve-QQSkinCodexInstallFromState -State $verifiedPackageState `
    -RegisteredInstalls @($fakeInstall))) {
    throw 'A mismatched Appx package family was accepted from state.'
  }
  Write-QQSkinUtf8FileAtomically -Path $statePath -Content '[]'
  $badStateRejected = $false
  try { $null = Read-QQSkinState -Path $statePath } catch { $badStateRejected = $true }
  if (-not $badStateRejected) { throw 'A non-object state file was accepted.' }
  $staleStatePath = Archive-QQSkinStateFile -Path $statePath
  if ((Test-Path -LiteralPath $statePath) -or -not (Test-Path -LiteralPath $staleStatePath)) {
    throw 'Stale state was not preserved under an archive name.'
  }

  $themeStateRoot = Join-Path $temporaryRoot 'theme-state'
  $legacyPresetDirectory = Join-Path $themeStateRoot 'themes\preset-romantic-rose'
  $customThemeDirectory = Join-Path $themeStateRoot 'themes\custom-keepme'
  New-Item -ItemType Directory -Force -Path $legacyPresetDirectory, $customThemeDirectory | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $legacyPresetDirectory 'retired-marker'), 'retired', $utf8NoBom)
  [System.IO.File]::WriteAllText((Join-Path $customThemeDirectory 'keep-marker'), 'keep', $utf8NoBom)
  $themePaths = Initialize-QQSkinThemeStore -SkillRoot $Root -StateRoot $themeStateRoot
  if ((Test-Path -LiteralPath $legacyPresetDirectory) -or
    -not (Test-Path -LiteralPath (Join-Path $customThemeDirectory 'keep-marker'))) {
    throw 'Theme-store migration did not retire the old preset ID while preserving custom themes.'
  }
  $initialTheme = Read-QQSkinTheme -ThemeDirectory $themePaths.Active
  if ($initialTheme.Theme.id -cne 'retro-qq-windows' -or
    $initialTheme.Theme.name -cne 'Codex Retro QQ Skin' -or
    $initialTheme.Theme.appearance -cne 'auto' -or
    $initialTheme.Theme.art.safeArea -cne 'center' -or
    $initialTheme.Theme.art.taskMode -cne 'ambient' -or
    [System.IO.Path]::GetExtension($initialTheme.ImagePath) -cne '.png') {
    throw 'Default Windows theme did not seed the Retro QQ wallpaper contract.'
  }
  $preseededThemes = @(Get-QQSkinSavedThemes -StateRoot $themeStateRoot)
  if ($preseededThemes.Count -ne 1 -or
    $preseededThemes[0].Id -cne 'retro-qq-windows' -or
    $preseededThemes[0].Name -cne 'Codex Retro QQ Skin') {
    throw 'Retro QQ Skin was not preseeded in the Windows saved-theme menu.'
  }
  $updatedTheme = Set-QQSkinActiveTheme -ImagePath (Join-Path $Root 'assets\qq-reference.png') `
    -Theme $null -Name '测试主题' -StateRoot $themeStateRoot
  if ($updatedTheme.Theme.name -cne '测试主题' -or
    $updatedTheme.Theme.id -cne 'custom' -or
    $updatedTheme.Theme.art.safeArea -cne 'auto' -or
    $updatedTheme.Theme.art.taskMode -cne 'auto' -or
    -not (Test-QQSkinThemePathWithin -Path $updatedTheme.ImagePath -Root $themePaths.Active)) {
    throw 'Imported image did not reset to the generic adaptive contract inside the managed directory.'
  }
  $null = Initialize-QQSkinThemeStore -SkillRoot $Root -StateRoot $themeStateRoot
  $idempotentTheme = Read-QQSkinTheme -ThemeDirectory $themePaths.Active
  if ($idempotentTheme.Theme.id -cne 'custom' -or
    @(Get-QQSkinSavedThemes -StateRoot $themeStateRoot).Count -ne 1) {
    throw 'Theme-store initialization overwrote the active custom theme or duplicated its bundled preset.'
  }
  $savedTheme = Save-QQSkinCurrentTheme -Name '已保存主题' -StateRoot $themeStateRoot
  if ($savedTheme.Theme.name -cne '已保存主题' -or @(Get-QQSkinSavedThemes -StateRoot $themeStateRoot).Count -ne 2) {
    throw 'Saved theme creation or discovery failed.'
  }
  $null = Use-QQSkinSavedTheme -ThemeDirectory $savedTheme.Directory -StateRoot $themeStateRoot

  $outsideTheme = Join-Path $temporaryRoot 'outside-theme'
  New-Item -ItemType Directory -Path $outsideTheme | Out-Null
  Copy-Item -LiteralPath (Join-Path $Root 'assets\qq-reference.png') `
    -Destination (Join-Path $outsideTheme 'qq-reference.png')
  Copy-Item -LiteralPath (Join-Path $Root 'assets\theme.json') `
    -Destination (Join-Path $outsideTheme 'theme.json')
  $junctionTheme = Join-Path $themePaths.Saved 'junction-escape'
  $null = New-Item -ItemType Junction -Path $junctionTheme -Target $outsideTheme
  $junctionRejected = $false
  try {
    $null = Use-QQSkinSavedTheme -ThemeDirectory $junctionTheme -StateRoot $themeStateRoot
  } catch { $junctionRejected = $true }
  if (-not $junctionRejected) { throw 'Saved-theme junction escaped the managed theme directory.' }
  [System.IO.Directory]::Delete($junctionTheme)

  Set-QQSkinPaused -Paused $true -StateRoot $themeStateRoot | Out-Null
  if (-not (Test-QQSkinPaused -StateRoot $themeStateRoot)) { throw 'Pause marker was not created.' }
  Set-QQSkinPaused -Paused $false -StateRoot $themeStateRoot | Out-Null
  if (Test-QQSkinPaused -StateRoot $themeStateRoot) { throw 'Pause marker was not removed.' }

  $oversizedTheme = Join-Path $temporaryRoot 'oversized-theme'
  New-Item -ItemType Directory -Path $oversizedTheme | Out-Null
  $oversizedImage = Join-Path $oversizedTheme 'oversized.jpg'
  $oversizedStream = [System.IO.File]::Open($oversizedImage, [System.IO.FileMode]::CreateNew)
  try { $oversizedStream.SetLength((16 * 1024 * 1024) + 1) } finally { $oversizedStream.Dispose() }
  Write-QQSkinUtf8FileAtomically -Path (Join-Path $oversizedTheme 'theme.json') `
    -Content "{`"image`":`"oversized.jpg`"}`r`n"
  $oversizedReadRejected = $false
  try { $null = Read-QQSkinTheme -ThemeDirectory $oversizedTheme } catch { $oversizedReadRejected = $true }
  $oversizedSetRejected = $false
  try {
    $null = Set-QQSkinActiveTheme -ImagePath $oversizedImage -Theme $null -StateRoot $themeStateRoot
  } catch { $oversizedSetRejected = $true }
  if (-not $oversizedReadRejected -or -not $oversizedSetRejected) {
    throw 'The 16 MB image limit was not enforced before theme copy or payload construction.'
  }

  $oversizedDimensionImage = Join-Path $temporaryRoot 'oversized-dimension.png'
  $pngHeader = New-Object byte[] 24
  [byte[]](0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a) | ForEach-Object -Begin { $i = 0 } -Process { $pngHeader[$i++] = $_ }
  $pngHeader[8] = 0; $pngHeader[9] = 0; $pngHeader[10] = 0; $pngHeader[11] = 13
  [byte[]](0x49, 0x48, 0x44, 0x52) | ForEach-Object -Begin { $i = 12 } -Process { $pngHeader[$i++] = $_ }
  $pngHeader[16] = 0; $pngHeader[17] = 0; $pngHeader[18] = 0x27; $pngHeader[19] = 0x10
  $pngHeader[20] = 0; $pngHeader[21] = 0; $pngHeader[22] = 0x17; $pngHeader[23] = 0x70
  [System.IO.File]::WriteAllBytes($oversizedDimensionImage, $pngHeader)
  $oversizedDimensionRejected = $false
  try { $null = Set-QQSkinActiveTheme -ImagePath $oversizedDimensionImage -Theme $null -StateRoot $themeStateRoot } catch { $oversizedDimensionRejected = $true }
  if (-not $oversizedDimensionRejected) { throw 'A 16384px/50MP-invalid import was copied into the active theme.' }

  $reparseStateRoot = Join-Path $temporaryRoot 'reparse-state'
  New-Item -ItemType Directory -Path $reparseStateRoot | Out-Null
  $outsideActive = Join-Path $temporaryRoot 'outside-active'
  New-Item -ItemType Directory -Path $outsideActive | Out-Null
  $reparseActive = Join-Path $reparseStateRoot 'active-theme'
  $null = New-Item -ItemType Junction -Path $reparseActive -Target $outsideActive
  $reparseInitRejected = $false
  try { $null = Initialize-QQSkinThemeStore -SkillRoot $Root -StateRoot $reparseStateRoot } catch { $reparseInitRejected = $true }
  if (-not $reparseInitRejected) { throw 'Theme-store initialization followed an active-theme junction.' }
  [System.IO.Directory]::Delete($reparseActive)

  $css = Read-QQSkinUtf8File -Path (Join-Path $Root 'assets\qq-skin.css')
  foreach ($requiredCss in @(
    'background-image: var(--ds-task-fade), var(--ds-task-shade), var(--qq-skin-art)',
    'main.main-surface > header.app-header-tint',
    '#codex-qq-skin-retro-shell',
    '.app-shell-main-content-top-fade',
    '.thread-scroll-container .bg-gradient-to-t.from-token-main-surface-primary',
    '--ds-immersive-composer',
    'background-position: var(--ds-art-position)',
    '.qq-skin-home-utility',
    ':has(.qq-skin-home-utility) .composer-surface-chrome',
    ':is([data-dream-task-mode="ambient"], [data-dream-art-task-mode="ambient"])[data-dream-art-wide="true"]'
  )) {
    if (-not $css.Contains($requiredCss)) { throw "Windows immersive CSS is missing: $requiredCss" }
  }
  $traySource = Read-QQSkinUtf8File -Path (Join-Path $Root 'scripts\tray-qq-skin.ps1')
  foreach ($requiredTrayAction in @('System.Windows.Forms.NotifyIcon', '暂停皮肤', '更换背景图', '已保存主题', '完全恢复 Codex')) {
    if (-not $traySource.Contains($requiredTrayAction)) { throw "Tray action is missing: $requiredTrayAction" }
  }
  if (-not $traySource.Contains('$nextPaused') -or -not $traySource.Contains('[System.Windows.Forms.Application]::Exit()')) {
    throw 'Tray pause/restore closures do not terminate cleanly.'
  }
  if ([regex]::Matches($traySource, '-ExecutionPolicy RemoteSigned').Count -ne 1 -or
    $traySource.Contains('-ExecutionPolicy Bypass')) {
    throw 'Tray actions still bypass the PowerShell execution policy.'
  }
  if (-not $traySource.Contains('Read-QQSkinTheme -ThemeDirectory $paths.Active -SkipImageMetadata') -or
    -not $traySource.Contains('Get-QQSkinSavedThemes -StateRoot $StateRoot -SkipImageMetadata')) {
    throw 'Tray menu metadata enumeration still performs full image parsing on every open.'
  }
  $restoreSource = Read-QQSkinUtf8File -Path (Join-Path $Root 'scripts\restore-qq-skin.ps1')
  if (-not $restoreSource.Contains('Stop-QQSkinTrayProcess')) {
    throw 'Complete restore does not stop a separately launched tray process.'
  }
  if ($restoreSource.Contains('Start-Process -FilePath $relaunchCodex.Executable') -or
    -not $restoreSource.Contains('Start-QQSkinCodex -Codex $relaunchCodex')) {
    throw 'Restore still executes the WindowsApps path instead of activating the registered package.'
  }
  $startSource = Read-QQSkinUtf8File -Path (Join-Path $Root 'scripts\start-qq-skin.ps1')
  if ($startSource.Contains('Start-Process -FilePath $codex.Executable') -or
    -not $startSource.Contains('Start-QQSkinCodex -Codex $codex')) {
    throw 'Start still executes the WindowsApps path instead of activating the registered package.'
  }
  $stateReadIndex = $startSource.IndexOf('$previousState = Read-QQSkinState', [System.StringComparison]::Ordinal)
  $restartPromptIndex = $startSource.IndexOf('$restartAuthorized = Confirm-QQSkinRestart', [System.StringComparison]::Ordinal)
  $recordedStopIndex = $startSource.IndexOf('$recordedInjectorStopped = Stop-QQSkinRecordedInjector', [System.StringComparison]::Ordinal)
  $cancelIndex = $startSource.IndexOf("Write-Host 'Retro QQ Skin launch was cancelled", [System.StringComparison]::Ordinal)
  $pauseClearIndex = $startSource.IndexOf('Set-QQSkinPaused -Paused $false', [System.StringComparison]::Ordinal)
  if ($stateReadIndex -lt 0 -or $pauseClearIndex -le $stateReadIndex -or
    ($restartPromptIndex -ge 0 -and $pauseClearIndex -le $restartPromptIndex) -or
    ($recordedStopIndex -ge 0 -and $pauseClearIndex -le $recordedStopIndex) -or
    ($cancelIndex -ge 0 -and $cancelIndex -ge $pauseClearIndex)) {
    throw 'Start clears the pause marker before state validation or restart consent, or before its cancellation branch.'
  }
  if (-not $startSource.Contains('$pauseWasSet = Test-QQSkinPaused') -or
    -not $startSource.Contains('$pauseCleared = $true') -or
    -not $startSource.Contains('Set-QQSkinPaused -Paused $true -StateRoot $StateRoot')) {
    throw 'Start does not preserve an existing pause marker when startup rolls back.'
  }

  $rendererSource = Read-QQSkinUtf8File -Path (Join-Path $Root 'assets\renderer-inject.js')
  foreach ($requiredRendererBehavior in @('qq-skin-home-utility', 'artMetadata', 'detectShellMode')) {
    if (-not $rendererSource.Contains($requiredRendererBehavior)) {
      throw "Renderer adaptive behavior is missing: $requiredRendererBehavior"
    }
  }
  $injectorSource = Read-QQSkinUtf8File -Path (Join-Path $Root 'scripts\injector.mjs')
  foreach ($requiredInjectorBehavior in @(
    'MAX_ART_BYTES', 'createHash', 'readImageMetadata', '50MP safety limit', 'STRONG_THEME_AUDIT_MS',
    'Page.addScriptToEvaluateOnNewDocument', 'Page.removeScriptToEvaluateOnNewDocument', 'earlyPayloadFor'
  )) {
    if (-not $injectorSource.Contains($requiredInjectorBehavior)) {
      throw "Injector theme safety is missing: $requiredInjectorBehavior"
    }
  }
  $themeSource = Read-QQSkinUtf8File -Path (Join-Path $Root 'scripts\theme-windows.ps1')
  foreach ($requiredThemeSafety in @(
    '[System.IO.FileAttributes]::ReparsePoint',
    'Ensure-QQSkinManagedDirectory',
    'Get-QQSkinValidatedImageMetadata',
    '16384px / 50MP safety limit',
    'Assert-QQSkinImageFile -Path $temporary',
    'Assert-QQSkinImageFile -Path $imageArchive'
  )) {
    if (-not $themeSource.Contains($requiredThemeSafety)) {
      throw "PowerShell theme-store safety is missing: $requiredThemeSafety"
    }
  }
  $commonSource = Read-QQSkinUtf8File -Path (Join-Path $Root 'scripts\common-windows.ps1')
  if (-not $commonSource.Contains('State was preserved.')) {
    throw 'Mismatched live injector identity does not fail closed with preserved state.'
  }

  $node = Get-QQSkinNodeRuntime
  $stderrProbe = Invoke-QQSkinNative -FilePath $node.Path -ArgumentList @(
    '-e', "process.stderr.write('qq-skin-stderr-probe\n'); process.exit(7)")
  if ($stderrProbe.ExitCode -ne 7 -or ($stderrProbe.Output -join "`n") -notmatch 'qq-skin-stderr-probe') {
    throw "Native stderr was not captured with its real exit code under Stop preference: exit=$($stderrProbe.ExitCode); output=$($stderrProbe.Output -join '<NL>')"
  }
  $discardedProbe = Invoke-QQSkinNative -FilePath $node.Path -ArgumentList @(
    '-e', "process.stderr.write('ignored-warning\n'); process.stdout.write('kept-output')") -DiscardStderr
  if ($discardedProbe.ExitCode -ne 0 -or ($discardedProbe.Output -join '') -cne 'kept-output') {
    throw 'Native stderr discard changed stdout or the real exit code.'
  }

  $selfTest = Invoke-QQSkinNative -FilePath $node.Path -ArgumentList @(
    (Join-Path $Root 'scripts\injector.mjs'), '--self-test')
  if ($selfTest.ExitCode -ne 0) { throw 'Injector CDP self-test failed.' }
  $payloadTest = Invoke-QQSkinNative -FilePath $node.Path -ArgumentList @(
    (Join-Path $Root 'scripts\injector.mjs'), '--check-payload')
  if ($payloadTest.ExitCode -ne 0) { throw 'Injector self-test failed.' }
  $managedPayloadTest = Invoke-QQSkinNative -FilePath $node.Path -ArgumentList @(
    (Join-Path $Root 'scripts\injector.mjs'), '--check-payload', '--theme-dir', $themePaths.Active)
  if ($managedPayloadTest.ExitCode -ne 0) { throw 'Managed theme payload validation failed.' }
  $oversizedPayloadTest = Invoke-QQSkinNative -FilePath $node.Path -ArgumentList @(
    (Join-Path $Root 'scripts\injector.mjs'), '--check-payload', '--theme-dir', $oversizedTheme)
  if ($oversizedPayloadTest.ExitCode -eq 0) { throw 'Node injector accepted an image over the 16 MB limit.' }
  $rendererTest = Invoke-QQSkinNative -FilePath $node.Path -ArgumentList @(
    (Join-Path $PSScriptRoot 'renderer-inject.test.mjs'))
  if ($rendererTest.ExitCode -ne 0) { throw 'Renderer auxiliary-window regression test failed.' }
  $bootstrapTest = Invoke-QQSkinNative -FilePath $node.Path -ArgumentList @(
    (Join-Path $PSScriptRoot 'injector-bootstrap.test.mjs'))
  if ($bootstrapTest.ExitCode -ne 0) { throw 'Injector early-bootstrap regression test failed.' }
  $oneShotTest = Invoke-QQSkinNative -FilePath $node.Path -ArgumentList @(
    (Join-Path $PSScriptRoot 'injector-one-shot.test.mjs'))
  if ($oneShotTest.ExitCode -ne 0) { throw 'Injector one-shot Browser ID regression test failed.' }
  $imageMetadataTest = Invoke-QQSkinNative -FilePath $node.Path -ArgumentList @(
    (Join-Path $PSScriptRoot 'image-metadata.test.mjs'))
  if ($imageMetadataTest.ExitCode -ne 0) { throw 'Image metadata regression test failed.' }

  Write-Host 'PASS: config transactions, restore scoping, state safety, argument quoting, and loopback CDP validation.'
} finally {
  Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
}
