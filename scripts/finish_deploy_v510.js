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
console.log(' Boardest v5.1.0 Final Deploy & USB Sync');
console.log('==========================================');

// 1. Web Assets 동기화
console.log('\n== [1/5] Syncing Web Assets & Downloads... ==');
run('node scripts/sync_web_assets.js', ROOT);

// 2. Firebase Hosting 배포
console.log('\n== [2/5] Deploying to Firebase Hosting... ==');
run('firebase deploy --only hosting', ROOT);

// 3. Git Commit, Tag & Push
console.log('\n== [3/5] Git Commit, Push & GitHub Release (v5.1.0)... ==');
try {
  run('git add -A', ROOT);
  try {
    run('git commit -m "feat(v5.1.0): web.bst 통합, .pen.bst 4대 포맷 추출, 캔바 클리커 수정, 과목별/쉬는시간 판서 자동 연동, 교사 독학 가이드 추가, v5.1.0 공식 릴리즈"', ROOT);
  } catch (e) {
    console.log('Nothing new to commit or skipped.');
  }
  run('git push origin main', ROOT);
  run('git push public-release main', ROOT);

  const releaseAssets = [
    path.join(ROOT, 'dist', 'appx', 'boardest.apk'),
    path.join(ROOT, 'dist', 'appx', 'boardest.appx'),
    path.join(ROOT, 'dist', 'appx', 'BoardestCert.cer'),
    path.join(ROOT, 'dist', 'appx', 'install_certificate.bat'),
    path.join(ROOT, 'apps', 'boardest', 'web', 'downloads', 'boardbook_extension.zip')
  ].filter(p => fs.existsSync(p)).map(p => `"${p}"`).join(' ');

  try {
    run(`gh release create v5.1.0 ${releaseAssets} -R hiJiwho/Boardest --title "Boardest v5.1.0" --notes "Boardest v5.1.0 공식 릴리즈 (web.bst 통합, .pen.bst 4대 포맷 추출, 캔바 클리커 수정, 교사 독학 가이드)"`, ROOT);
    console.log('GitHub Release v5.1.0 created successfully!');
  } catch (err) {
    console.log('Release create failed or already exists, attempting upload...');
    run(`gh release upload v5.1.0 ${releaseAssets} -R hiJiwho/Boardest --clobber`, ROOT);
  }
} catch (e) {
  console.warn('GitHub push / release warning:', e.message);
}

// 4. USB 복사 (boardest.apk 와 boardest.appx 2개 복사!)
console.log('\n== [4/5] Copying v5.1.0 APK and AppX to USB... ==');
const targetDrives = ['E:\\', 'F:\\'];
for (const drive of targetDrives) {
  if (fs.existsSync(drive)) {
    console.log(`\n>>> [USB COPY] Detected ${drive}, copying v5.1.0 APK & AppX...`);
    const usbFolder = path.join(drive, 'Boardest_v5.1.0');
    if (!fs.existsSync(usbFolder)) fs.mkdirSync(usbFolder, { recursive: true });

    const apkSrc = path.join(ROOT, 'dist', 'appx', 'boardest.apk');
    const appxSrc = path.join(ROOT, 'dist', 'appx', 'boardest.appx');

    copyFile(apkSrc, path.join(drive, 'boardest.apk'));
    copyFile(apkSrc, path.join(usbFolder, 'boardest.apk'));
    copyFile(appxSrc, path.join(drive, 'boardest.appx'));
    copyFile(appxSrc, path.join(usbFolder, 'boardest.appx'));

    // 인증서 파일도 복사
    const certSrc = path.join(ROOT, 'dist', 'appx', 'BoardestCert.cer');
    const batSrc = path.join(ROOT, 'dist', 'appx', 'install_certificate.bat');
    copyFile(certSrc, path.join(usbFolder, 'BoardestCert.cer'));
    copyFile(batSrc, path.join(usbFolder, 'install_certificate.bat'));
  }
}

console.log('\n🎉 Boardest 5.1.0 All Pipelines Completed Successfully!');

// 5. 컴퓨터 끄기
console.log('\n== [5/5] Shutting down computer in 60 seconds... ==');
try {
  run('shutdown /s /t 60 /c "Boardest v5.1.0 All Pipelines Completed Successfully! PC will shut down in 60 seconds."');
} catch (e) {
  console.warn('Shutdown command failed:', e.message);
}
