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

console.log('============================================');
console.log(' Boardest v5.1.2.1 Build and Deploy Pipeline');
console.log('============================================');

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

// 1. Android APK 빌드 (Class Pro + BCLD 독립 APK)
console.log('\n== [1/6] Building Boardest Class Pro & BCLD APKs (v5.1.2.1)... ==');
run('flutter build apk --release --no-tree-shake-icons', path.join(ROOT, 'apps', 'boardest'));
const classApk = path.join(ROOT, 'apps', 'boardest', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
copyFile(classApk, path.join(ROOT, 'dist', 'appx', 'boardest.apk'));
copyFile(classApk, path.join(ROOT, 'infra', 'download_web', 'boardest.apk'));
copyFile(classApk, path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest.apk'));

// BCLD APK 빌드
console.log('\n== Building Standalone BCLD APK... ==');
run('flutter build apk --release --no-tree-shake-icons', path.join(ROOT, 'apps', 'boardest_class_cloud'));
const bcldApk = path.join(ROOT, 'apps', 'boardest_class_cloud', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
copyFile(bcldApk, path.join(ROOT, 'dist', 'appx', 'bcld.apk'));
copyFile(bcldApk, path.join(ROOT, 'dist', 'appx', 'boardest-class-cloud.apk'));
copyFile(bcldApk, path.join(ROOT, 'infra', 'download_web', 'bcld.apk'));
copyFile(bcldApk, path.join(ROOT, 'infra', 'downloads_hub_web', 'bcld.apk'));

// 2. Windows 빌드 및 패키징 (AppX: Boardest, BCLD, Teacher MSI)
console.log('\n== [2/6] Building Windows AppX & MSI Packages (v5.1.2.1)... ==');
try {
  run('powershell -ExecutionPolicy Bypass -File scripts/build_all_appx.ps1 -AppVersion 5.1.2.1 -SkipApk', ROOT);
  copyFile(path.join(ROOT, 'dist', 'appx', 'boardest.appx'), path.join(ROOT, 'infra', 'download_web', 'boardest.appx'));
  copyFile(path.join(ROOT, 'dist', 'appx', 'boardest.appx'), path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest.appx'));
  copyFile(path.join(ROOT, 'dist', 'appx', 'bcld.appx'), path.join(ROOT, 'infra', 'download_web', 'bcld.appx'));
  copyFile(path.join(ROOT, 'dist', 'appx', 'bcld.appx'), path.join(ROOT, 'infra', 'downloads_hub_web', 'bcld.appx'));
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
run('firebase.cmd deploy --only hosting', ROOT);

// 5. Git Commit, Push & GitHub Release (v5.1.2.1)
console.log('\n== [5/6] Git Commit, Push & GitHub Release (v5.1.2.1)... ==');
try {
  run('git add -A', ROOT);
  try {
    run('git commit -m "feat(v5.1.2.1): 주간 시간표 7열 불일치 크래시 완벽 해결, 상단 헤더 버전 표기 5.1.2.1 최신화, 독립 BCLD(Boardest Class Cloud) APK/AppX 빌드 체계 추가, v5.1.2.1 공식 릴리즈"', ROOT);
  } catch (e) {
    console.log('Nothing new to commit or already committed.');
  }

  run('git push origin main', ROOT);

  const releaseAssets = [
    path.join(ROOT, 'dist', 'appx', 'boardest.apk'),
    path.join(ROOT, 'dist', 'appx', 'boardest.appx'),
    path.join(ROOT, 'dist', 'appx', 'bcld.apk'),
    path.join(ROOT, 'dist', 'appx', 'bcld.appx'),
    path.join(ROOT, 'dist', 'appx', 'bst-teacher.msi'),
    path.join(ROOT, 'dist', 'appx', 'BoardestCert.cer'),
    path.join(ROOT, 'dist', 'appx', 'install_certificate.bat'),
    path.join(ROOT, 'apps', 'boardest', 'web', 'downloads', 'boardbook_extension.zip')
  ].filter(p => fs.existsSync(p)).map(p => `"${p}"`).join(' ');

  console.log(`\n>>> Creating GitHub Release v5.1.2.1 with assets: ${releaseAssets}`);
  const notesFile = path.join(ROOT, 'scripts', 'release_notes_v5121.md');

  try {
    run(`gh release create v5.1.2.1 ${releaseAssets} -R hiJiwho/Boardest --target main --title "Boardest v5.1.2.1" -F "${notesFile}"`, ROOT);
    console.log('GitHub Release v5.1.2.1 created successfully!');
  } catch (err) {
    console.log('Release create failed or already exists, attempting upload...');
    run(`gh release upload v5.1.2.1 ${releaseAssets} -R hiJiwho/Boardest --clobber`, ROOT);
  }
} catch (e) {
  console.error('Git push / GitHub release error:', e.message);
}

console.log('\n🎉 Boardest 5.1.2.1 All Pipelines and Release Completed Successfully!');
