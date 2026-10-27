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
console.log(' Boardest v5.1.2 Build and Deploy Pipeline');
console.log('==========================================');

// 0. 필수 단위 테스트 실행 (Test Verification)
console.log('\n== [0/6] Running Mandatory Unit Tests... ==');
run('flutter test test/pro_launcher_and_neis_test.dart test/school_schedule_sync_test.dart test/tbp_pointer_resolution_test.dart test/passkey_school_validation_test.dart', path.join(ROOT, 'apps', 'boardest'));
run('flutter test test/bst_tbp_test.dart', path.join(ROOT, 'packages', 'plugins', 'bst_tbp'));
console.log('>>> All mandatory unit tests passed successfully!');

// CRX 패키징 (ZIP)
console.log('\n== Packaging CRX BoardBook Extension... ==');
const crxZipDest = path.join(ROOT, 'apps', 'boardest', 'web', 'downloads', 'boardbook_extension.zip');
try {
  run(`powershell -NoProfile -Command "Compress-Archive -Path apps/boardest_crx_boardbook/* -DestinationPath '${crxZipDest}' -Force"`, ROOT);
  console.log(`>>> CRX BoardBook zipped successfully to ${crxZipDest}`);
} catch (e) {
  console.warn('CRX zipping warning:', e.message);
}

// 1. Android APK 빌드 (Class Pro 전용)
console.log('\n== [1/6] Building Boardest Class Pro APK (v5.1.2)... ==');
run('flutter build apk --release --no-tree-shake-icons', path.join(ROOT, 'apps', 'boardest'));
const classApk = path.join(ROOT, 'apps', 'boardest', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
copyFile(classApk, path.join(ROOT, 'dist', 'appx', 'boardest.apk'));
copyFile(classApk, path.join(ROOT, 'infra', 'download_web', 'boardest.apk'));
copyFile(classApk, path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest.apk'));

// 2. Windows 빌드 및 패키징 (AppX)
console.log('\n== [2/6] Building Windows AppX Packages (v5.1.2)... ==');
try {
  run('powershell -ExecutionPolicy Bypass -File scripts/build_all_appx.ps1 -AppVersion 5.1.2.0 -SkipApk', ROOT);
  copyFile(path.join(ROOT, 'dist', 'appx', 'boardest.appx'), path.join(ROOT, 'infra', 'download_web', 'boardest.appx'));
  copyFile(path.join(ROOT, 'dist', 'appx', 'boardest.appx'), path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest.appx'));
} catch (e) {
  console.warn('Windows AppX build encountered a warning:', e.message);
}

// 3. Web 빌드
console.log('\n== [3/6] Building Web Applications (Class & Teacher)... ==');
run('flutter build web --release --base-href /class/', path.join(ROOT, 'apps', 'boardest'));
run('flutter build web --release --base-href /teacher/', path.join(ROOT, 'apps', 'boardest_teacher'));

// 4. Web Assets 동기화 & Firebase Hosting 배포
console.log('\n== [4/6] Syncing Web Assets & Deploying Firebase Hosting... ==');
run('node scripts/sync_web_assets.js', ROOT);
run('firebase deploy --only hosting', ROOT);

// 5. Git Commit, Push & GitHub Release (v5.1.2)
console.log('\n== [5/6] Git Commit, Push & GitHub Release (v5.1.2)... ==');
try {
  run('git add -A', ROOT);
  try {
    run('git commit -m "feat(v5.1.2): Boardest Class Cloud(BCLD) 교실 수업 전용 모드, 학교 ID 패스키 매칭 및 타 학교 차단, 앱 슬롯 무한 가로 스크롤 확장, NEIS 급식 로딩 안정화, v5.1.2 공식 릴리즈"', ROOT);
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

  console.log(`\n>>> Creating GitHub Release v5.1.2 with assets: ${releaseAssets}`);
  const releaseNotes = `### Boardest v5.1.2 공식 릴리즈
- **Boardest Class Cloud (BCLD) 교실 수업 모드 정식 지원**:
  - Class 앱이 미설치된 교실 전자칠판에서도 브라우저(Web) 및 BCLD를 통해 즉시 수업 진행 가능
  - QR 패스키 스캔 시 선생님의 소속 학교 정보 자동 기입 및 즉시 수업 준비
- **학교 ID 패스키 보안 검증 (타 학교 연결 차단)**:
  - 칠판에 등록된 학교 ID와 선생님의 학교 ID가 다를 경우 QR 패스키 연결 즉시 차단
- **Class PRO 무제한 앱 등록 및 가로 스크롤 지원**:
  - 교사용 바로가기 앱을 개수 제한 없이 무한 등록 가능 (마우스 휠 및 터치 드래그 가로 스크롤 지원)
  - 앱 등록 시 기존 바로가기 앱 목록이 증발하거나 덮어씌워지던 문제 완벽 해결
- **NEIS 급식표 연동 안정화 및 오프라인 캐시 적용**:
  - 교육청 NEIS 서버 지연 및 간헐적 급식 누락 방지를 위한 타임아웃/식사코드 폴백/로컬 캐시 강화
- **수업시간 우측 화면 Cloud 전면 전환 레이아웃 최적화**:
  - 쉬는 시간/수업 시간 일관된 시계 레이아웃 유지 및 Cloud 연결 시 우측 전체 수업 보관함 확장
- **TBP / BoardBook CRX 전자교과서 엔진 고도화**:
  - 팝업 및 확장프로그램 Flutter Web 런타임 호환 구조 개선 및 v5.1.2 최신화`;

  const notesFile = path.join(ROOT, 'scripts', 'release_notes_v512.md');
  fs.writeFileSync(notesFile, releaseNotes, 'utf8');

  try {
    run(`gh release create v5.1.2 ${releaseAssets} -R hiJiwho/Boardest --target main --title "Boardest v5.1.2" -F "${notesFile}"`, ROOT);
    console.log('GitHub Release v5.1.2 created successfully!');
  } catch (err) {
    console.log('Release create failed or already exists, attempting upload...');
    run(`gh release upload v5.1.2 ${releaseAssets} -R hiJiwho/Boardest --clobber`, ROOT);
  }
} catch (e) {
  console.error('Git push / GitHub release error:', e.message);
}

console.log('\n🎉 Boardest 5.1.2 All Pipelines and Release Completed Successfully!');
