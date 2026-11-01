const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const ROOT = 'c:\\Users\\jiwho\\Documents\\boardest';
const VERSION = '5.5.0';

const cleanAssets = [
  // 1. Installer EXEs (기본, class, teacher, class lite, bcld)
  path.join(ROOT, 'dist', 'appx', 'boardest-installer.exe'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class.exe'),
  path.join(ROOT, 'dist', 'appx', 'boardest-teacher.exe'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class-lite.exe'),
  path.join(ROOT, 'dist', 'appx', 'boardest-cloud.exe'),

  // 2. Teacher ZIP (프로그램 압축한 zip)
  path.join(ROOT, 'dist', 'appx', 'bst-teacher-windows.zip'),

  // 3. MSIX (나머지 프로그램)
  path.join(ROOT, 'dist', 'appx', 'boardest.msix'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class.msix'),
  path.join(ROOT, 'dist', 'appx', 'boardest-cloud.msix'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class-lite.msix'),

  // 4. APK (모든 프로그램, teacher는 lite 버전)
  path.join(ROOT, 'dist', 'appx', 'boardest.apk'),
  path.join(ROOT, 'dist', 'appx', 'boardest-cloud.apk'),
  path.join(ROOT, 'dist', 'appx', 'boardest-class-lite.apk'),
  path.join(ROOT, 'dist', 'appx', 'boardest-teacher-lite.apk'),

  // 5. Root Certificate (신뢰 인증서)
  path.join(ROOT, 'dist', 'appx', 'BoardestCert.cer'),
];

for (const a of cleanAssets) {
  if (!fs.existsSync(a)) {
    console.error(`Asset not found: ${a}`);
    process.exit(1);
  }
}

console.log(`Verified all ${cleanAssets.length} streamlined assets exist.`);
const assetsArg = cleanAssets.map(f => `"${f}"`).join(' ');

const notesPath = path.join(ROOT, 'scripts', 'release_notes_v550.md');

// 1. Delete v5.5.0 on both repos first
for (const repo of ['hiJiwho/Boardest', 'hiJiwho/Boardest-Source-code']) {
  console.log(`\nDeleting existing release and tag v${VERSION} on ${repo}...`);
  try {
    execSync(`gh release delete v${VERSION} -R ${repo} -y --cleanup-tag`, { stdio: 'inherit' });
    console.log(`Deleted v${VERSION} on ${repo}.`);
  } catch (e) {
    console.log(`Release delete note: ${e.message}`);
  }
}

// 2. Create fresh streamlined release v5.5.0 on both repos
for (const repo of ['hiJiwho/Boardest', 'hiJiwho/Boardest-Source-code']) {
  console.log(`\n========================================`);
  console.log(`Re-creating streamlined release v${VERSION} on ${repo}...`);
  console.log(`========================================`);
  try {
    const createCmd = `gh release create v${VERSION} -R ${repo} -F "${notesPath}" -t "🚀 Boardest v${VERSION} Official Release" ${assetsArg}`;
    execSync(createCmd, { stdio: 'inherit' });
    console.log(`Successfully published streamlined release v${VERSION} to ${repo}!`);
  } catch (err) {
    console.error(`Error publishing to ${repo}:`, err.message);
    process.exit(1);
  }
}

console.log(`\nAll streamlined releases re-published successfully!`);
