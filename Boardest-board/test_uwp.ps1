Add-Type -AssemblyName System.Drawing

function Find-UwpLogo($installLocation) {
    $subDirs = @("Assets", "images", "VisualElements", "Resources")
    foreach ($sub in $subDirs) {
        $path = Join-Path $installLocation $sub
        if (Test-Path $path) {
            $pngs = Get-ChildItem -Path $path -Filter "*.png" -Recurse -ErrorAction SilentlyContinue
            if ($pngs) {
                # Filter for preferred logo/applist filenames, excluding very small target sizes
                $preferred = $pngs | Where-Object { 
                    $_.Name -match "AppList|Logo|Square|Tile|Icon" -and 
                    $_.Name -notmatch "targetsize-(16|24|30|32|36|40)" 
                } | Select-Object -First 1
                if ($preferred) { return $preferred.FullName }
                
                # Fallback to any PNG in the asset directory
                return $pngs[0].FullName
            }
        }
    }
    
    # Root level non-recursive search fallback
    $rootPngs = Get-ChildItem -Path $installLocation -Filter "*.png" -ErrorAction SilentlyContinue
    if ($rootPngs) { return $rootPngs[0].FullName }
    return $null
}

# Test on a few packages
$pkgs = @("AppleInc.iCloud", "Microsoft.Copilot", "Microsoft.M365Companions", "Microsoft.XboxGamingOverlay")
foreach ($pname in $pkgs) {
    $pkg = Get-AppxPackage -Name $pname
    if ($pkg) {
        $logo = Find-UwpLogo $pkg.InstallLocation
        Write-Host "$pname -> Logo: $logo"
    } else {
        Write-Host "Package $pname not found"
    }
}
