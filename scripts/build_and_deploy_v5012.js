const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = 'c:\\Users\\jiwho\\Documents\\boardest';

function run(cmd, cwd = ROOT) {
  console.log(`\n>>> [EXEC] ${cmd} (in ${cwd})`);
  execSync(cmd, { cwd, stdio: 'inherit' });
}

function copyFile(src, dest) {
  console.log(`>>> [COPY] ${src} -> ${dest}`);
  fs.copyFileSync(src, dest);
}

function copyDir(src, dest) {
  console.log(`>>> [COPY DIR] ${src} -> ${dest}`);
  fs.cpSync(src, dest, { recursive: true, force: true });
}

console.log('==========================================');
console.log(' Boardest v5.0.12 Build and Deploy Pipeline');
console.log('==========================================');

// 1. Android APK 빌드 (2종: Class Pro & Class Lite)
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

// 2. Web 빌드 (3종)
console.log('\n== [3/5] Building Web Apps... ==');
run('flutter build web --release --base-href /', path.join(ROOT, 'apps', 'boardest'));
copyDir(
  path.join(ROOT, 'apps', 'boardest', 'build', 'web'),
  path.join(ROOT, 'infra', 'demo_web', 'class')
);

run('flutter build web --release --base-href /', path.join(ROOT, 'apps', 'boardest_teacher'));
copyDir(
  path.join(ROOT, 'apps', 'boardest_teacher', 'build', 'web'),
  path.join(ROOT, 'infra', 'demo_web', 'teacher')
);
copyDir(
  path.join(ROOT, 'apps', 'boardest_teacher', 'build', 'web'),
  path.join(ROOT, 'infra', 'teacher_timetable_web')
);

run('flutter build web --release --base-href /lite/', path.join(ROOT, 'apps', 'boardest_teacher_lite'));
copyDir(
  path.join(ROOT, 'apps', 'boardest_teacher_lite', 'build', 'web'),
  path.join(ROOT, 'infra', 'teacher_timetable_web', 'lite')
);

// Sync missing web manifests & FCM assets across web builds
run('node scripts/sync_web_assets.js', ROOT);

// 3. Firebase Hosting 배포
console.log('\n== [4/5] Deploying to Firebase Hosting... ==');
run('firebase deploy --only hosting', ROOT);

// 4. Git Commit & Push & Release
console.log('\n== [5/5] Committing, Pushing to GitHub and Creating Release... ==');
run('git add -A', ROOT);
try {
  run('git commit -m "feat(v5.0.12): TBP/HTMLP 3대 폴더 일원화, 32자리 ID 포인터 껍데기 아키텍처, boardest1217 암호화 백업 및 복원, 연쇄 삭제, 버전 5.0.12 갱신"', ROOT);
} catch (e) {
  console.log('Commit skipped or nothing new to commit.');
}
run('git push origin main', ROOT);
run('git push public-release main', ROOT);

const releaseAssets = [
  path.join(ROOT, 'infra', 'download_web', 'boardest.apk'),
  path.join(ROOT, 'infra', 'download_web', 'bst-class-lite.apk'),
  path.join(ROOT, 'infra', 'download_web', 'bst-teacher.apk'),
  path.join(ROOT, 'infra', 'download_web', 'bst-teacher-lite.apk'),
  path.join(ROOT, 'infra', 'download_web', 'BoardestCert.cer'),
  path.join(ROOT, 'infra', 'download_web', 'bst-teacher.msi'),
  path.join(ROOT, 'infra', 'download_web', 'boardest.appx')
].map(p => `"${p}"`).join(' ');

const notesFile = path.join(ROOT, 'scripts', 'release_notes.md');
run(`gh release create v5.0.12 ${releaseAssets} -R hiJiwho/Boardest --title "Boardest v5.0.12" -F "${notesFile}"`, ROOT);

console.log('\n==========================================');
console.log(' Boardest v5.0.12 Build and Deploy Succeeded!');
console.log('==========================================');
