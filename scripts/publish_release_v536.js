const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const ROOT = 'c:\\Users\\jiwho\\Documents\\boardest';
const VERSION = '5.3.6';

const releaseAssets = [
  path.join(ROOT, 'dist', 'appx', 'boardest-teacher-installer.exe'),
  path.join(ROOT, 'dist', 'appx', 'Boardest-Teacher-Setup.exe'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class-installer.exe'),
  path.join(ROOT, 'dist', 'appx', 'Boardest-Class-Setup.exe'),
  path.join(ROOT, 'dist', 'appx', 'boardest-cloud-installer.exe'),
  path.join(ROOT, 'dist', 'appx', 'Boardest-Cloud-Setup.exe'),
  path.join(ROOT, 'dist', 'appx', 'boardest.msix'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class.msix'),
  path.join(ROOT, 'dist', 'appx', 'boardest-cloud.msix'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class-cloud.msix'),
  path.join(ROOT, 'dist', 'appx', 'boardest.appx'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class.appx'),
  path.join(ROOT, 'dist', 'appx', 'boardest-cloud.appx'),
  path.join(ROOT, 'dist', 'appx', 'bst-teacher-windows.zip'),
  path.join(ROOT, 'dist', 'appx', 'boardest-teacher-windows.zip'),
  path.join(ROOT, 'dist', 'appx', 'boardest-windows.zip'),
  path.join(ROOT, 'dist', 'appx', 'boardest-teacher.msi'),
  path.join(ROOT, 'dist', 'appx', 'bst-teacher.msi'),
  path.join(ROOT, 'dist', 'appx', 'boardest-teacher-lite.apk'),
  path.join(ROOT, 'dist', 'appx', 'bst-teacher-lite.apk'),
  path.join(ROOT, 'dist', 'appx', 'boardest-teacher.apk'),
  path.join(ROOT, 'dist', 'appx', 'bst-teacher.apk'),
  path.join(ROOT, 'dist', 'appx', 'boardest.apk'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class.apk'),
  path.join(ROOT, 'dist', 'appx', 'boardest-cloud.apk'),
  path.join(ROOT, 'dist', 'appx', 'BoardestCert.cer'),
];
const existingAssets = releaseAssets.filter(f => fs.existsSync(f));
const assetsArg = existingAssets.map(f => `"${f}"`).join(' ');

console.log('Existing assets count:', existingAssets.length);
try { execSync(`gh release delete v${VERSION} -R hiJiwho/Boardest -y`, { cwd: ROOT, stdio: 'inherit' }); } catch(_) {}
execSync(`gh release create v${VERSION} -R hiJiwho/Boardest -F scripts/release_notes_v536.md -t "Boardest v${VERSION} Official Release" ${assetsArg}`, { cwd: ROOT, stdio: 'inherit' });

try { execSync(`gh release delete v${VERSION} -y`, { cwd: ROOT, stdio: 'inherit' }); } catch(_) {}
try {
  execSync(`gh release create v${VERSION} -F scripts/release_notes_v536.md -t "Boardest v${VERSION} Official Release" ${assetsArg}`, { cwd: ROOT, stdio: 'inherit' });
} catch (e) {
  console.warn('Origin release creation warning:', e.message);
}
console.log('GitHub Release v5.3.6 successfully published!');
