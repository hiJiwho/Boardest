const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const ROOT = 'c:\\Users\\jiwho\\Documents\\boardest';
const VERSION = '5.5.0';

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
console.log(`Found ${existingAssets.length} of ${releaseAssets.length} release assets.`);
const assetsArg = existingAssets.map(f => `"${f}"`).join(' ');

const notesPath = path.join(ROOT, 'scripts', 'release_notes_v550.md');
if (!fs.existsSync(notesPath)) {
  console.error('Release notes file not found: ' + notesPath);
  process.exit(1);
}

for (const repo of ['hiJiwho/Boardest', 'hiJiwho/Boardest-Source-code']) {
  console.log(`\n========================================`);
  console.log(`Publishing release v${VERSION} to ${repo}...`);
  console.log(`========================================`);
  try {
    try {
      execSync(`gh release view v${VERSION} -R ${repo}`, { stdio: 'pipe' });
      console.log(`Tag v${VERSION} exists on ${repo}. Deleting to recreate fresh...`);
      execSync(`gh release delete v${VERSION} -R ${repo} -y`, { stdio: 'inherit' });
    } catch (_) {}

    const createCmd = `gh release create v${VERSION} -R ${repo} -F "${notesPath}" -t "🚀 Boardest v${VERSION} Official Ecosystem Overhaul Release" ${assetsArg}`;
    execSync(createCmd, { stdio: 'inherit' });
    console.log(`Successfully published release v${VERSION} to ${repo}!`);
  } catch (err) {
    console.error(`Error publishing to ${repo}:`, err.message);
  }
}

console.log(`\nAll releases published successfully!`);
