$cacheDir = "$env:TEMP\boardest_icons_test"
if (!(Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir | Out-Null
}
Add-Type -AssemblyName System.Drawing

# Map all shortcut files in the Start Menu by their name
$shortcutPaths = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs"
)

$lnkMap = @{}
foreach ($dir in $shortcutPaths) {
    if (Test-Path $dir) {
        Get-ChildItem -Path $dir -Filter "*.lnk" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($_.Name).ToLower()
            # Save the shortest path or first occurrence
            if (!$lnkMap.ContainsKey($name)) {
                $lnkMap[$name] = $_.FullName
            }
        }
    }
}

$apps = Get-StartApps | Select-Object -First 30
$result = @()

foreach ($app in $apps) {
    $name = $app.Name
    $appId = $app.AppID
    $iconPath = ""
    
    # Generate safe filename
    $safeId = $appId -replace '[\\/:*?"<>|! ]', '_'
    $targetPng = Join-Path $cacheDir "$safeId.png"
    
    try {
        if (Test-Path $targetPng) {
            $iconPath = $targetPng
        } else {
            # 1. Try mapping to a physical shortcut file
            $lowerName = $name.ToLower()
            $resolvedPath = ""
            if ($lnkMap.ContainsKey($lowerName)) {
                $resolvedPath = $lnkMap[$lowerName]
            } elseif (Test-Path $appId) {
                $resolvedPath = $appId
            }
            
            if ($resolvedPath -ne "" -and (Test-Path $resolvedPath)) {
                $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($resolvedPath)
                $bmp = $icon.ToBitmap()
                $bmp.Save($targetPng, [System.Drawing.Imaging.ImageFormat]::Png)
                $icon.Dispose()
                $bmp.Dispose()
                $iconPath = $targetPng
            }
            # 2. If it's a UWP app (or registry app) and we couldn't get a Win32 icon
            elseif ($appId.Contains("!") -or $appId -match "^[A-Za-z0-9\.]+\_[a-z0-9]+") {
                $pfn = $appId.Split("!")[0]
                $pkg = Get-AppxPackage -PackageFamilyName $pfn -ErrorAction SilentlyContinue
                if ($pkg -and $pkg.InstallLocation) {
                    $manifestPath = Join-Path $pkg.InstallLocation "AppxManifest.xml"
                    if (Test-Path $manifestPath) {
                        [xml]$manifest = Get-Content $manifestPath
                        
                        $logoPath = ""
                        # Look inside visual elements first
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
            }
        }
    } catch {
        # Silent catch
    }
    
    $result += [PSCustomObject]@{
        Name = $name
        AppID = $appId
        IconPath = $iconPath
    }
}

$result | ConvertTo-Json
