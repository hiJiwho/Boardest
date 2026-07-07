$cacheDir = "$env:TEMP\boardest_icons_test"
if (!(Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir | Out-Null
}
Add-Type -AssemblyName System.Drawing

function Find-UwpLogo($installLocation) {
    $subDirs = @("", "Assets", "images", "VisualElements", "Resources")
    $filters = @("*AppList*.png", "*Logo*.png", "*Tile*.png", "*Icon*.png", "*.png")
    
    foreach ($sub in $subDirs) {
        $path = Join-Path $installLocation $sub
        if (Test-Path $path) {
            foreach ($filter in $filters) {
                # Find PNG files, prefer larger ones (exclude very small target sizes if possible)
                $found = Get-ChildItem -Path $path -Filter $filter -ErrorAction SilentlyContinue | 
                         Where-Object { $_.Name -notmatch "targetsize-(16|24|30|32|36|40)" } | 
                         Select-Object -First 1
                if ($found) {
                    return $found.FullName
                }
            }
            # If nothing found with exclusions, get the first one available
            $foundAny = Get-ChildItem -Path $path -Filter "*.png" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($foundAny) {
                return $foundAny.FullName
            }
        }
    }
    return $null
}

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
            if (!$lnkMap.ContainsKey($name)) {
                $lnkMap[$name] = $_.FullName
            }
        }
    }
}

$apps = Get-StartApps | Select-Object -First 40
$result = @()

foreach ($app in $apps) {
    $name = $app.Name
    $appId = $app.AppID
    $iconPath = ""
    
    $safeId = $appId -replace '[\\/:*?"<>|! ]', '_'
    $targetPng = Join-Path $cacheDir "$safeId.png"
    
    try {
        if (Test-Path $targetPng) {
            $iconPath = $targetPng
        } else {
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
            # 2. Try UWP package mapping
            elseif ($appId.Contains("!") -or $appId -match "^[A-Za-z0-9\.]+\_[a-z0-9]+") {
                $pfn = $appId.Split("!")[0]
                $pkg = Get-AppxPackage -PackageFamilyName $pfn -ErrorAction SilentlyContinue
                if ($pkg -and $pkg.InstallLocation) {
                    $uwpLogo = Find-UwpLogo $pkg.InstallLocation
                    if ($uwpLogo -and (Test-Path $uwpLogo)) {
                        Copy-Item $uwpLogo $targetPng -Force
                        $iconPath = $targetPng
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
