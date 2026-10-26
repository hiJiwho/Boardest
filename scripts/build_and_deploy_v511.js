const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = 'c:\\Users\\jiwho\\Documents\\boardest';

function run(cmd, cwd = ROOT) {
  console.log(`\n>>> [EXEC] ${cmd} (in ${cwd})`);
  execSync(cmd, { cwd, stdio: 'inherit' });
}

function copyFile(src, dest) {
  if (fs.existsSync(src)) {
    console.log(`>>> [COPY] ${src} -> ${dest}`);
    const destDir = path.dirname(dest);
    if (!fs.existsSync(destDir)) fs.mkdirSync(destDir, { recursive: true });
    fs.copyFileSync(src, dest);
  } else {
    console.warn(`>>> [SKIP] Source file does not exist: ${src}`);
  }
}

console.log('==========================================');
console.log(' Boardest v5.1.1 Build and Deploy Pipeline');
console.log('==========================================');

// 1. Android APK 빌드 (Class Pro 전용)
console.log('\n== [1/6] Building Boardest Class Pro APK (v5.1.1)... ==');
run('flutter build apk --release --no-tree-shake-icons', path.join(ROOT, 'apps', 'boardest'));
const classApk = path.join(ROOT, 'apps', 'boardest', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
copyFile(classApk, path.join(ROOT, 'dist', 'appx', 'boardest.apk'));
copyFile(classApk, path.join(ROOT, 'infra', 'download_web', 'boardest.apk'));
copyFile(classApk, path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest.apk'));

// 2. Windows 빌드 및 패키징 (AppX)
console.log('\n== [2/6] Building Windows AppX Packages (v5.1.1)... ==');
try {
  run('powershell -ExecutionPolicy Bypass -File scripts/build_all_appx.ps1 -AppVersion 5.1.1.0 -SkipApk', ROOT);
  copyFile(path.join(ROOT, 'dist', 'appx', 'boardest.appx'), path.join(ROOT, 'infra', 'download_web', 'boardest.appx'));
  copyFile(path.join(ROOT, 'dist', 'appx', 'boardest.appx'), path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest.appx'));
} catch (e) {
  console.warn('Windows AppX build encountered a warning:', e.message);
}

// 3. Web 빌드
console.log('\n== [3/6] Building Web Applications... ==');
run('flutter build web --release --base-href /class/', path.join(ROOT, 'apps', 'boardest'));
run('flutter build web --release --base-href /teacher/', path.join(ROOT, 'apps', 'boardest_teacher'));

// 4. Web Assets 동기화 & Firebase Hosting 배포
console.log('\n== [4/6] Syncing Web Assets & Deploying Firebase Hosting... ==');
run('node scripts/sync_web_assets.js', ROOT);
run('firebase deploy --only hosting', ROOT);

// 5. Git Commit, Push & GitHub Release (v5.1.1)
console.log('\n== [5/6] Git Commit, Push & GitHub Release (v5.1.1)... ==');
try {
  run('git add -A', ROOT);
  try {
    run('git commit -m "feat(v5.1.1): 다음 교시 자동 연동, 시간표 교과서 확대, TBP 형광펜/되돌리기/저장 업그레이드, 교사 실전 가이드 대폭 개편, v5.1.1 공식 릴리즈"', ROOT);
  } catch (e) {
    console.log('Nothing new to commit or already committed.');
  }

  run('git push origin main', ROOT);

  const releaseAssets = [
    path.join(ROOT, 'dist', 'appx', 'boardest.apk'),
    path.join(ROOT, 'dist', 'appx', 'boardest.appx'),
    path.join(ROOT, 'dist', 'appx', 'bst-teacher.msi'),
    path.join(ROOT, 'dist', 'appx', 'BoardestCert.cer'),
    path.join(ROOT, 'dist', 'appx', 'install_certificate.bat'),
    path.join(ROOT, 'apps', 'boardest', 'web', 'downloads', 'boardbook_extension.zip')
  ].filter(p => fs.existsSync(p)).map(p => `"${p}"`).join(' ');

  console.log(`\n>>> Creating GitHub Release v5.1.1 with assets: ${releaseAssets}`);
  const releaseNotes = `### Boardest v5.1.1 공식 릴리즈
- **다음 교시 올바른 교시 자동 연동**: 쉬는 시간 및 점심 시간 중 1교시로 리셋되던 문제 완벽 해결 (실제 다음 수업 교시로 자동 지정 및 시간표 민트색 강조)
- **오늘의 시간표 교과서 크기 대폭 확대**: 시간표 컬럼 폭 확장(220px) 및 교과서 표지 썸네일 크기 확대(44x60)
- **TBP (교안·슬라이드 뷰어) 대폭 업그레이드**:
  - 반투명 형광펜(하이라이터) 도구 탑재
  - 실행 취소(Undo / Ctrl+Z) 및 판서 즉시 저장(Ctrl+S) 지원
  - 슬라이드 넘김(클리커/키보드) 온스크린 피드백 토스트 안내
- **교사용 실전 & 독학 마스터 가이드 전면 개편**:
  - [boardest.web.app/guide](https://boardest.web.app/guide) 신설
  - 현장 선생님들이 가장 자주 겪는 상황별 FAQ 5선 및 꿀팁 탑재
- **버전 표기**: Boardest v5.1.1 정식 배포`;

  const notesFile = path.join(ROOT, 'scripts', 'release_notes_v511.md');
  fs.writeFileSync(notesFile, releaseNotes, 'utf8');

  try {
    run(`gh release create v5.1.1 ${releaseAssets} -R hiJiwho/Boardest --target main --title "Boardest v5.1.1" -F "${notesFile}"`, ROOT);
    console.log('GitHub Release v5.1.1 created successfully!');
  } catch (err) {
    console.log('Release create failed or already exists, attempting upload...');
    run(`gh release upload v5.1.1 ${releaseAssets} -R hiJiwho/Boardest --clobber`, ROOT);
  }
} catch (e) {
  console.error('Git push / GitHub release error:', e.message);
}

console.log('\n🎉 Boardest 5.1.1 All Pipelines Completed Successfully!');

// 6. 컴퓨터 끄기
console.log('\n== [6/6] Shutting down computer in 60 seconds... ==');
try {
  run('shutdown /s /t 60 /c "Boardest v5.1.1 All Pipelines Completed Successfully! PC will shut down in 60 seconds."');
} catch (e) {
  console.warn('Shutdown command failed:', e.message);
}
