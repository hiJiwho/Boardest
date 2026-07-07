$cacheDir = "$env:TEMP\boardest_icons_test"
if (!(Test-Path $cacheDir)) {
    New-Item -ItemType Directory -Path $cacheDir | Out-Null
}
Add-Type -AssemblyName System.Drawing

# 1. Map all shortcut files in the Start Menu by their name
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

# 2. Pre-cache UWP package family names to their install locations (extremely fast bulk lookup)
$uwpPkgs = @{}
Get-AppxPackage | ForEach-Object {
    if ($_.PackageFamilyName -and $_.InstallLocation) {
        $uwpPkgs[$_.PackageFamilyName.ToLower()] = $_.InstallLocation
    }
}

function Find-UwpLogo($installLocation) {
    # Check directly inside common directories (non-recursive first, extremely fast!)
    $subDirs = @("Assets", "VisualElements", "images", "")
    foreach ($sub in $subDirs) {
        $path = Join-Path $installLocation $sub
        if (Test-Path $path) {
            # Non-recursive first
            $pngs = Get-ChildItem -Path $path -Filter "*.png" -ErrorAction SilentlyContinue
            if ($pngs) {
                $preferred = $pngs | Where-Object { 
                    $_.Name -match "AppList|Logo|Square|Tile|Icon" -and 
                    $_.Name -notmatch "targetsize-(16|24|30|32|36|40)" 
                } | Select-Object -First 1
                if ($preferred) { return $preferred.FullName }
                return $pngs[0].FullName
            }
        }
    }
    
    # Only fallback to recursive search in Assets if root search returned nothing
    $assetsPath = Join-Path $installLocation "Assets"
    if (Test-Path $assetsPath) {
        $pngs = Get-ChildItem -Path $assetsPath -Filter "*.png" -Recurse -ErrorAction SilentlyContinue
        if ($pngs) {
            $preferred = $pngs | Where-Object { 
                $_.Name -match "AppList|Logo|Square|Tile|Icon" -and 
                $_.Name -notmatch "targetsize-(16|24|30|32|36|40)" 
            } | Select-Object -First 1
            if ($preferred) { return $preferred.FullName }
            return $pngs[0].FullName
        }
    }
    return $null
}

# Measure the time it takes to process ALL installed apps
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$apps = Get-StartApps
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
            # Pre-cached UWP package lookup
            elseif ($appId.Contains("!") -or $appId -match "^[A-Za-z0-9\.]+\_[a-z0-9]+") {
                $pfn = $appId.Split("!")[0].ToLower()
                if ($uwpPkgs.ContainsKey($pfn)) {
                    $installLocation = $uwpPkgs[$pfn]
                    if ($installLocation -and (Test-Path $installLocation)) {
                        $uwpLogo = Find-UwpLogo $installLocation
                        if ($uwpLogo -and (Test-Path $uwpLogo)) {
                            Copy-Item $uwpLogo $targetPng -Force
                            $iconPath = $targetPng
                        }
                    }
                }
            }
        }
    } catch {
        # Silent catch
    }
    
    # Return forward slashes for Flutter
    $displayIconPath = $iconPath -replace '\\', '/'
    
    $result += [PSCustomObject]@{
        Name = $name
        AppID = $appId
        IconPath = $displayIconPath
    }
}

$sw.Stop()
Write-Host "Processed $($apps.Count) apps in $($sw.Elapsed.TotalMilliseconds) ms"

# Output first 5 results to check formatting
$result | Select-Object -First 5 | ConvertTo-Json
