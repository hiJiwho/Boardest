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

// 1. Android APK 빌드 (v1+v2 동시 서명 & 9999년 정식 키스토어)
console.log('\n== [1/6] Building Boardest Class Pro APK... ==');
run('flutter build apk --release --no-tree-shake-icons', path.join(ROOT, 'apps', 'boardest'));
const classApk = path.join(ROOT, 'apps', 'boardest', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
copyFile(classApk, path.join(ROOT, 'dist', 'appx', 'boardest.apk'));
copyFile(classApk, path.join(ROOT, 'infra', 'download_web', 'boardest.apk'));
copyFile(classApk, path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest.apk'));

console.log('\n== [2/6] Building Boardest Class Lite APK... ==');
run('flutter build apk --release --no-tree-shake-icons', path.join(ROOT, 'apps', 'boardest_class_lite'));
const liteApk = path.join(ROOT, 'apps', 'boardest_class_lite', 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
copyFile(liteApk, path.join(ROOT, 'dist', 'appx', 'bst-class-lite.apk'));
copyFile(liteApk, path.join(ROOT, 'dist', 'appx', 'boardest-class-lite.apk'));
copyFile(liteApk, path.join(ROOT, 'infra', 'download_web', 'bst-class-lite.apk'));
copyFile(liteApk, path.join(ROOT, 'infra', 'downloads_hub_web', 'bst-class-lite.apk'));

// 2. Windows 빌드 및 패키징 (AppX & MSI)
console.log('\n== [3/6] Building Windows AppX & MSI Packages... ==');
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
  copyFile(
    path.join(ROOT, 'dist', 'appx', 'boardest-class-lite.appx'),
    path.join(ROOT, 'infra', 'download_web', 'boardest-class-lite.appx')
  );
  copyFile(
    path.join(ROOT, 'dist', 'appx', 'boardest-class-lite.appx'),
    path.join(ROOT, 'infra', 'downloads_hub_web', 'boardest-class-lite.appx')
  );
  copyFile(
    path.join(ROOT, 'dist', 'appx', 'bst-teacher.msi'),
    path.join(ROOT, 'infra', 'download_web', 'bst-teacher.msi')
  );
  copyFile(
    path.join(ROOT, 'dist', 'appx', 'bst-teacher.msi'),
    path.join(ROOT, 'infra', 'downloads_hub_web', 'bst-teacher.msi')
  );
  copyFile(
    path.join(ROOT, 'dist', 'appx', 'BoardestCert.cer'),
    path.join(ROOT, 'infra', 'download_web', 'BoardestCert.cer')
  );
  copyFile(
    path.join(ROOT, 'dist', 'appx', 'BoardestCert.cer'),
    path.join(ROOT, 'infra', 'downloads_hub_web', 'BoardestCert.cer')
  );
  copyFile(
    path.join(ROOT, 'certs', 'install_certificate.bat'),
    path.join(ROOT, 'infra', 'download_web', 'install_certificate.bat')
  );
  copyFile(
    path.join(ROOT, 'certs', 'install_certificate.bat'),
    path.join(ROOT, 'infra', 'downloads_hub_web', 'install_certificate.bat')
  );
} catch (e) {
  console.warn('Windows AppX build encountered a warning/error:', e.message);
}

// 3. Web 빌드 및 동기화
console.log('\n== [4/6] Syncing Web Assets & Downloads... ==');
run('node scripts/sync_web_assets.js', ROOT);

// 4. Firebase Hosting 배포
console.log('\n== [5/6] Deploying Hosting to Firebase... ==');
run('firebase deploy --only hosting', ROOT);

// 5. Git Commit & Push & GitHub Official Release 생성
console.log('\n== [6/6] Pushing to Git Repositories and Creating GitHub Release... ==');
try {
  run('git add -A', ROOT);
  try {
    run('git commit -m "feat(v5.0.13): v1+v2 APK 서명 및 9999년 릴리즈 키스토어 통일, Windows 2999년 영구 인증서 원클릭 자동 설치기, v5.0.13 공식 릴리즈"', ROOT);
  } catch (e) {
    console.log('Commit skipped or nothing new to commit.');
  }
  run('git push origin main', ROOT);
  run('git push public-release main', ROOT);

  const releaseAssets = [
    path.join(ROOT, 'dist', 'appx', 'boardest.apk'),
    path.join(ROOT, 'dist', 'appx', 'bst-class-lite.apk'),
    path.join(ROOT, 'dist', 'appx', 'boardest.appx'),
    path.join(ROOT, 'dist', 'appx', 'boardest-class-lite.appx'),
    path.join(ROOT, 'dist', 'appx', 'bst-teacher.msi'),
    path.join(ROOT, 'dist', 'appx', 'BoardestCert.cer'),
    path.join(ROOT, 'dist', 'appx', 'install_certificate.bat'),
    path.join(ROOT, 'apps', 'boardest', 'web', 'downloads', 'boardbook_extension.zip')
  ].filter(p => fs.existsSync(p)).map(p => `"${p}"`).join(' ');

  const notesFile = path.join(ROOT, 'scripts', 'release_notes.md');
  try {
    run(`gh release create v5.0.13 ${releaseAssets} -R hiJiwho/Boardest --title "Boardest v5.0.13" -F "${notesFile}"`, ROOT);
    console.log('GitHub Release v5.0.13 created successfully!');
  } catch (err) {
    console.log('Release create failed or already exists, attempting upload...');
    run(`gh release upload v5.0.13 ${releaseAssets} -R hiJiwho/Boardest --clobber`, ROOT);
  }
} catch (e) {
  console.warn('GitHub push / release failed:', e.message);
}

// 6. USB 드라이브 복사 (E:, F: 가 연결되어 있을 경우 자동 복사)
const targetDrives = ['E:\\', 'F:\\'];
for (const drive of targetDrives) {
  if (fs.existsSync(drive)) {
    console.log(`\n>>> [USB COPY] Detected ${drive}, copying v5.0.13 release artifacts...`);
    const usbFolder = path.join(drive, 'Boardest_v5.0.13');
    if (!fs.existsSync(usbFolder)) fs.mkdirSync(usbFolder, { recursive: true });

    const filesToCopy = [
      { src: path.join(ROOT, 'dist', 'appx', 'boardest.apk'), name: 'boardest.apk' },
      { src: path.join(ROOT, 'dist', 'appx', 'bst-class-lite.apk'), name: 'bst-class-lite.apk' },
      { src: path.join(ROOT, 'dist', 'appx', 'boardest.appx'), name: 'boardest.appx' },
      { src: path.join(ROOT, 'dist', 'appx', 'boardest-class-lite.appx'), name: 'boardest-class-lite.appx' },
      { src: path.join(ROOT, 'dist', 'appx', 'bst-teacher.msi'), name: 'bst-teacher.msi' },
      { src: path.join(ROOT, 'dist', 'appx', 'bst-overlay-panser.appx'), name: 'bst-overlay-panser.appx' },
      { src: path.join(ROOT, 'dist', 'appx', 'BoardestCert.cer'), name: 'BoardestCert.cer' },
      { src: path.join(ROOT, 'certs', 'install_certificate.bat'), name: 'install_certificate.bat' },
      { src: path.join(ROOT, 'apps', 'boardest', 'web', 'downloads', 'boardbook_extension.zip'), name: 'boardbook_extension.zip' }
    ];

    for (const f of filesToCopy) {
      if (fs.existsSync(f.src)) {
        copyFile(f.src, path.join(drive, f.name));
        copyFile(f.src, path.join(usbFolder, f.name));
      }
    }
  }
}

console.log('\n🎉 Boardest 5.0.13 All Pipelines Completed Successfully!');
