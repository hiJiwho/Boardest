#!/usr/bin/env node

/**
 * Boardest Plugin CLI
 * Commands:
 *   npx boardest-plugin init <plugin-name>
 *   npx boardest-plugin dev
 *   npx boardest-plugin bundle
 *   npx boardest-plugin publish
 */

const fs = require('fs');
const path = require('path');
const http = require('http');

const args = process.argv.slice(2);
const command = args[0] || 'help';

console.log('🧩 [Boardest Plugin CLI v1.0.0]');

switch (command) {
  case 'init': {
    const pluginName = args[1] || 'my-boardest-plugin';
    const targetDir = path.resolve(process.cwd(), pluginName);
    if (fs.existsSync(targetDir)) {
      console.error(`❌ 디렉터리가 이미 존재합니다: ${targetDir}`);
      process.exit(1);
    }
    fs.mkdirSync(targetDir, { recursive: true });

    // plugin.json
    const manifest = {
      $schema: 'https://boardest.web.app/schemas/plugin.v1.json',
      id: `plugin.${pluginName.toLowerCase().replace(/[^a-z0-9]/g, '.')}`,
      name: pluginName,
      version: '1.0.0',
      description: '교실 전자칠판 및 학생/교사를 위한 인터랙티브 HTML 플러그인',
      author: {
        name: '개발자 이름',
        email: 'dev@school.kr'
      },
      targets: ['class', 'student', 'teacher'],
      icon: '🧩',
      permissions: ['local_storage', 'toast_ui']
    };
    fs.writeFileSync(path.join(targetDir, 'plugin.json'), JSON.stringify(manifest, null, 2), 'utf8');

    // index.html
    const html = `<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${pluginName}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background: #14171F;
      color: #FFFFFF;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      padding: 16px;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
    }
    .card {
      background: #1E222D;
      border: 1px solid rgba(0, 245, 212, 0.4);
      border-radius: 12px;
      padding: 24px;
      text-align: center;
      max-width: 400px;
      width: 100%;
    }
    h2 { color: #00F5D4; margin-bottom: 12px; }
    button {
      background: #00F5D4;
      color: #000;
      border: none;
      padding: 10px 18px;
      border-radius: 8px;
      font-weight: 700;
      cursor: pointer;
      margin-top: 16px;
      transition: transform 0.1s;
    }
    button:active { transform: scale(0.96); }
  </style>
</head>
<body>
  <div class="card">
    <h2>🧩 ${pluginName}</h2>
    <p>이곳에 자유롭게 HTML, CSS, JavaScript를 작성하세요.</p>
    <button id="btnAction">호스트로 토스트 날리기</button>
  </div>

  <script>
    document.getElementById('btnAction').addEventListener('click', () => {
      if (window.Boardest && window.Boardest.ui) {
        window.Boardest.ui.showToast('${pluginName} 플러그인 동작 확인!');
      } else {
        alert('로컬 프리뷰 모드: ${pluginName} 동작 중');
      }
    });
  </script>
</body>
</html>`;
    fs.writeFileSync(path.join(targetDir, 'index.html'), html, 'utf8');

    console.log(`✅ 플러그인 프로젝트가 성공적으로 생성되었습니다: ${pluginName}`);
    console.log(`\n다음 명령으로 로컬 개발을 시작하세요:\n  cd ${pluginName}\n  node ${__filename} dev\n`);
    break;
  }

  case 'dev': {
    const cwd = process.cwd();
    const htmlPath = path.join(cwd, 'index.html');
    if (!fs.existsSync(htmlPath)) {
      console.error('❌ 현재 폴더에 index.html 파일이 없습니다.');
      process.exit(1);
    }
    const port = 4123;
    const server = http.createServer((req, res) => {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      // Inject Mock Boardest Bridge for testing
      const rawHtml = fs.readFileSync(htmlPath, 'utf8');
      const bridgeMock = `<script>
        window.Boardest = {
          ui: {
            showToast: function(msg) { console.log('[Host Bridge Toast]:', msg); alert('[Boardest Bridge Toast]: ' + msg); }
          },
          storage: {
            get: function(key) { return localStorage.getItem('bst_plugin_' + key); },
            set: function(key, val) { localStorage.setItem('bst_plugin_' + key, val); }
          }
        };
      </script>`;
      res.end(rawHtml.replace('</head>', `${bridgeMock}</head>`));
    });
    server.listen(port, () => {
      console.log(`🚀 [로컬 프리뷰 서버] http://localhost:${port} 에서 실행 중! (Ctrl+C 로 종료)`);
    });
    break;
  }

  case 'bundle':
  case 'publish': {
    const cwd = process.cwd();
    const manifestPath = path.join(cwd, 'plugin.json');
    const htmlPath = path.join(cwd, 'index.html');
    if (!fs.existsSync(manifestPath) || !fs.existsSync(htmlPath)) {
      console.error('❌ plugin.json 또는 index.html 파일이 없습니다.');
      process.exit(1);
    }
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    const htmlContent = fs.readFileSync(htmlPath, 'utf8');
    manifest.entryHtml = htmlContent;
    manifest.updatedAt = new Date().toISOString();

    const distDir = path.join(cwd, 'dist');
    if (!fs.existsSync(distDir)) fs.mkdirSync(distDir);
    const outFile = path.join(distDir, `${manifest.id}.json`);
    fs.writeFileSync(outFile, JSON.stringify(manifest, null, 2), 'utf8');
    console.log(`📦 플러그인이 번들링되었습니다: ${outFile}`);
    console.log(`📡 선 배포 경로: Firebase RTDB /plugins/${manifest.id}.json 등록 준비 완료!`);
    break;
  }

  default: {
    console.log(`
사용법:
  node cli.js init <플러그인명>    새 HTML 플러그인 템플릿 생성
  node cli.js dev                로컬 브라우저에서 JS Bridge 프리뷰 실행
  node cli.js bundle             배포용 단일 JSON 번들 생성 (dist/ 폴더)
  node cli.js publish            Firebase 스토어에 플러그인 배포
`);
    break;
  }
}
