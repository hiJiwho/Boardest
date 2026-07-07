$cacheDir = "$env:TEMP\boardest_icons_test"
if (!(Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir | Out-Null
}
Add-Type -AssemblyName System.Drawing

$apps = Get-StartApps | Select-Object -First 15
$result = @()

foreach ($app in $apps) {
    $name = $app.Name
    $appId = $app.AppID
    $iconPath = ""
    
    # Generate safe filename
    $safeId = $appId -replace '[\\/:*?"<>|! ]', '_'
    $targetPng = Join-Path $cacheDir "$safeId.png"
    
    try {
        if ($appId.Contains("!") -or $appId -match "^[A-Za-z0-9\.]+\_[a-z0-9]+") {
            # UWP app
            $pfn = $appId.Split("!")[0]
            $pkg = Get-AppxPackage -PackageFamilyName $pfn -ErrorAction SilentlyContinue
            if ($pkg -and $pkg.InstallLocation) {
                $manifestPath = Join-Path $pkg.InstallLocation "AppxManifest.xml"
                if (Test-Path $manifestPath) {
                    [xml]$manifest = Get-Content $manifestPath
                    
                    # Try VisualElements first as it usually has the direct assets
                    $logoPath = ""
                    $vis = $manifest.Package.Applications.Application.VisualElements
                    if ($vis) {
                        $logoPath = $vis.Square44x44Logo
                        if (!$logoPath) { $logoPath = $vis.Square150x150Logo }
                        if (!$logoPath) { $logoPath = $vis.Logo }
                    }
                    if (!$logoPath) {
                        $logoPath = $manifest.Package.Properties.Logo
                    }
                    
                    if ($logoPath) {
                        $fullLogoPath = Join-Path $pkg.InstallLocation $logoPath
                        if (!(Test-Path $fullLogoPath)) {
                            # Search for matching filename ignoring suffix (e.g. scale-200.png)
                            $logoName = [System.IO.Path]::GetFileNameWithoutExtension($logoPath)
                            $logoExt = [System.IO.Path]::GetExtension($logoPath)
                            $found = Get-ChildItem -Path $pkg.InstallLocation -Filter "$logoName*$logoExt" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                            if ($found) {
                                $fullLogoPath = $found.FullName
                            }
                        }
                        if (Test-Path $fullLogoPath) {
                            Copy-Item $fullLogoPath $targetPng -Force
                            $iconPath = $targetPng
                        }
                    }
                }
            }
        } else {
            # Win32 app
            if (Test-Path $appId) {
                $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($appId)
                $bmp = $icon.ToBitmap()
                $bmp.Save($targetPng, [System.Drawing.Imaging.ImageFormat]::Png)
                $icon.Dispose()
                $bmp.Dispose()
                $iconPath = $targetPng
            }
        }
    } catch {
        # Ignore errors
    }
    
    $result += [PSCustomObject]@{
        Name = $name
        AppID = $appId
        IconPath = $iconPath
    }
}

$result | ConvertTo-Json
