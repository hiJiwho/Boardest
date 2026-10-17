param(
  [string]$Version = '4.0.9'
)

$ErrorActionPreference = 'Stop'
$Repository = 'hiJiwho/Boardest'
$ExpectedAssets = @(
  'boardest-windows.zip',
  'bst-teacher-windows.zip',
  'boardest.appx',
  'bst-teacher.appx',
  'bst-overlay-panser.appx',
  'boardest-class-lite.appx',
  'boardest.apk',
  'bst-teacher.apk',
  'bst-teacher-lite.apk',
  'bst-class-lite.apk',
  'BoardestCert.cer'
)
$DownloadArtifacts = @(
  'boardest.appx',
  'bst-teacher.appx',
  'bst-overlay-panser.appx',
  'boardest-class-lite.appx',
  'boardest.apk',
  'bst-teacher.apk',
  'bst-teacher-lite.apk',
  'bst-class-lite.apk',
  'BoardestCert.cer'
)
$VersionChecks = @{
  'https://boardest-class.web.app' = "application-version`" content=`"$Version`""
  'https://boardest-teacher.web.app' = "application-version`" content=`"$Version`""
  'https://boardest-teacher.web.app/lite/' = "application-version`" content=`"$Version`""
  'https://boardest-class-lite.web.app' = "application-version`" content=`"$Version`""
  'https://boardest-downloads.web.app' = "v$Version"
}
$HostingUrls = @(
  'https://boardest.web.app',
  'https://boardest-class.web.app',
  'https://boardest-class-lite.web.app',
  'https://boardest-tools.web.app',
  'https://boardest-class-pro.web.app',
  'https://boardest-demo.web.app',
  'https://boardest-teacher.web.app',
  'https://jiwhosboardest.web.app',
  'https://boardest-control.web.app',
  'https://boardest-teacher-oauth.web.app',
  'https://boardest-eat.web.app',
  'https://boardest-downloads.web.app',
  'https://bst-installer.web.app',
  'https://boardest-cloud-connect.web.app',
  'https://boardest-teacher.web.app/lite/'
)

$ReleaseOutput = & gh release view "v$Version" --repo $Repository --json tagName,assets
if ($LASTEXITCODE -ne 0) { throw "Could not read GitHub release v$Version." }
$Release = $ReleaseOutput | ConvertFrom-Json
if ($Release.tagName -ne "v$Version") { throw "Unexpected GitHub release tag: $($Release.tagName)." }
$PublishedAssets = @($Release.assets | ForEach-Object { $_.name })
$MissingAssets = @($ExpectedAssets | Where-Object { $_ -notin $PublishedAssets })
if ($MissingAssets.Count -gt 0) {
  throw "GitHub release is missing required assets: $($MissingAssets -join ', ')."
}
$EmptyAssets = @($Release.assets | Where-Object { $_.name -in $ExpectedAssets -and $_.size -le 0 })
if ($EmptyAssets.Count -gt 0) {
  throw "GitHub release contains empty assets: $(($EmptyAssets | ForEach-Object { $_.name }) -join ', ')."
}
Write-Host "GitHub release v$Version has all $($ExpectedAssets.Count) required source and app assets."

$RemoteMainOutput = & git ls-remote origin refs/heads/main
if ($LASTEXITCODE -ne 0) { throw 'Could not verify the pushed GitHub main branch.' }
$RemoteMain = ($RemoteMainOutput -split '\s+')[0]
$LocalMain = (& git rev-parse HEAD).Trim()
if ($RemoteMain -ne $LocalMain) { throw "GitHub main ($RemoteMain) does not match the released source commit ($LocalMain)." }
Write-Host "GitHub main is up to date at $LocalMain."

foreach ($url in $HostingUrls) {
  try {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
    if ($response.StatusCode -ne 200) { throw "HTTP $($response.StatusCode)." }
  } catch {
    throw "Firebase Hosting verification failed for $url : $($_.Exception.Message)"
  }
  Write-Host "Hosting verified: $url"
}

foreach ($url in $VersionChecks.Keys) {
  try {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
    if ($response.StatusCode -ne 200) { throw "HTTP $($response.StatusCode)." }
    if (-not $response.Content.Contains($VersionChecks[$url])) {
      throw "The deployed page does not identify release version $Version."
    }
  } catch {
    throw "Version verification failed for $url : $($_.Exception.Message)"
  }
  Write-Host "Version $Version verified: $url"
}

foreach ($artifact in $DownloadArtifacts) {
  $url = "https://bst-installer.web.app/$artifact"
  try {
    $response = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -TimeoutSec 60
    if ($response.StatusCode -ne 200) { throw "HTTP $($response.StatusCode)." }
    $contentLength = [int64]$response.Headers['Content-Length']
    if ($contentLength -le 0) { throw 'Empty download response.' }
  } catch {
    throw "Firebase download verification failed for $url : $($_.Exception.Message)"
  }
  Write-Host "Download verified: $url ($contentLength bytes)"
}

Write-Host "GitHub release assets, source push, all $($HostingUrls.Count) websites, and $($DownloadArtifacts.Count) Firebase downloads passed verification."
