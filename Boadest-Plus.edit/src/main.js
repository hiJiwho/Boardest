import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-app.js";
import { getAuth, GoogleAuthProvider, signInWithPopup, signOut, onAuthStateChanged } from "https://www.gstatic.com/firebasejs/10.12.0/firebase-auth.js";

// Real Firebase Configuration for jiwhosboardest
const firebaseConfig = {
  apiKey: "AIzaSyBMoJZHMBN4eYJtiZR2iGePcmIB7bg8wGo",
  authDomain: "jiwhosboardest.firebaseapp.com",
  projectId: "jiwhosboardest",
  storageBucket: "jiwhosboardest.firebasestorage.app",
  messagingSenderId: "287519871774",
  appId: "1:287519871774:web:ee2177b6a5497ab96cef0f"
};

let firebaseAuth = null;
let googleAccessToken = localStorage.getItem('google_access_token') || '';

try {
  const app = initializeApp(firebaseConfig);
  firebaseAuth = getAuth(app);

  onAuthStateChanged(firebaseAuth, (user) => {
    if (user) {
      userInfo.textContent = `${user.email || '인증됨'}`;
      googleLoginBtn.textContent = '로그아웃';
    } else {
      userInfo.textContent = '';
      googleLoginBtn.textContent = 'Google 로그인 (Firebase)';
    }
  });
} catch (e) {
  console.log('Firebase Auth init error', e);
}

let editor = null;
let activeFileHandle = null;
let directoryHandle = null;
let isGitHubMode = false;
let currentGitHubRepo = '';

// DOM Elements
const openDirBtn = document.getElementById('openDirBtn');
const githubBtn = document.getElementById('githubBtn');
const toggleInfoBtn = document.getElementById('toggleInfoBtn');
const googleLoginBtn = document.getElementById('googleLoginBtn');
const userInfo = document.getElementById('userInfo');
const newFileBtn = document.getElementById('newFileBtn');
const fileTree = document.getElementById('fileTree');
const sidebarTitle = document.getElementById('sidebarTitle');
const promptInput = document.getElementById('promptInput');
const sendBtn = document.getElementById('sendBtn');
const chatLogs = document.getElementById('chatLogs');

// Form Input Elements for info.json
const infoFormPane = document.getElementById('infoFormPane');
const closeInfoBtn = document.getElementById('closeInfoBtn');
const infoId = document.getElementById('infoId');
const infoName = document.getElementById('infoName');
const infoVersion = document.getElementById('infoVersion');
const infoDesc = document.getElementById('infoDesc');
const infoIcon = document.getElementById('infoIcon');
const infoDisplay = document.getElementById('infoDisplay');
const infoCanvas = document.getElementById('infoCanvas');
const infoRole = document.getElementById('infoRole');
const infoUrl = document.getElementById('infoUrl');

// Initialize Monaco Editor
require.config({ paths: { vs: 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.39.0/min/vs' } });
require(['vs/editor/editor.main'], function () {
  editor = monaco.editor.create(document.getElementById('monaco-container'), {
    value: `// [폴더 열기] 또는 [GitHub 연동]을 누른 뒤 파일 선택\n`,
    language: 'javascript',
    theme: 'vs-dark',
    automaticLayout: true,
    fontSize: 14,
    minimap: { enabled: false }
  });

  editor.onDidChangeModelContent(() => {
    saveActiveFile();
    syncEditorToForm();
  });
});

// Google OAuth Authorization Trigger via Firebase
googleLoginBtn.addEventListener('click', async () => {
  if (firebaseAuth && firebaseAuth.currentUser) {
    await signOut(firebaseAuth);
    googleAccessToken = '';
    localStorage.removeItem('google_access_token');
    return;
  }

  if (firebaseAuth) {
    try {
      const provider = new GoogleAuthProvider();
      provider.addScope('https://www.googleapis.com/auth/generative-language');
      const result = await signInWithPopup(firebaseAuth, provider);
      const credential = GoogleAuthProvider.credentialFromResult(result);
      if (credential && credential.accessToken) {
        googleAccessToken = credential.accessToken;
        localStorage.setItem('google_access_token', googleAccessToken);
      }
    } catch (e) {
      alert('구글 로그인 실패: ' + e.message);
    }
  }
});

// Directory Picker
openDirBtn.addEventListener('click', async () => {
  if (!window.showDirectoryPicker) {
    alert('이 브라우저는 로컬 폴더 열기를 지원하지 않습니다. [GitHub 연동] 버튼을 사용해 보세요!');
    return;
  }
  try {
    directoryHandle = await window.showDirectoryPicker();
    isGitHubMode = false;
    sidebarTitle.textContent = `탐색기 (${directoryHandle.name})`;
    
    // Ensure default template files exist (index.html & info.json)
    await ensureDefaultTemplateFiles();
    renderFileTree();
  } catch (e) {
    if (e.name !== 'AbortError') alert('폴더를 열 수 없습니다: ' + e.message);
  }
});

async function ensureDefaultTemplateFiles() {
  if (!directoryHandle) return;

  // 1. Ensure info.json
  try {
    await directoryHandle.getFileHandle('info.json');
  } catch (_) {
    try {
      const handle = await directoryHandle.getFileHandle('info.json', { create: true });
      const defaultInfo = {
        id: "com.boardest.myplugin",
        name: "내 스마트 미니앱",
        version: "1.0.0",
        description: "전자칠판에 연동되는 커스텀 미니앱",
        iconEmoji: "⏱️",
        displayMode: "popup",
        requiresCanvas: true,
        role: "both"
      };
      const writable = await handle.createWritable();
      await writable.write(JSON.stringify(defaultInfo, null, 2));
      await writable.close();
    } catch (_) {}
  }

  // 2. Ensure index.html
  try {
    await directoryHandle.getFileHandle('index.html');
  } catch (_) {
    try {
      const handle = await directoryHandle.getFileHandle('index.html', { create: true });
      const defaultHtml = `<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8">
  <title>내 스마트 미니앱</title>
  <style>
    body { background: #121214; color: #E2E2E6; font-family: sans-serif; margin: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; }
    .card { background: #1E1E24; border: 1px solid #3C3C3C; border-radius: 12px; padding: 24px; text-align: center; }
    button { background: #00F5D4; color: #121214; border: none; padding: 10px 20px; border-radius: 6px; font-weight: bold; cursor: pointer; }
  </style>
</head>
<body>
  <div class="card">
    <h1>⏱️ 내 스마트 미니앱</h1>
    <p>칠판연동 SDK 준비 완료</p>
    <button onclick="testSdk()">알림 띄우기</button>
  </div>

  <script>
    async function testSdk() {
      if (window.boardest) {
        window.boardest.showNotification("안녕하세요! 미니앱 연동 성공입니다.");
      } else {
        alert("Boardest SDK 준비 완료!");
      }
    }
  </script>
</body>
</html>`;
      const writable = await handle.createWritable();
      await writable.write(defaultHtml);
      await writable.close();
    } catch (_) {}
  }
}

// GitHub Integration
githubBtn.addEventListener('click', async () => {
  const repo = prompt('연동할 GitHub 저장소를 입력하세요 (형식: owner/repo):', currentGitHubRepo || 'hiJiwho/bst-store');
  if (!repo) return;

  currentGitHubRepo = repo;
  isGitHubMode = true;
  sidebarTitle.textContent = `GitHub (${repo})`;
  renderGitHubFileTree('');
});

async function renderGitHubFileTree(path = '') {
  fileTree.innerHTML = '<div style="padding: 12px; color: var(--text-muted); font-size: 11px;">GitHub 파일 불러오는 중...</div>';
  try {
    const res = await fetch(`https://api.github.com/repos/${currentGitHubRepo}/contents/${path}`);
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();

    fileTree.innerHTML = '';
    const items = Array.isArray(data) ? data : [data];

    for (const item of items) {
      const el = document.createElement('div');
      el.className = 'tree-item';
      el.dataset.path = item.path;

      if (item.type === 'dir') {
        el.innerHTML = `📁 <b>${item.name}</b>`;
        el.addEventListener('click', () => renderGitHubFileTree(item.path));
      } else {
        el.innerHTML = `📄 ${item.name}`;
        el.addEventListener('click', () => openGitHubFile(item));
      }
      fileTree.appendChild(el);
    }
  } catch (e) {
    fileTree.innerHTML = `<div style="padding: 12px; color: #ef4565; font-size: 11px;">GitHub 로딩 실패: ${e.message}</div>`;
  }
}

async function openGitHubFile(item) {
  try {
    activeFileHandle = { isGitHub: true, ...item };
    const res = await fetch(item.download_url);
    const content = await res.text();

    document.querySelectorAll('.tree-item').forEach(x => x.classList.remove('active'));
    const found = Array.from(document.querySelectorAll('.tree-item')).find(x => x.dataset.path === item.path);
    if (found) found.classList.add('active');

    const ext = item.name.split('.').pop().toLowerCase();
    let lang = 'html';
    if (ext === 'js') lang = 'javascript';
    else if (ext === 'css') lang = 'css';
    else if (ext === 'json') lang = 'json';

    const model = monaco.editor.createModel(content, lang);
    editor.setModel(model);
    syncEditorToForm();
  } catch (e) {
    alert('파일 읽기 실패: ' + e.message);
  }
}

async function renderFileTree() {
  fileTree.innerHTML = '';
  if (!directoryHandle) return;

  for await (const entry of directoryHandle.values()) {
    const el = document.createElement('div');
    el.className = 'tree-item';
    el.dataset.name = entry.name;
    
    if (entry.kind === 'directory') {
      el.innerHTML = `📁 <b>${entry.name}</b>`;
      fileTree.appendChild(el);
      for await (const subEntry of entry.values()) {
        const subEl = document.createElement('div');
        subEl.className = 'tree-item';
        subEl.style.paddingLeft = '24px';
        subEl.innerHTML = `📄 ${subEntry.name}`;
        subEl.addEventListener('click', () => openLocalFile(subEntry));
        fileTree.appendChild(subEl);
      }
    } else {
      el.innerHTML = `📄 ${entry.name}`;
      el.addEventListener('click', () => openLocalFile(entry));
      fileTree.appendChild(el);
    }
  }
}

async function openLocalFile(fileHandle) {
  activeFileHandle = fileHandle;
  const file = await fileHandle.getFile();
  const content = await file.text();
  
  document.querySelectorAll('.tree-item').forEach(x => x.classList.remove('active'));
  const found = Array.from(document.querySelectorAll('.tree-item')).find(x => x.textContent.includes(fileHandle.name));
  if (found) found.classList.add('active');

  const ext = fileHandle.name.split('.').pop().toLowerCase();
  let lang = 'html';
  if (ext === 'js') lang = 'javascript';
  else if (ext === 'css') lang = 'css';
  else if (ext === 'json') lang = 'json';

  const model = monaco.editor.createModel(content, lang);
  editor.setModel(model);
  syncEditorToForm();
}

async function saveActiveFile() {
  if (!activeFileHandle || !editor) return;
  
  if (activeFileHandle.isGitHub) {
    return;
  }

  try {
    const content = editor.getValue();
    const writable = await activeFileHandle.createWritable();
    await writable.write(content);
    await writable.close();
  } catch (_) {}
}

// Bi-directional Form UI Syncing for info.json / manifest.json
function syncEditorToForm() {
  if (!activeFileHandle || !editor) return;
  const fileName = (activeFileHandle.name || activeFileHandle.path || '').toLowerCase();
  if (fileName === 'info.json' || fileName === 'manifest.json') {
    try {
      const data = JSON.parse(editor.getValue());
      infoId.value = data.id || '';
      infoName.value = data.name || '';
      infoVersion.value = data.version || '1.0.0';
      infoDesc.value = data.description || '';
      infoIcon.value = data.iconEmoji || '⏱️';
      infoDisplay.value = data.displayMode || 'popup';
      infoCanvas.value = (data.requiresCanvas === true || data.requiresCanvas === 'true') ? 'true' : 'false';
      infoRole.value = data.role || 'both';
      infoUrl.value = data.url || '';
    } catch (_) {}
  }
}

function syncFormToEditor() {
  if (!activeFileHandle || !editor) return;
  const fileName = (activeFileHandle.name || activeFileHandle.path || '').toLowerCase();
  if (fileName === 'info.json' || fileName === 'manifest.json') {
    const updated = {
      id: infoId.value,
      name: infoName.value,
      version: infoVersion.value,
      description: infoDesc.value,
      iconEmoji: infoIcon.value,
      displayMode: infoDisplay.value,
      requiresCanvas: infoCanvas.value === 'true',
      role: infoRole.value,
      url: infoUrl.value || undefined
    };
    editor.setValue(JSON.stringify(updated, null, 2));
  }
}

// Bind all form inputs
[infoId, infoName, infoVersion, infoDesc, infoIcon, infoDisplay, infoCanvas, infoRole, infoUrl].forEach(input => {
  input.addEventListener('input', syncFormToEditor);
  input.addEventListener('change', syncFormToEditor);
});

// Toggle Info Form Pane
toggleInfoBtn.addEventListener('click', async () => {
  const isVisible = infoFormPane.style.display === 'flex';
  infoFormPane.style.display = isVisible ? 'none' : 'flex';
  if (!isVisible && directoryHandle) {
    try {
      const handle = await directoryHandle.getFileHandle('info.json');
      openLocalFile(handle);
    } catch (_) {
      try {
        const handle = await directoryHandle.getFileHandle('manifest.json');
        openLocalFile(handle);
      } catch (_) {}
    }
  }
});
closeInfoBtn.addEventListener('click', () => {
  infoFormPane.style.display = 'none';
});

// New File Button
newFileBtn.addEventListener('click', async () => {
  if (!directoryHandle && !isGitHubMode) {
    alert('폴더를 먼저 열어주세요.');
    return;
  }
  const name = prompt('생성할 파일명을 입력하세요 (예: info.json, index.html):');
  if (!name) return;

  if (!isGitHubMode && directoryHandle) {
    try {
      const handle = await directoryHandle.getFileHandle(name, { create: true });
      renderFileTree();
      openLocalFile(handle);
    } catch (e) {
      alert('파일 생성 실패: ' + e.message);
    }
  }
});

// Antigravity AI Vibe Coding Prompt Trigger
async function triggerVibeCoding() {
  const prompt = promptInput.value.trim();
  if (!prompt) return;

  if (!activeFileHandle) {
    alert('수정할 파일을 탐색기에서 먼저 열어주세요.');
    return;
  }

  appendMessage('user', prompt);
  promptInput.value = '';

  const activeContent = editor.getValue();
  appendMessage('ai', 'Antigravity CLI가 소스코드를 인덱싱하여 수정하는 중입니다...');

  try {
    const systemPrompt = `You are Antigravity CLI, an expert developer engine. 
Based on the user's prompt, rewrite the active source code. Return ONLY the complete modified source code. Do NOT output markdown block quotes or explanations.

File Name: ${activeFileHandle.name || activeFileHandle.path}
Code:
${activeContent}`;

    let headers = { 'Content-Type': 'application/json' };
    if (googleAccessToken) {
      headers['Authorization'] = `Bearer ${googleAccessToken}`;
    }

    const response = await fetch(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent',
      {
        method: 'POST',
        headers: headers,
        body: JSON.stringify({
          contents: [{
            parts: [{ text: `${systemPrompt}\n\nRequest: ${prompt}` }]
          }]
        })
      }
    );

    if (response.ok) {
      const data = await response.json();
      let code = data.candidates?.[0]?.content?.parts?.[0]?.text || '';
      
      if (code.startsWith('```')) {
        const lines = code.split('\n');
        if (lines[0].startsWith('```')) lines.shift();
        if (lines[lines.length - 1].startsWith('```')) lines.pop();
        code = lines.join('\n');
      }
      
      code = code.trim();
      
      if (code) {
        editor.setValue(code);
        await saveActiveFile();
        appendMessage('ai', 'Antigravity CLI: 변경사항을 파일에 반영했습니다. 👍');
      } else {
        appendMessage('ai', '오류: AI가 코드를 생성하지 못했습니다.');
      }
    } else {
      const errText = await response.text();
      appendMessage('ai', `오류가 발생했습니다: ${response.status} ${errText}`);
    }
  } catch (e) {
    appendMessage('ai', `API 호출 오류: ${e.message}`);
  }
}

function appendMessage(role, text) {
  const el = document.createElement('div');
  el.className = role === 'user' ? 'msg-user' : 'msg-ai';
  el.innerHTML = `<b>${role === 'user' ? '나' : 'Antigravity'}</b><br>${text}`;
  chatLogs.appendChild(el);
  chatLogs.scrollTop = chatLogs.scrollHeight;
}

sendBtn.addEventListener('click', triggerVibeCoding);
promptInput.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') triggerVibeCoding();
});

// Help Pane toggle
const toggleHelpBtn = document.getElementById('toggleHelpBtn');
const closeHelpBtn = document.getElementById('closeHelpBtn');
const helpPane = document.getElementById('helpPane');

toggleHelpBtn.addEventListener('click', () => {
  const isVisible = helpPane.style.display === 'flex';
  helpPane.style.display = isVisible ? 'none' : 'flex';
});

closeHelpBtn.addEventListener('click', () => {
  helpPane.style.display = 'none';
});
