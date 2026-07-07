$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (Test-Path $csc) {
    Write-Host "Compiling C# binaries..."
    & $csc /target:exe /out:watchdog.exe watchdog.cs
    & $csc /target:winexe /out:boardest_ppt_overlay.exe /lib:C:\Windows\Microsoft.NET\Framework64\v4.0.30319,C:\Windows\Microsoft.NET\Framework64\v4.0.30319\WPF /r:System.dll,System.Core.dll,WindowsBase.dll,PresentationCore.dll,PresentationFramework.dll,System.Xaml.dll boardest_ppt_overlay.cs
    & $csc /target:exe /out:boardest_ppt_helper.exe boardest_ppt_helper.cs
    
    # Copy to runner Release
    $releaseDir = "build\windows\x64\runner\Release"
    if (Test-Path $releaseDir) {
        Copy-Item "watchdog.exe" "$releaseDir\watchdog.exe" -Force
        Copy-Item "boardest_ppt_overlay.exe" "$releaseDir\boardest_ppt_overlay.exe" -Force
        Copy-Item "boardest_ppt_helper.exe" "$releaseDir\boardest_ppt_helper.exe" -Force
        Write-Host "Copied helpers to runner Release"
    }
    
    # Copy to outputs Release
    $outDir = "build\outputs\windows\Release"
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    Copy-Item "watchdog.exe" "$outDir\watchdog.exe" -Force
    Copy-Item "boardest_ppt_overlay.exe" "$outDir\boardest_ppt_overlay.exe" -Force
    Copy-Item "boardest_ppt_helper.exe" "$outDir\boardest_ppt_helper.exe" -Force
    Write-Host "Copied helpers to outputs Release"
    Write-Host "Done!"
} else {
    Write-Host "csc.exe not found!"
}
