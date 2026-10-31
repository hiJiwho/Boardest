const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const ROOT = 'c:\\Users\\jiwho\\Documents\\boardest';
const VERSION = '5.4.3';

const releaseAssets = [
  // Unified Online Installers (.exe)
  path.join(ROOT, 'dist', 'appx', 'boardest-installer.exe'),
  path.join(ROOT, 'dist', 'appx', 'installer.exe'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class.exe'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class-lite.exe'),
  path.join(ROOT, 'dist', 'appx', 'boardest-teacher.exe'),
  path.join(ROOT, 'dist', 'appx', 'boardest-cloud.exe'),
  path.join(ROOT, 'dist', 'appx', 'boardest-teacher-installer.exe'),
  path.join(ROOT, 'dist', 'appx', 'boardest-teacher-uninstaller.exe'),
  path.join(ROOT, 'dist', 'appx', 'Boardest-Teacher-Setup.exe'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class-installer.exe'),
  path.join(ROOT, 'dist', 'appx', 'Boardest-Class-Setup.exe'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class-lite-installer.exe'),
  path.join(ROOT, 'dist', 'appx', 'Boardest-Class-Lite-Setup.exe'),
  path.join(ROOT, 'dist', 'appx', 'boardest-cloud-installer.exe'),
  path.join(ROOT, 'dist', 'appx', 'Boardest-Cloud-Setup.exe'),
  path.join(ROOT, 'dist', 'appx', 'uninstall.exe'),

  // Modern MSIX & AppX Packages
  path.join(ROOT, 'dist', 'appx', 'boardest.msix'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class.msix'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class-lite.msix'),
  path.join(ROOT, 'dist', 'appx', 'boardest-cloud.msix'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class-cloud.msix'),
  path.join(ROOT, 'dist', 'appx', 'boardest.appx'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class.appx'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class-lite.appx'),
  path.join(ROOT, 'dist', 'appx', 'boardest-cloud.appx'),

  // Windows ZIP Releases
  path.join(ROOT, 'dist', 'appx', 'bst-teacher-windows.zip'),
  path.join(ROOT, 'dist', 'appx', 'boardest-windows.zip'),

  // Windows MSI Installers
  path.join(ROOT, 'dist', 'appx', 'boardest-teacher.msi'),
  path.join(ROOT, 'dist', 'appx', 'bst-teacher.msi'),

  // Android APKs
  path.join(ROOT, 'dist', 'appx', 'boardest-teacher-lite.apk'),
  path.join(ROOT, 'dist', 'appx', 'bst-teacher-lite.apk'),
  path.join(ROOT, 'dist', 'appx', 'boardest-teacher.apk'),
  path.join(ROOT, 'dist', 'appx', 'bst-teacher.apk'),
  path.join(ROOT, 'dist', 'appx', 'boardest.apk'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class.apk'),
  path.join(ROOT, 'dist', 'appx', 'boardest-cloud.apk'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class-lite.apk'),
  path.join(ROOT, 'dist', 'appx', 'bst-class-lite.apk'),

  // Certificate
  path.join(ROOT, 'dist', 'appx', 'BoardestCert.cer'),
];

const existingAssets = releaseAssets.filter(f => fs.existsSync(f));
const assetsArg = existingAssets.map(f => `"${f}"`).join(' ');

console.log('Existing assets count:', existingAssets.length);

// Delete v5.4.2 as requested by user
for (const repo of ['hiJiwho/Boardest', 'hiJiwho/Boardest-Source-code']) {
  try {
    execSync(`gh release delete v5.4.2 -R ${repo} -y`, { cwd: ROOT, stdio: 'inherit' });
  } catch (_) {}
  try {
    execSync(`gh release delete v${VERSION} -R ${repo} -y`, { cwd: ROOT, stdio: 'inherit' });
  } catch (_) {}
}

execSync(
  `gh release create v${VERSION} -R hiJiwho/Boardest -F scripts/release_notes_v543.md -t "Boardest v${VERSION} Official Release" ${assetsArg}`,
  { cwd: ROOT, stdio: 'inherit' }
);

try {
  execSync(
    `gh release create v${VERSION} -R hiJiwho/Boardest-Source-code -F scripts/release_notes_v543.md -t "Boardest v${VERSION} Official Release" ${assetsArg}`,
    { cwd: ROOT, stdio: 'inherit' }
  );
} catch (e) {
  console.warn('Source repo release creation warning:', e.message);
}

console.log(`GitHub Release v${VERSION} successfully published (and v5.4.2 removed)!`);
