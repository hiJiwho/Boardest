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

function copyDir(src, dest) {
  if (fs.existsSync(src)) {
    console.log(`>>> [COPY DIR] ${src} -> ${dest}`);
    fs.cpSync(src, dest, { recursive: true, force: true });
  } else {
    console.warn(`>>> [SKIP] Source directory does not exist: ${src}`);
  }
}

console.log('==========================================');
console.log(' Boardest v5.0.13 Build and Deploy Pipeline');
console.log('==========================================');

// 1. Android APK 빌드 (Class Pro & Class Lite & Teacher)
console.log('\n== [1/5] Building Boardest Class Pro APK... ==');
run('flutter build apk --release', path.join(ROOT, 'apps', 'boardest'));
copyFile(
  path.join(ROOT, 'apps', 'boardest', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk'),
  path.join(ROOT, 'infra', 'download_web', 'boardest.apk')
);
copyFile(
  path.join(ROOT, 'apps', 'boardest', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk'),
  path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest.apk')
);

console.log('\n== [2/5] Building Boardest Class Lite APK... ==');
run('flutter build apk --release', path.join(ROOT, 'apps', 'boardest_class_lite'));
copyFile(
  path.join(ROOT, 'apps', 'boardest_class_lite', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk'),
  path.join(ROOT, 'infra', 'download_web', 'bst-class-lite.apk')
);
copyFile(
  path.join(ROOT, 'apps', 'boardest_class_lite', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk'),
  path.join(ROOT, 'infra', 'downloads_hub_web', 'bst-class-lite.apk')
);

// 2. Windows 빌드 및 패키징 (AppX)
console.log('\n== [3/5] Building Windows AppX Packages... ==');
try {
  run('powershell -ExecutionPolicy Bypass -File scripts/build_all_appx.ps1 -AppVersion 5.0.13.0 -SkipApk', ROOT);
  copyFile(
    path.join(ROOT, 'dist', 'appx', 'boardest.appx'),
    path.join(ROOT, 'infra', 'download_web', 'boardest.appx')
  );
  copyFile(
    path.join(ROOT, 'dist', 'appx', 'boardest.appx'),
    path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest.appx')
  );
} catch (e) {
  console.warn('Windows AppX build encountered a warning/error:', e.message);
}

// 3. Web 빌드 및 동기화
console.log('\n== [4/5] Syncing Web Assets & Downloads... ==');
run('node scripts/sync_web_assets.js', ROOT);

// 4. Firebase Hosting 배포
console.log('\n== [5/5] Deploying Hosting to Firebase... ==');
run('firebase deploy --only hosting', ROOT);

console.log('\n🎉 Boardest 5.0.13 All Pipelines Completed Successfully!');
