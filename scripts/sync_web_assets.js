const fs = require('fs');
const path = require('path');

const ROOT = 'c:\\Users\\jiwho\\Documents\\boardest';

function copyFileSafe(src, dest) {
  if (fs.existsSync(src)) {
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.copyFileSync(src, dest);
    console.log(`[SYNC FILE] ${src} -> ${dest}`);
  } else {
    console.warn(`[WARN] Source file not found: ${src}`);
  }
}

function copyDirSafe(src, dest) {
  if (fs.existsSync(src)) {
    fs.mkdirSync(dest, { recursive: true });
    fs.cpSync(src, dest, { recursive: true, force: true });
    console.log(`[SYNC DIR] ${src} -> ${dest}`);
  } else {
    console.warn(`[WARN] Source dir not found: ${src}`);
  }
}

console.log('=== Syncing Web Assets for Boardest Teacher ===');

const teacherBuildWeb = path.join(ROOT, 'apps', 'boardest_teacher', 'build', 'web');
const teacherWeb = path.join(ROOT, 'apps', 'boardest_teacher', 'web');
const flutterAssets = path.join(ROOT, 'apps', 'boardest_teacher', 'build', 'flutter_assets');
const teacherAssets = path.join(teacherBuildWeb, 'assets');

// 1. web/ 루트 정적 파일 복사 (manifest.json, sw 등)
const staticFiles = [
  'manifest.json',
  'firebase-messaging-sw.js',
  'favicon.png',
  'logo.png',
  'passkey.html'
];

for (const file of staticFiles) {
  copyFileSafe(path.join(teacherWeb, file), path.join(teacherBuildWeb, file));
}

// 2. FCM Push Scope 폴더 복사
copyDirSafe(
  path.join(teacherWeb, 'firebase-cloud-messaging-push-scope'),
  path.join(teacherBuildWeb, 'firebase-cloud-messaging-push-scope')
);

// 3. AssetManifest 및 FontManifest 생성/복사
fs.mkdirSync(teacherAssets, { recursive: true });

// FontManifest.json
if (fs.existsSync(path.join(flutterAssets, 'FontManifest.json'))) {
  copyFileSafe(
    path.join(flutterAssets, 'FontManifest.json'),
    path.join(teacherAssets, 'FontManifest.json')
  );
} else if (fs.existsSync(path.join(ROOT, 'infra', 'demo_web', 'teacher', 'assets', 'FontManifest.json'))) {
  copyFileSafe(
    path.join(ROOT, 'infra', 'demo_web', 'teacher', 'assets', 'FontManifest.json'),
    path.join(teacherAssets, 'FontManifest.json')
  );
}

// AssetManifest.bin
let assetBinPath = null;
if (fs.existsSync(path.join(flutterAssets, 'AssetManifest.bin'))) {
  assetBinPath = path.join(flutterAssets, 'AssetManifest.bin');
} else if (fs.existsSync(path.join(ROOT, 'infra', 'demo_web', 'teacher', 'assets', 'AssetManifest.bin'))) {
  assetBinPath = path.join(ROOT, 'infra', 'demo_web', 'teacher', 'assets', 'AssetManifest.bin');
}

if (assetBinPath) {
  copyFileSafe(assetBinPath, path.join(teacherAssets, 'AssetManifest.bin'));
  // AssetManifest.bin.json 생성 (Base64 of AssetManifest.bin)
  const binBuf = fs.readFileSync(assetBinPath);
  const base64Str = binBuf.toString('base64');
  fs.writeFileSync(path.join(teacherAssets, 'AssetManifest.bin.json'), JSON.stringify(base64Str), 'utf8');
  console.log(`[GEN] Generated AssetManifest.bin.json (${base64Str.length} chars)`);
}

// NOTICES
if (fs.existsSync(path.join(ROOT, 'infra', 'demo_web', 'teacher', 'assets', 'NOTICES'))) {
  copyFileSafe(
    path.join(ROOT, 'infra', 'demo_web', 'teacher', 'assets', 'NOTICES'),
    path.join(teacherAssets, 'NOTICES')
  );
}

// 4. apps/boardest_teacher_lite 빌드 결과를 teacher/build/web/lite 에 복사
const liteBuildWeb = path.join(ROOT, 'apps', 'boardest_teacher_lite', 'build', 'web');
if (fs.existsSync(liteBuildWeb)) {
  copyDirSafe(liteBuildWeb, path.join(teacherBuildWeb, 'lite'));
  // lite 내부에도 FCM SW 복사
  copyDirSafe(
    path.join(teacherWeb, 'firebase-cloud-messaging-push-scope'),
    path.join(teacherBuildWeb, 'lite', 'firebase-cloud-messaging-push-scope')
  );
}

// 5. infra/demo_web/teacher 및 infra/teacher_timetable_web 에도 전체 복사
copyDirSafe(teacherBuildWeb, path.join(ROOT, 'infra', 'demo_web', 'teacher'));
copyDirSafe(teacherBuildWeb, path.join(ROOT, 'infra', 'teacher_timetable_web'));

// 6. Boardest Class Web 동기화
console.log('=== Syncing Web Assets for Boardest Class ===');
const classBuildWeb = path.join(ROOT, 'apps', 'boardest', 'build', 'web');
const classWeb = path.join(ROOT, 'apps', 'boardest', 'web');
const classAssets = path.join(classBuildWeb, 'assets');

const classStaticFiles = [
  'manifest.json',
  'firebase-messaging-sw.js',
  'favicon.png',
  'passkey.html'
];
for (const file of classStaticFiles) {
  copyFileSafe(path.join(classWeb, file), path.join(classBuildWeb, file));
}
fs.mkdirSync(classAssets, { recursive: true });
if (fs.existsSync(path.join(ROOT, 'infra', 'demo_web', 'class', 'assets', 'FontManifest.json'))) {
  copyFileSafe(path.join(ROOT, 'infra', 'demo_web', 'class', 'assets', 'FontManifest.json'), path.join(classAssets, 'FontManifest.json'));
}
if (fs.existsSync(path.join(ROOT, 'infra', 'demo_web', 'class', 'assets', 'AssetManifest.bin'))) {
  copyFileSafe(path.join(ROOT, 'infra', 'demo_web', 'class', 'assets', 'AssetManifest.bin'), path.join(classAssets, 'AssetManifest.bin'));
  const binBuf = fs.readFileSync(path.join(ROOT, 'infra', 'demo_web', 'class', 'assets', 'AssetManifest.bin'));
  fs.writeFileSync(path.join(classAssets, 'AssetManifest.bin.json'), JSON.stringify(binBuf.toString('base64')), 'utf8');
}
copyDirSafe(classBuildWeb, path.join(ROOT, 'infra', 'demo_web', 'class'));

console.log('=== Web Assets Sync Complete! ===');
