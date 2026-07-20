# 🔌 Boardest Plus Javascript SDK & Manifest Guide

Boardest Plus 플랫폼은 웹 기술(HTML/CSS/JS)을 활용하여 전자칠판용 스마트 학습 교구(플러그인)를 자유롭게 제작할 수 있는 환경을 제공합니다.

---

## 1. `manifest.json` 설정 (플러그인 메타데이터)

플러그인 폴더 루트에 `manifest.json`을 위치시켜 칠판에서의 실행 형태를 구성할 수 있습니다.

```json
{
  "id": "com.boardest.stopwatch",
  "name": "M3 스톱워치",
  "version": "1.0.1",
  "description": "랩타임 모션을 지원하는 스톱워치",
  "author": "Boardest Team",
  "iconEmoji": "⏱️",
  "displayMode": "popup",
  "requiresCanvas": true,
  "role": "teacher"
}
```

### 설정 필드 목록
* **`displayMode`**: 칠판에서 앱이 기동되는 형태를 정의합니다.
  - `"popup"` (기본값): 화면 위에 드래그 가능한 크기 조절형 플로팅 창으로 실행.
  - `"fullscreen"`: 화면 전체를 덮는 꽉 찬 모드로 실행.
* **`requiresCanvas`**: `true`로 설정하면 웹뷰 상단에 **투명 판서 캔버스**가 자동으로 오버레이됩니다.
* **`role`**: 플러그인을 사용할 권한 범위를 나눕니다.
  - `"teacher"`: 교사용 도구 탭에만 표시.
  - `"student"`: 학생용 도구 탭에만 표시.
  - `"both"` (기본값): 둘 다 사용 가능.
* **`url`**: (선택사항) 로컬 index.html 대신 지정된 외부 학습용 사이트 주소를 직접 전체화면으로 실행합니다.

---

## 2. `window.boardest` SDK Javascript API

웹 플러그인 내부 스크립트에서 네이티브 전자칠판의 하드웨어 및 데이터를 제어할 수 있습니다.

### 2.1 USB 연결 상태 확인
```javascript
const connected = await window.boardest.usbDetected();
if (connected) {
  console.log("교사용 수업 USB 마운트 감지됨");
}
```

### 2.2 칠판 설정 및 학교 정보 조회
```javascript
const settings = await window.boardest.getSettings();
console.log("학교명:", settings.selectedSchool?.name);
console.log("학년/반:", settings.selectedGrade, "학년", settings.selectedClass, "반");
```

### 2.3 데이터 영구 보존 (Persistence)
미니앱의 상태나 기록값들을 칠판의 로컬 데이터베이스에 저장하고 영구 보존합니다.
```javascript
// 데이터 저장
window.boardest.saveData("stopwatch_record", "01:23.45");

// 데이터 로드 (settings 객체 내부에 저장됨)
const settings = await window.boardest.getSettings();
console.log("저장된 기록:", settings.pluginData?.stopwatch_record);
```

### 2.4 네이티브 알림 띄우기
```javascript
window.boardest.showNotification("스톱워치 기록이 완료되었습니다!");
```

### 2.5 앱 닫기
```javascript
window.boardest.close();
```

---

## 3. 웹 뷰 페이지 제어 통합 (이전/다음 동작)

`requiresCanvas: true` 설정 시 화면 하단에 이전/다음 네이티브 컨트롤 버튼이 활성화됩니다. 이 버튼을 누르면 웹뷰에 다음과 같이 이벤트 및 키 입력이 트리거됩니다.

* **일반 HTML 번들**: 윈도우 객체로 `pagechange` 커스텀 이벤트가 수신됩니다.
  ```javascript
  window.addEventListener('pagechange', (e) => {
    const action = e.detail.action; // 'prev' 또는 'next'
    if (action === 'next') {
      goToNextPage();
    }
  });
  ```
* **외부 웹사이트 (`url` 사용 시)**: 웹뷰 내부 DOM에 **Page Up (keyCode 33)** 및 **Page Down (keyCode 34)** 가상 키 입력이 직접 전달되어 사이트의 스크롤이나 슬라이드가 즉시 이동합니다.
