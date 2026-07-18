[CmdletBinding()]
param([int]$Port = 9335)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic
. (Join-Path $PSScriptRoot 'common-windows.ps1')
. (Join-Path $PSScriptRoot 'theme-windows.ps1')

Assert-QQSkinPort -Port $Port
$SkillRoot = Split-Path -Parent $PSScriptRoot
$StateRoot = Join-Path $env:LOCALAPPDATA 'CodexQQSkin'
$paths = Initialize-QQSkinThemeStore -SkillRoot $SkillRoot -StateRoot $StateRoot
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
$startScript = Join-Path $PSScriptRoot 'start-qq-skin.ps1'
$restoreScript = Join-Path $PSScriptRoot 'restore-qq-skin.ps1'

$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$mutex = [System.Threading.Mutex]::new($false, "Local\CodexQQSkin.$sid.Tray")
$acquired = $false
try {
  try { $acquired = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $acquired = $true }
  if (-not $acquired) { exit 0 }

  $notify = [System.Windows.Forms.NotifyIcon]::new()
  $notify.Icon = [System.Drawing.SystemIcons]::Application
  $notify.Text = 'Codex Retro QQ Skin'
  $notify.Visible = $true
  $menu = [System.Windows.Forms.ContextMenuStrip]::new()
  $notify.ContextMenuStrip = $menu

  function Show-QQSkinTrayError {
    param([string]$Message)
    [void][System.Windows.Forms.MessageBox]::Show(
      $Message,
      'Codex Retro QQ Skin',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Error
    )
  }

  function Start-QQSkinPowerShell {
    param([Parameter(Mandatory = $true)][string]$Script, [string[]]$Arguments = @())
    $scriptToken = ConvertTo-QQSkinProcessArgument -Value $Script
    $argumentLine = '-NoProfile -ExecutionPolicy RemoteSigned -File ' + $scriptToken
    if ($Arguments.Count -gt 0) { $argumentLine += ' ' + ($Arguments -join ' ') }
    Start-Process -FilePath $powershell -ArgumentList $argumentLine | Out-Null
  }

  function Add-QQSkinTrayItem {
    param(
      [Parameter(Mandatory = $true)][System.Windows.Forms.ToolStripItemCollection]$Items,
      [Parameter(Mandatory = $true)][string]$Text,
      [AllowNull()][scriptblock]$Action,
      [bool]$Enabled = $true
    )
    $item = [System.Windows.Forms.ToolStripMenuItem]::new($Text)
    $item.Enabled = $Enabled
    if ($null -ne $Action) {
      $item.add_Click({
        try { & $Action } catch { Show-QQSkinTrayError -Message $_.Exception.Message }
      }.GetNewClosure())
    }
    [void]$Items.Add($item)
    return $item
  }

  function Rebuild-QQSkinTrayMenu {
    $menu.Items.Clear()
    $paused = Test-QQSkinPaused -StateRoot $StateRoot
    $state = $null
    try { $state = Read-QQSkinState -Path $paths.State } catch {}
    $active = $null
    try { $active = Read-QQSkinTheme -ThemeDirectory $paths.Active -SkipImageMetadata } catch {}
    $status = if ($paused) { '状态：已暂停' } elseif ($state) { '状态：运行中' } else { '状态：未运行' }
    if ($null -ne $active -and $null -ne $active.Theme -and $active.Theme.name) {
      $status += " · $($active.Theme.name)"
    }
    $null = Add-QQSkinTrayItem -Items $menu.Items -Text $status -Action $null -Enabled $false
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())

    $null = Add-QQSkinTrayItem -Items $menu.Items -Text '应用或重新应用' -Action {
      Set-QQSkinPaused -Paused $false -StateRoot $StateRoot | Out-Null
      Start-QQSkinPowerShell -Script $startScript -Arguments @('-Port', "$Port", '-PromptRestart')
    }
    $pauseText = if ($paused) { '继续显示皮肤' } else { '暂停皮肤' }
    $nextPaused = -not $paused
    $pauseAction = {
      Set-QQSkinPaused -Paused $nextPaused -StateRoot $StateRoot | Out-Null
    }.GetNewClosure()
    $null = Add-QQSkinTrayItem -Items $menu.Items -Text $pauseText -Action $pauseAction
    $null = Add-QQSkinTrayItem -Items $menu.Items -Text '更换背景图' -Action {
      $dialog = [System.Windows.Forms.OpenFileDialog]::new()
      $dialog.Title = '选择 Codex Retro QQ Skin 背景图'
      $dialog.Filter = 'Image files|*.png;*.jpg;*.jpeg;*.webp|All files|*.*'
      $dialog.Multiselect = $false
      try {
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
          $null = Set-QQSkinActiveTheme -ImagePath $dialog.FileName -Theme $null -StateRoot $StateRoot
          Set-QQSkinPaused -Paused $false -StateRoot $StateRoot | Out-Null
          $notify.ShowBalloonTip(1800, 'Codex Retro QQ Skin', '背景图已更新。', [System.Windows.Forms.ToolTipIcon]::Info)
        }
      } finally {
        $dialog.Dispose()
      }
    }
    $null = Add-QQSkinTrayItem -Items $menu.Items -Text '保存当前主题' -Action {
      $name = [Microsoft.VisualBasic.Interaction]::InputBox('输入主题名称：', '保存 Codex Retro QQ Skin 主题', '')
      if ($name.Trim()) {
        $saved = Save-QQSkinCurrentTheme -Name $name -StateRoot $StateRoot
        $notify.ShowBalloonTip(1800, 'Codex Retro QQ Skin', "已保存：$($saved.Theme.name)", [System.Windows.Forms.ToolTipIcon]::Info)
      }
    }

    $savedMenu = [System.Windows.Forms.ToolStripMenuItem]::new('已保存主题')
    $savedThemes = @(Get-QQSkinSavedThemes -StateRoot $StateRoot -SkipImageMetadata)
    if ($savedThemes.Count -eq 0) {
      $empty = [System.Windows.Forms.ToolStripMenuItem]::new('暂无已保存主题')
      $empty.Enabled = $false
      [void]$savedMenu.DropDownItems.Add($empty)
    } else {
      foreach ($saved in $savedThemes) {
        $savedPath = $saved.Path
        $savedName = $saved.Name
        $savedAction = {
          $null = Use-QQSkinSavedTheme -ThemeDirectory $savedPath -StateRoot $StateRoot
          Set-QQSkinPaused -Paused $false -StateRoot $StateRoot | Out-Null
          $notify.ShowBalloonTip(1800, 'Codex Retro QQ Skin', "已应用：$savedName", [System.Windows.Forms.ToolTipIcon]::Info)
        }.GetNewClosure()
        $null = Add-QQSkinTrayItem -Items $savedMenu.DropDownItems -Text $savedName -Action $savedAction
      }
    }
    [void]$menu.Items.Add($savedMenu)

    $null = Add-QQSkinTrayItem -Items $menu.Items -Text '打开图片文件夹' -Action {
      Start-Process -FilePath explorer.exe -ArgumentList @($paths.Images) | Out-Null
    }
    [void]$menu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
    $null = Add-QQSkinTrayItem -Items $menu.Items -Text '完全恢复 Codex' -Action {
      Start-QQSkinPowerShell -Script $restoreScript -Arguments @(
        '-Port', "$Port", '-RestoreBaseTheme', '-PromptRestart'
      )
      $notify.Visible = $false
      [System.Windows.Forms.Application]::Exit()
    }
    $null = Add-QQSkinTrayItem -Items $menu.Items -Text '退出托盘' -Action {
      $notify.Visible = $false
      [System.Windows.Forms.Application]::Exit()
    }
  }

  $menu.add_Opening({ Rebuild-QQSkinTrayMenu })
  $notify.add_DoubleClick({
    try {
      Set-QQSkinPaused -Paused $false -StateRoot $StateRoot | Out-Null
      Start-QQSkinPowerShell -Script $startScript -Arguments @('-Port', "$Port", '-PromptRestart')
    } catch {
      Show-QQSkinTrayError -Message $_.Exception.Message
    }
  })
  [System.Windows.Forms.Application]::Run()
} finally {
  if ($null -ne $notify) { $notify.Dispose() }
  if ($acquired) { try { $mutex.ReleaseMutex() } catch {} }
  $mutex.Dispose()
}
