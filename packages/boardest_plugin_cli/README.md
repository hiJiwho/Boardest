# 🧩 Boardest Plugin CLI

Boardest 교실 전자칠판, 학생용 포털, 교사용 앱에서 구동되는 **인앱 HTML 플러그인(미니앱)**을 1분 만에 만들고 로컬에서 테스트/배포할 수 있는 도구입니다.

---

## 🚀 사용법

### 1. 새 플러그인 프로젝트 생성
```bash
node tools/boardest_plugin_cli/bin/cli.js init my-stopwatch
cd my-stopwatch
```

### 2. 로컬 브라우저에서 개발 및 프리뷰
```bash
node ../tools/boardest_plugin_cli/bin/cli.js dev
# 브라우저에서 http://localhost:4123 접속 (Boardest JS Bridge 자동 주입)
```

### 3. 배포용 JSON 생성 및 배포
```bash
node ../tools/boardest_plugin_cli/bin/cli.js bundle
# dist/{pluginId}.json 생성 -> Firebase RTDB /plugins/{pluginId}.json 배포
```
