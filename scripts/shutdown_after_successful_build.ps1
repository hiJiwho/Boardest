param(
  [Parameter(Mandatory)]
  [int]$BuildProcessId
)

$ErrorActionPreference = 'Stop'
$RootDir = Split-Path $PSScriptRoot -Parent
$DistDir = Join-Path $RootDir 'dist'
$LogPath = Join-Path $DistDir 'release_pipeline.log'
New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
$LogPath | Out-Null

function Write-ReleaseLog([string]$Message) {
  "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" |
    Add-Content -Path $LogPath
}

$BuildProcess = [System.Diagnostics.Process]::GetProcessById($BuildProcessId)
Write-ReleaseLog "Waiting for native release build process $BuildProcessId."
$BuildProcess.WaitForExit()
$BuildProcess.Refresh()

if ($BuildProcess.ExitCode -ne 0) {
  Write-ReleaseLog "Build failed with exit code $($BuildProcess.ExitCode); publishing and shutdown were skipped."
  exit $BuildProcess.ExitCode
}

Write-ReleaseLog 'Native builds passed; starting Firebase deployment and GitHub publishing.'
$DeployScript = Join-Path $PSScriptRoot 'deploy_all.bat'
$Command = '/d /c ""{0}" --skip-native >> "{1}" 2>&1"' -f $DeployScript, $LogPath
$DeployProcess = Start-Process -FilePath $env:ComSpec -ArgumentList $Command -WorkingDirectory $RootDir -WindowStyle Hidden -PassThru
$DeployProcess.WaitForExit()
$DeployProcess.Refresh()

if ($DeployProcess.ExitCode -ne 0) {
  Write-ReleaseLog "Publishing or online verification failed with exit code $($DeployProcess.ExitCode); shutdown was not scheduled. Review scripts\release_pipeline.log."
  exit $DeployProcess.ExitCode
}

Write-ReleaseLog 'Firebase hosting and GitHub uploads were verified; deploy_all.bat schedules shutdown.'
