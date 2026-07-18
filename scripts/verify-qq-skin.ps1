[CmdletBinding()]
param(
  [int]$Port = 9335,
  [string]$ScreenshotPath
)

$ErrorActionPreference = 'Stop'
$PortExplicit = $PSBoundParameters.ContainsKey('Port')
$injector = Join-Path $PSScriptRoot 'injector.mjs'
. (Join-Path $PSScriptRoot 'common-windows.ps1')

$operationLock = Enter-QQSkinOperationLock
$verifyExitCode = 1
try {
  $StatePath = Join-Path $env:LOCALAPPDATA 'CodexQQSkin\state.json'
  $state = Read-QQSkinState -Path $StatePath
  if (-not $PortExplicit -and $null -ne $state -and $state.port) { $Port = [int]$state.port }
  Assert-QQSkinPort -Port $Port
  $node = Get-QQSkinNodeRuntime
  $currentCodex = Get-QQSkinCodexInstall
  $codex = $currentCodex
  $cdpIdentity = Get-QQSkinVerifiedCdpIdentity -Port $Port -Codex $codex
  if ($null -eq $cdpIdentity -and $null -ne $state) {
    $savedCodex = Get-QQSkinCodexInstallFromState -State $state
    if ($null -ne $savedCodex -and
      -not (Test-QQSkinPathEqual -Left $savedCodex.Executable -Right $currentCodex.Executable)) {
      $savedIdentity = Get-QQSkinVerifiedCdpIdentity -Port $Port -Codex $savedCodex
      if ($null -ne $savedIdentity) {
        $codex = $savedCodex
        $cdpIdentity = $savedIdentity
      }
    }
  }
  if ($null -eq $cdpIdentity) {
    throw "No verified Codex CDP endpoint is active on loopback port $Port."
  }
  if ($null -ne $state -and $state.browserId -and "$($state.browserId)" -cne $cdpIdentity.BrowserId) {
    throw 'The active CDP browser does not match the saved Retro QQ Skin session; state was preserved.'
  }

  $arguments = @($injector, '--verify', '--port', "$Port", '--browser-id', $cdpIdentity.BrowserId,
    '--timeout-ms', '30000')
  if ($ScreenshotPath) { $arguments += @('--screenshot', $ScreenshotPath) }
  & $node.Path @arguments
  $verifyExitCode = $LASTEXITCODE
} finally {
  Exit-QQSkinOperationLock -Mutex $operationLock
}
exit $verifyExitCode
