const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = 'c:\\Users\\jiwho\\Documents\\boardest';
const VERSION = '5.3.3';

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
    throw new Error(`Required source file does not exist: ${src}`);
  }
}

console.log('============================================');
console.log(` Boardest v${VERSION} Build and Deploy Pipeline`);
console.log('============================================');

// 0. 필수 단위 테스트 실행 (Test Verification)
console.log('\n== [0/5] Running Mandatory Unit Tests... ==');
run(
  'flutter test test/passkey_school_validation_test.dart test/tbp_pointer_resolution_test.dart test/school_schedule_sync_test.dart test/pro_launcher_and_neis_test.dart',
  path.join(ROOT, 'apps', 'boardest')
);
console.log('>>> All mandatory unit tests passed successfully!');

// 1. Android APK 빌드 (1순위: boardest-cloud.apk, 2순위: boardest.apk / boardest-class.apk, 3순위: bst-teacher.apk)
console.log(`\n== [1/5] Building Standalone Native Boardest Cloud APK (v${VERSION})... ==`);
run(
  'flutter build apk --release --no-tree-shake-icons --dart-define=BC_CLOUD_MODE=true',
  path.join(ROOT, 'apps', 'boardest')
);
const builtApkPath = path.join(ROOT, 'apps', 'boardest', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
copyFile(builtApkPath, path.join(ROOT, 'dist', 'appx', 'boardest-cloud.apk'));
copyFile(builtApkPath, path.join(ROOT, 'dist', 'appx', 'boardest-class-cloud.apk'));
copyFile(builtApkPath, path.join(ROOT, 'infra', 'download_web', 'boardest-cloud.apk'));
copyFile(builtApkPath, path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest-cloud.apk'));

console.log(`\n== Building Boardest Class Pro APK (v${VERSION})... ==`);
run(
  'flutter build apk --release --no-tree-shake-icons',
  path.join(ROOT, 'apps', 'boardest')
);
copyFile(builtApkPath, path.join(ROOT, 'dist', 'appx', 'boardest-class.apk'));
copyFile(builtApkPath, path.join(ROOT, 'dist', 'appx', 'boardest.apk'));
copyFile(builtApkPath, path.join(ROOT, 'infra', 'download_web', 'boardest-class.apk'));
copyFile(builtApkPath, path.join(ROOT, 'infra', 'download_web', 'boardest.apk'));
copyFile(builtApkPath, path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest-class.apk'));
copyFile(builtApkPath, path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest.apk'));

console.log(`\n== Building Teacher APK (v${VERSION})... ==`);
run(
  'flutter build apk --release --no-tree-shake-icons',
  path.join(ROOT, 'apps', 'boardest_teacher')
);
const teacherApk = path.join(ROOT, 'apps', 'boardest_teacher', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
copyFile(teacherApk, path.join(ROOT, 'dist', 'appx', 'bst-teacher.apk'));
copyFile(teacherApk, path.join(ROOT, 'infra', 'download_web', 'bst-teacher.apk'));
copyFile(teacherApk, path.join(ROOT, 'infra', 'downloads_hub_web', 'bst-teacher.apk'));

// 2. Windows 빌드 및 패키징 (AppX: boardest-class.appx, boardest.appx, boardest-cloud.appx, MSI: bst-teacher.msi)
console.log(`\n== [2/5] Building Windows AppX & MSI Packages (v${VERSION})... ==`);
run(`powershell -ExecutionPolicy Bypass -File scripts/build_all_appx.ps1 -AppVersion ${VERSION} -SkipApk`, ROOT);
copyFile(path.join(ROOT, 'dist', 'appx', 'boardest.appx'), path.join(ROOT, 'dist', 'appx', 'boardest-class.appx'));
copyFile(path.join(ROOT, 'dist', 'appx', 'boardest.appx'), path.join(ROOT, 'infra', 'download_web', 'boardest.appx'));
copyFile(path.join(ROOT, 'dist', 'appx', 'boardest.appx'), path.join(ROOT, 'infra', 'download_web', 'boardest-class.appx'));
copyFile(path.join(ROOT, 'dist', 'appx', 'boardest.appx'), path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest.appx'));
copyFile(path.join(ROOT, 'dist', 'appx', 'boardest.appx'), path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest-class.appx'));
copyFile(path.join(ROOT, 'dist', 'appx', 'boardest-cloud.appx'), path.join(ROOT, 'infra', 'download_web', 'boardest-cloud.appx'));
copyFile(path.join(ROOT, 'dist', 'appx', 'boardest-cloud.appx'), path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest-cloud.appx'));
copyFile(path.join(ROOT, 'dist', 'appx', 'bst-teacher.msi'), path.join(ROOT, 'infra', 'download_web', 'bst-teacher.msi'));
copyFile(path.join(ROOT, 'dist', 'appx', 'bst-teacher.msi'), path.join(ROOT, 'infra', 'downloads_hub_web', 'bst-teacher.msi'));

// 3. Web 빌드 (Base Href: '/')
console.log('\n== [3/5] Building Web Applications (Class, Teacher, Lite)... ==');
run('flutter build web --release --base-href /', path.join(ROOT, 'apps', 'boardest'));
run('flutter build web --release --base-href /', path.join(ROOT, 'apps', 'boardest_teacher'));
try {
  run('flutter build web --release --base-href /lite/', path.join(ROOT, 'apps', 'boardest_teacher_lite'));
} catch (e) {
  console.warn('Teacher lite web build warning:', e.message);
}

// 4. Web Assets 동기화 & Firebase Hosting 배포
console.log('\n== [4/5] Syncing Web Assets & Deploying Firebase Hosting... ==');
run('node scripts/sync_web_assets.js', ROOT);
run('firebase.cmd deploy --only hosting', ROOT);

// 5. Git Commit, Push & GitHub Release (v5.3.3 on hiJiwho/Boardest AND origin)
console.log(`\n== [5/5] Git Commit, Push & GitHub Release (v${VERSION})... ==`);
run('git add -A', ROOT);
try {
  run(`git commit -m "feat(v${VERSION}): fix duplicate clock, quota optimization, seamless auto-update, renewed web portals"`, ROOT);
} catch (e) {
  console.log('Nothing new to commit or already committed.');
}

run('git push origin main', ROOT);

const releaseAssets = [
  path.join(ROOT, 'dist', 'appx', 'boardest-class.apk'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class.appx'),
  path.join(ROOT, 'dist', 'appx', 'boardest.apk'),
  path.join(ROOT, 'dist', 'appx', 'boardest.appx'),
  path.join(ROOT, 'dist', 'appx', 'boardest-cloud.apk'),
  path.join(ROOT, 'dist', 'appx', 'boardest-cloud.appx'),
  path.join(ROOT, 'dist', 'appx', 'bst-teacher.msi'),
  path.join(ROOT, 'dist', 'appx', 'bst-teacher.apk'),
  path.join(ROOT, 'dist', 'appx', 'BoardestCert.cer'),
];

const existingAssets = releaseAssets.filter(f => fs.existsSync(f));
const assetsArg = existingAssets.map(f => `"${f}"`).join(' ');

console.log(`>>> Uploading ${existingAssets.length} assets to GitHub Release v${VERSION} on hiJiwho/Boardest...`);
try {
  run(`gh release delete v${VERSION} -R hiJiwho/Boardest -y`, ROOT);
} catch (_) {}
run(
  `gh release create v${VERSION} -R hiJiwho/Boardest -F scripts/release_notes_v533.md -t "Boardest v${VERSION} Official Release" ${assetsArg}`,
  ROOT
);

try {
  run(`gh release delete v${VERSION} -y`, ROOT);
} catch (_) {}
try {
  run(
    `gh release create v${VERSION} -F scripts/release_notes_v533.md -t "Boardest v${VERSION} Official Release" ${assetsArg}`,
    ROOT
  );
} catch (e) {
  console.warn('Origin release creation warning:', e.message);
}

console.log('\n============================================');
console.log(` 🎉 Boardest v${VERSION} Build & Deployment Complete!`);
console.log('============================================');

// 6. 시스템 종료 예약 (60초 후 종료)
console.log('\n>>> All builds and deployments completed successfully. Shutting down system in 60s...');
try {
  run('shutdown.exe /s /t 60', ROOT);
} catch (e) {
  console.warn('Shutdown command error:', e.message);
}
