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
console.log(' Boardest v5.3.0 Build and Deploy Pipeline');
console.log('============================================');

// 0. 필수 단위 테스트 실행 (Test Verification)
console.log('\n== [0/6] Running Mandatory Unit Tests... ==');
run('flutter test test/passkey_school_validation_test.dart test/tbp_pointer_resolution_test.dart test/school_schedule_sync_test.dart test/pro_launcher_and_neis_test.dart', path.join(ROOT, 'apps', 'boardest'));
console.log('>>> All mandatory unit tests passed successfully!');

// 1. Android APK 빌드 (Class Pro, BCLD 독립 APK, Teacher APK)
console.log('\n== [1/6] Building Boardest Class Pro APK (v5.3.0)... ==');
run('flutter build apk --release --no-tree-shake-icons', path.join(ROOT, 'apps', 'boardest'));
const classApk = path.join(ROOT, 'apps', 'boardest', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
copyFile(classApk, path.join(ROOT, 'dist', 'appx', 'boardest.apk'));
copyFile(classApk, path.join(ROOT, 'infra', 'download_web', 'boardest.apk'));
copyFile(classApk, path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest.apk'));

console.log('\n== Building Standalone Native BCLD APK (v5.3.0)... ==');
run('flutter build apk --release --no-tree-shake-icons --dart-define=BC_CLOUD_MODE=true -PisCloud=true', path.join(ROOT, 'apps', 'boardest'));
const bcldApk = path.join(ROOT, 'apps', 'boardest', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
copyFile(bcldApk, path.join(ROOT, 'dist', 'appx', 'bcld.apk'));
copyFile(bcldApk, path.join(ROOT, 'dist', 'appx', 'boardest-class-cloud.apk'));
copyFile(bcldApk, path.join(ROOT, 'infra', 'download_web', 'bcld.apk'));
copyFile(bcldApk, path.join(ROOT, 'infra', 'downloads_hub_web', 'bcld.apk'));

console.log('\n== Building Teacher APK (v5.3.0)... ==');
try {
  run('flutter build apk --release --no-tree-shake-icons', path.join(ROOT, 'apps', 'boardest_teacher'));
  const teacherApk = path.join(ROOT, 'apps', 'boardest_teacher', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
  copyFile(teacherApk, path.join(ROOT, 'dist', 'appx', 'bst-teacher.apk'));
  copyFile(teacherApk, path.join(ROOT, 'infra', 'download_web', 'bst-teacher.apk'));
  copyFile(teacherApk, path.join(ROOT, 'infra', 'downloads_hub_web', 'bst-teacher.apk'));
} catch (e) {
  console.warn('Teacher APK build warning:', e.message);
}

// 2. Windows 빌드 및 패키징 (AppX: Boardest, BCLD, Teacher MSI)
console.log('\n== [2/6] Building Windows AppX & MSI Packages (v5.3.0)... ==');
try {
  run('powershell -ExecutionPolicy Bypass -File scripts/build_all_appx.ps1 -AppVersion 5.3.0 -SkipApk', ROOT);
  copyFile(path.join(ROOT, 'dist', 'appx', 'boardest.appx'), path.join(ROOT, 'infra', 'download_web', 'boardest.appx'));
  copyFile(path.join(ROOT, 'dist', 'appx', 'boardest.appx'), path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest.appx'));
  copyFile(path.join(ROOT, 'dist', 'appx', 'bcld.appx'), path.join(ROOT, 'infra', 'download_web', 'bcld.appx'));
  copyFile(path.join(ROOT, 'dist', 'appx', 'bcld.appx'), path.join(ROOT, 'infra', 'downloads_hub_web', 'bcld.appx'));
  copyFile(path.join(ROOT, 'dist', 'appx', 'bst-teacher.msi'), path.join(ROOT, 'infra', 'download_web', 'bst-teacher.msi'));
  copyFile(path.join(ROOT, 'dist', 'appx', 'bst-teacher.msi'), path.join(ROOT, 'infra', 'downloads_hub_web', 'bst-teacher.msi'));
} catch (e) {
  console.warn('Windows AppX build encountered a warning:', e.message);
}

// 3. Web 빌드 (Base Href: '/')
console.log('\n== [3/6] Building Web Applications (Class, Teacher, Lite)... ==');
run('flutter build web --release --base-href /', path.join(ROOT, 'apps', 'boardest'));
run('flutter build web --release --base-href /', path.join(ROOT, 'apps', 'boardest_teacher'));
try {
  run('flutter build web --release --base-href /lite/', path.join(ROOT, 'apps', 'boardest_teacher_lite'));
} catch (e) {
  console.warn('Teacher lite web build warning:', e.message);
}

// 4. Web Assets 동기화 & Firebase Hosting 배포
console.log('\n== [4/6] Syncing Web Assets & Deploying Firebase Hosting... ==');
run('node scripts/sync_web_assets.js', ROOT);
run('firebase.cmd deploy --only hosting', ROOT);

// 5. Git Commit, Push & GitHub Release (v5.3.0)
console.log('\n== [5/6] Git Commit, Push & GitHub Release (v5.3.0)... ==');
try {
  run('git add -A', ROOT);
  try {
    run('git commit -m "feat(v5.3.0): force-update lockout, unified tbp-htmlp creation, native bcld, web tbp blocking, drive token fix, v5.3.0 release"', ROOT);
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
  ];

  if (fs.existsSync(path.join(ROOT, 'dist', 'appx', 'bst-teacher.apk'))) {
    releaseAssets.push(path.join(ROOT, 'dist', 'appx', 'bst-teacher.apk'));
  }

  const existingAssets = releaseAssets.filter(f => fs.existsSync(f));
  const assetsArg = existingAssets.map(f => `"${f}"`).join(' ');

  console.log(`>>> Uploading ${existingAssets.length} assets to GitHub Release v5.3.0...`);
  try {
    run(`gh release delete v5.3.0 -y`, ROOT);
  } catch (_) {}
  run(`gh release create v5.3.0 -F scripts/release_notes_v530.md -t "Boardest v5.3.0 Official Release" ${assetsArg}`, ROOT);
  console.log('>>> GitHub Release v5.3.0 created successfully!');
} catch (e) {
  console.error('GitHub push/release failed:', e.message);
}

// 6. 완료 알림 및 시스템 종료
console.log('\n============================================');
console.log(' 🎉 All Build & Deployment Tasks Finished!');
console.log(' System will shut down in 60 seconds...');
console.log('============================================');
try {
  run('shutdown.exe /s /t 60 /c "Boardest v5.3.0 build and deployment complete. Shutting down system."', ROOT);
} catch (e) {
  console.warn('Shutdown command failed:', e.message);
}
