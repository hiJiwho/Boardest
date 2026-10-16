param(
  [int]$ProcessId = 23092
)

try {
  $p = [System.Diagnostics.Process]::GetProcessById($ProcessId)
} catch {
  Write-Host "Process $ProcessId not found."
  exit 1
}

Write-Host "Monitoring deploy process $ProcessId..."
$p.WaitForExit()
$exitCode = $p.ExitCode
Write-Host "Process $ProcessId exited with code $exitCode."

if ($exitCode -eq 0) {
  Write-Host "Build & Deploy succeeded! Scheduling shutdown in 120s..."
  & shutdown.exe /s /t 120 /c "Boardest v4.0.7 빌드 및 배포 완료! 2분 후 PC가 자동 종료됩니다. 취소하려면 'shutdown /a'를 입력하세요."
} else {
  Write-Host "Build & Deploy failed with exit code $exitCode. Shutdown cancelled."
}
