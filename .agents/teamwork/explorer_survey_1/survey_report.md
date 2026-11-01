# Issue Group 1 정밀 조사 및 기술 분석 보고서
**TBP 스마트교과서 및 캔바(Canva) 뷰어 완성도**

- **작성자**: teamwork_explorer_survey_1
- **작성일**: 2026-11-01
- **대상 모듈**:
  - `apps/boardest/`
  - `apps/boardest_teacher/`
  - `packages/plugins/bst_tbp/`
  - `packages/plugins/bst_canva/`

---

## 1. 개요 및 요약 (Executive Summary)

본 보고서는 Boardest 생태계의 핵심 뷰어인 **TBP(전자저작물/스마트교과서) 및 Canva(HTML 프레젠테이션) 뷰어**에서 발생하는 4대 문제점에 대한 심층 분석 결과와 구체적인 코드 레벨 해결책을 제시합니다.

| 번호 | 이슈 항목 | 핵심 원인 | 해결 방안 요약 |
|---|---|---|---|
| **1** | **1536px 배율 & 선명도** | `_hashJsScript` 내 CSS `transform: scale()` 강제 적용으로 인한 래스터화 흐림 현상 및 Canva UI 왜곡 | WebView2 네이티브 `setZoomFactor(W / 1536.0)` 적용 및 16:9 컨테이너 동기화. Canva에는 CSS 강제 락 배제 |
| **2** | **판서 파일 포맷 및 보존** | 현재 `BBPen/[classId]/[hash].svg` 구조로 저장되어 `[교실ID]dhash.pen` 규약 불일치 및 페이지 전환 시 저장/로드 경쟁 상태 발생 | `[교실ID]dhash.pen` (예: `기본_dhash.pen`, `[1반]dhash.pen`) 파일명 표준화 + 인메모리 0ms 즉각 복원 캐시 도입 |
| **3** | **2페이지 건너뜀 (이중 트리거)** | Windows WebView2 내부 네이티브 키 이벤트와 Flutter `Focus` (`onKeyEvent`)의 동시 처리로 2회 네비게이션 발생 | WebView 내부 Capture-Phase 키 인터셉터 (`preventDefault`, `stopImmediatePropagation`) + Flutter 단일 경로 제어 + 50ms 초고속 감지 |
| **4** | **Canva/TBP dHash 고착 (`hash__1` / `default`)** | Canva에서 `location.hash` 부재로 무조건 `'hash__1'` 반환 하드코딩 + TBP iframe/셀렉터 미매칭 시 정적 URL 해시 고착 | Canva DOM 슬라이드 카운터 정규식 매칭 + 가상 슬라이드 인덱스 Fallback + 다중 출판사 DOM/iframe URL 감지 엔진 확장 |

---

## 2. Issue 1: 1536px 배율 및 고해상도 선명 렌더링

### 2.1 현행 코드 및 문제점 분석

#### 관련 파일 및 라인
- `apps/boardest/lib/services/tbp/tbp_dhash_engine.dart`: 41~127
- `apps/boardest_teacher/lib/services/tbp/tbp_dhash_engine.dart`: 41~127
- `packages/plugins/bst_tbp/lib/src/services/tbp_dhash_engine.dart`: 50~136

#### 코드 분석
```javascript
// tbp_dhash_engine.dart (라인 71~110)
function sync1536Scale() {
  var targetW = 1536;
  var targetH = 864;
  var winW = (window.__bstGetRealW ? window.__bstGetRealW() : window.innerWidth) || screen.width || 1536;
  var winH = (window.__bstGetRealH ? window.__bstGetRealH() : window.innerHeight) || screen.height || 864;
  var scale = Math.min(winW / targetW, winH / targetH);
  ...
  styleEl.textContent = 'html { width: 100% !important; height: 100% !important; ... } ' +
    'body { width: 1536px !important; min-width: 1536px !important; max-width: 1536px !important; ' +
    'height: 864px !important; min-height: 864px !important; max-height: 864px !important; ' +
    'transform-origin: 0 0 !important; ' +
    'transform: translate(' + offsetX.toFixed(2) + 'px, ' + offsetY.toFixed(2) + 'px) scale(' + scale.toFixed(4) + ') !important; ... }';
}
```

#### 문제 발생 메커니즘
1. **CSS Transform의 래스터화 한계**:
   - `transform: scale(scale)`을 `body`에 걸면 브라우저 컴포지터가 1536x864 해상도로 DOM을 래스터화한 뒤 텍스처를 확대합니다.
   - FHD(1920x1080), QHD(2560x1440), 4K(3840x2160) 모니터나 전자칠판에서 확대 시 폰트의 서브픽셀 힌팅이 파괴되고 벡터 그래픽 및 캔버스 요소가 뿌옇게 흐려지는(Blurry/Fuzzy) 현상이 발생합니다.
2. **Canva 레이아웃 파괴**:
   - Canva(`canva.com`)는 자체 반응형 레이아웃 엔진을 탑재하고 있습니다. `body`를 1536x864로 고정하고 `transform: scale`을 강제하면 Canva 내부 에디터/뷰어의 툴바가 짤리고 터치/마우스 좌표가 어긋납니다.
3. **`Object.defineProperty` 오버라이드 충돌**:
   - `window.innerWidth = 1536`을 강제로 덮어씌워 브라우저 내부 스크립트가 실제 렌더링 뷰포트 크기를 계산하지 못합니다.

### 2.2 해결 방안: 네이티브 ZoomFactor 기반 1536 선명 렌더링

1. **WebView2 네이티브 Zoom Factor 연동**:
   - `webview_windows`의 `WebviewController`에는 `Future<void> setZoomFactor(double zoomFactor)`가 이미 구현되어 있습니다 (`webview.dart:442`).
   - Flutter 측에서 16:9 컨테이너의 실제 렌더링 폭 `W`를 측정하여 `zoomFactor = W / 1536.0`을 네이티브 WebView2에 설정합니다.
   - 이렇게 하면 Chromium 엔진이 내부적으로 뷰포트를 `1536 x 864` 논리 픽셀로 인식하면서도, 렌더링은 모니터의 실제 물리 픽셀(DPI)에 맞춰 고해상도 네이티브 벡터로 직접 그립니다. 폰트와 이미지가 100% 선명하게 유지됩니다.
2. **Canva 분기 처리**:
   - Canva 뷰어(`canva_board_view.dart`)에서는 `bst-1536-lock-style` 주입을 건너뛰고, 16:9 컨테이너 비율 맞춤만 유지합니다.

---

## 3. Issue 2: 판서 파일 포맷 및 보존 규약 (`[교실ID]dhash.pen`)

### 3.1 현행 판서 저장/로드 로직 및 파일 네이밍 규약 점검

#### 관련 파일 및 라인
- `apps/boardest_teacher/lib/services/tbp/tbp_storage_service.dart`: 853~1045
- `apps/boardest/lib/services/tbp/tbp_storage_service.dart`: 820~1010
- `apps/boardest_teacher/lib/views/tbp/tbp_viewer_route.dart`: 555~603
- `apps/boardest/lib/views/tbp/tbp_viewer_route.dart`: 525~573
- `apps/boardest_teacher/lib/views/canva_board_view.dart`: 425~479

#### 현행 파일 네이밍 상태
현재 `saveStrokeData` 및 `loadStrokeData`는 다음과 같이 동작합니다:
- `classId`가 있을 때: `${tbpFolderPath}/BBPen/${classId}/${base}.svg` 및 `${base}.bstpen` 저장
- `classId`가 없을 때: `${tbpFolderPath}/BBPen/${base}.svg` 및 `${tbpFolderPath}/PEN/${base}.bstpen` 저장
- 요구 규약인 `[교실ID]dhash.pen` (예: `기본_dhash.pen`, `[1반]dhash.pen`)과 불일치합니다.
- `canva_board_view.dart`는 `savePenStrokes` 및 `loadPenStrokes` 호출 시 `classId`를 전혀 전달하지 않아 반별 분리가 누락되어 있었습니다.

#### 판서 복원 실패 원인
1. **페이지 전환 중 경쟁 상태(Race Condition)**:
   - 페이지가 전환될 때 새 페이지의 판서를 로드하기 전에 이전 페이지의 스트로크 변경 리스너(`_onStrokesChanged`)가 비동기로 빈 배열을 저장해버려 기존 파일이 덮어씌워지는 버그 존재.
2. **초기 `default` 해시 저장 누락**:
   - 첫 진입 시 dHash가 `'default'`인 상태에서 필기한 경우, `if (prevHash != 'default')` 조건으로 인해 첫 페이지 판서 저장이 스킵됨.
3. **디스크 I/O 비동기 지연**:
   - 페이지를 빠르게 넘겼다가 다시 돌아왔을 때, 이전 저장 작업이 디스크에 완료되기 전에 `loadPenStrokes`가 파일 존재 여부를 체크하여 빈 데이터(`[]`)를 반환함.

### 3.2 해결 방안: `[교실ID]dhash.pen` 규약 및 100% 즉시 복원 메커니즘

1. **표준 파일명 생성 규칙**:
   ```dart
   String getPenFileName(String classId, String dHash) {
     final safeClass = classId.trim().isEmpty ? '기본' : classId.trim();
     final safeHash = sanitizeKey(dHash);
     if (safeClass == '기본') {
       return '기본_$safeHash.pen';
     } else if (safeClass.startsWith('[') && safeClass.endsWith(']')) {
       return '$safeClass$safeHash.pen';
     } else {
       return '[$safeClass]$safeHash.pen';
     }
   }
   ```
2. **다중 경로 로드 호환성 (하위 호환 100%)**:
   - `loadStrokeData`에서 아래 순서로 파일을 탐색:
     1) `${tbpFolderPath}/PEN/${fileName}`
     2) `${tbpFolderPath}/${fileName}`
     3) `${tbpFolderPath}/PEN/${safeClass}_${safeHash}.pen`
     4) `${tbpFolderPath}/BBPen/${safeClass}/${safeHash}.svg` (레거시)
     5) `${tbpFolderPath}/PEN/${safeHash}.bstpen` (레거시)
3. **인메모리 0ms 즉시 복원 캐시 (`_pageStrokesMemory`)**:
   - 뷰어 State 내에 `final Map<String, List<AnnotationStroke>> _pageStrokesMemory = {};` 유지 (`key: '$classId::$dHash'`).
   - 페이지 전환 시 현재 판서를 즉시 메모리 맵에 저장 (0ms 동기).
   - 이전 페이지로 복귀 시 메모리 맵을 최우선 조회하여 파일 I/O 대기 없이 **100% 즉시 복원**.
   - 백그라운드에서 파일 플러시(`savePenStrokes`) 수행.

---

## 4. Issue 3: 2페이지 건너뜀 (이중 트리거) 원천 차단 & 50ms 감지

### 4.1 이중 트리거(Double-Trigger) 발생 메커니즘

#### 관련 파일 및 라인
- `apps/boardest_teacher/lib/views/tbp/tbp_viewer_route.dart`: 664~688 (`_onKeyEvent`), 615~623 (`_navigatePage`)
- `apps/boardest/lib/views/tbp/tbp_viewer_route.dart`: 664~688 (`_onKeyEvent`), 614~622 (`_navigatePage`)
- `apps/boardest_teacher/lib/services/tbp/tbp_dhash_engine.dart`: 336~409 (`navigatePage`)
- `apps/boardest/lib/services/tbp/tbp_dhash_engine.dart`: 336~409 (`navigatePage`)

#### 문제의 근본 원인
1. **Windows 플랫폼 메시지 중복 전달**:
   - 사용자가 `ArrowRight`, `PageDown`, `Space` 등의 키를 누르면 Windows OS는 포커스를 가진 WebView2 컨트롤에 `WM_KEYDOWN`을 직접 전달합니다.
   - WebView2 내부의 웹페이지(Canva 슬라이드 또는 디지털 교과서)가 자체 키보드 리스너로 반응하여 **1페이지 이동**합니다.
2. **Flutter Focus 시스템의 중복 감지**:
   - 동시에 Flutter 윈도우 프로시저도 동일한 키 이벤트를 수신하여 `_keyboardFocus`의 `_onKeyEvent`를 실행합니다.
   - `_onKeyEvent`는 `_navigatePage(true)`를 호출하고, 이는 `TbpDhashEngine.navigatePage`를 통해 웹뷰 내부에 버튼 클릭 또는 가상 `KeyboardEvent('keydown')`를 주입합니다.
   - 결과적으로 웹페이지는 **네이티브 키 1회 + Flutter 주입 스크립트 1회 = 총 2회** 이벤트를 받아 **2페이지를 건너뛰게 됩니다.**

### 4.2 해결 방안: 웹뷰 내부 캡처 가드 + 50ms 초고속 감지

1. **WebView 내부 캡처-단계(Capture-Phase) 이벤트 차단 스크립트**:
   - 웹뷰 초기화 시 최상위 `window`에 캡처 리스너를 등록하여 내비게이션 키의 네이티브 처리를 원천 차단하고 Flutter로만 이벤트를 일원화합니다:
   ```javascript
   window.addEventListener('keydown', function(e) {
     if (['ArrowRight', 'ArrowLeft', 'PageDown', 'PageUp', 'Space'].indexOf(e.key) !== -1) {
       if (!e.__bstSynthetic) {
         e.preventDefault();
         e.stopPropagation();
         e.stopImmediatePropagation();
         postToFlutter({
           type: 'requestNavigation',
           isNext: (e.key === 'ArrowRight' || e.key === 'PageDown' || e.key === 'Space')
         });
       }
     }
   }, true);
   ```
2. **Flutter 단일 경로 네비게이션 가드**:
   - Flutter 측 `_navigatePage`에 350ms 시간 가드를 두어 키보드/터치 버튼/메시지로부터 유입되는 중복 명령을 단 1회로 제한합니다.
   - 가상 키 주입 시에는 `__bstSynthetic = true` 플래그를 설정하여 가드 통과.
3. **50ms 초고속 페이지 감지 트리거**:
   - 페이지 네비게이션이 실행된 직후 `50ms`, `150ms`, `300ms` 시점에 지연 없는 고속 `checkPage` 트리거를 연속 발행하여 지연 없이 즉각 판서를 교체합니다.

---

## 5. Issue 4: Canva 및 TBP dHash 고착 버그 (`hash__1` / `default`)

### 5.1 Canva에서 `hash__1` 고착 근본 원인

#### 관련 파일 및 라인
- `apps/boardest_teacher/lib/services/tbp/tbp_dhash_engine.dart`: 183~188
- `apps/boardest/lib/services/tbp/tbp_dhash_engine.dart`: 183~188

#### 코드 라인
```javascript
var loc = (w && w.location) ? w.location : window.location;
if (loc && loc.hostname && loc.hostname.indexOf('canva.com') !== -1) {
  var chash = (loc.hash && loc.hash.length > 1)
      ? loc.hash.replace(/[^a-zA-Z0-9_-]/g, '_')
      : '_1';
  return 'hash_' + chash;
}
```

#### 원인 규명
- Canva 임베드 뷰어(`https://www.canva.com/design/.../view?embed`)는 슬라이드를 넘겨도 **`location.hash`가 항상 빈 문자열(`""`)**입니다.
- 위 코드의 조건문 `loc.hash && loc.hash.length > 1`은 항상 `false`가 되며, `chash`는 무조건 `'_1'`로 평가됩니다.
- 그 결과 함수는 슬라이드가 몇 페이지이든 무조건 `'hash__1'`을 즉시 리턴합니다.
- `window.__bstLastPageId`와 비교 시 값이 변하지 않으므로 Flutter로 `dhashResult`가 영원히 발송되지 않습니다.
- 따라서 모든 슬라이드에서 dHash가 `'hash__1'`로 고착되어 모든 슬라이드에 1페이지 판서가 겹쳐 표시됩니다.

### 5.2 TBP에서 `hash__1` 또는 `default` 고착 근본 원인

1. **iframe CORS 접근 제한에 따른 Fallback 오류**:
   - `tbp_dhash_engine.dart:218~227`에서 `frames[f].contentDocument`를 읽으려 할 때 교과서 iframe의 도메인이 다르거나 포트가 다르면 `SecurityError`가 발생하여 catch문으로 빠집니다.
   - 셀렉터 감지에 실패하면 229~250라인의 `getFastHash(raw)`가 실행되는데, 이때 `window.location.pathname`, `search`, 부모 문서의 `bodyText`는 슬라이드를 넘겨도 전혀 변하지 않습니다.
   - 따라서 매 페이지마다 완벽히 동일한 정적 해시 문자열이 생성되어 페이지 변경을 감지하지 못합니다.
2. **`tbp_storage_service.dart`의 `default` 강제 폴백**:
   - 730라인 및 871라인에서 `key == 'hash__1' || key == 'ui_home'`인 경우 `default.json`, `query__embed.json`으로 강제 리다이렉트하는 코드가 존재하여 다른 페이지의 데이터까지 `default` 데이터로 오염시키는 원인이 되었습니다.

### 5.3 해결 방안 코드 레벨 분석

1. **Canva 전용 DOM 슬라이드 카운터 정밀 매칭**:
   ```javascript
   if (loc && loc.hostname && loc.hostname.indexOf('canva.com') !== -1) {
     // 1. Canva 슬라이드 카운터 텍스트 매칭 (예: "3 / 15")
     var allEls = doc.querySelectorAll('button, div, span, p');
     for (var i = 0; i < allEls.length; i++) {
       var t = allEls[i].innerText || allEls[i].textContent || '';
       var m = t.match(/^\s*(\d+)\s*\/\s*(\d+)\s*$/);
       if (m && m[1]) return 'canva_p' + m[1];
     }
     // 2. Canva aria-valuenow / aria-roledescription 슬라이드 속성
     var activeSlide = doc.querySelector('[aria-current="step"], [data-testid="page-number"], [aria-roledescription*="slide"][aria-hidden="false"]');
     if (activeSlide) {
       var pno = (activeSlide.getAttribute('aria-valuenow') || activeSlide.innerText || '').replace(/[^0-9]/g, '');
       if (pno) return 'canva_p' + pno;
     }
     // 3. 네비게이션 가상 인덱스 연동
     if (window.__bstCanvaPage) return 'canva_p' + window.__bstCanvaPage;
     return 'canva_p1';
   }
   ```
2. **TBP 다중 출판사 셀렉터 및 iframe URL 감지 엔진 확장**:
   - 국내 주요 출판사(천재, 비상, 미래엔, 동아, 금성, YBM 등)에서 사용하는 클래스 및 속성을 대거 추가:
     `[data-page]`, `[data-page-no]`, `.cur_page`, `.current`, `.num`, `.page_info`, `span.page`, `input.page`
   - iframe의 `src` URL에서 `/(?:page|p|slide)[/_=-]?(\d+)/i` 패턴 감지
   - 전역 JS 객체 감지: `window.ebook.currentPage`, `window.curPage`, `window.pageNo`
3. **가상 페이지 카운터 자동 보정 (Ultimate Fallback)**:
   - DOM 분석으로도 페이지 번호를 알 수 없는 특수 저작물의 경우, 이전/다음 네비게이션 트리거 발생 시 `__bstVirtualPage`를 증감시켜 페이지마다 고유한 `page_1`, `page_2`, `page_3`을 반드시 보장.
4. **StorageService의 `hash__1` -> `default` 변환 코드 제거**:
   - `hash__1`이나 각 페이지 해시가 독립된 파일로 보존되도록 리다이렉트 제거.

---

## 6. 전체 영향 파일 및 구현 제안 요약

| 파일 경로 | 수정 대상 영역 | 수정 내용 |
|---|---|---|
| `apps/boardest/lib/services/tbp/tbp_dhash_engine.dart` | `_hashJsScript`, `navigatePage` | Canva `hash__1` 제거 및 DOM 카운터 도입, 1536 CSS Transform 제거, 50ms 감지 트리거 |
| `apps/boardest_teacher/lib/services/tbp/tbp_dhash_engine.dart` | `_hashJsScript`, `navigatePage` | 동일 적용 |
| `packages/plugins/bst_tbp/lib/src/services/tbp_dhash_engine.dart` | `_hashJsScript`, `navigatePage` | 동일 적용 |
| `apps/boardest/lib/services/tbp/tbp_storage_service.dart` | `loadStrokeData`, `saveStrokeData` | `[교실ID]dhash.pen` 네이밍 적용, `hash__1` 폴백 제거 |
| `apps/boardest_teacher/lib/services/tbp/tbp_storage_service.dart` | `loadStrokeData`, `saveStrokeData` | 동일 적용 |
| `packages/plugins/bst_tbp/lib/src/services/tbp_storage_service.dart` | `loadStrokeData`, `saveStrokeData` | 동일 적용 |
| `apps/boardest/lib/views/tbp/tbp_viewer_route.dart` | `_onKeyEvent`, `_setupWebview`, `_onDhashDetected` | 네이티브 `setZoomFactor` 적용, 인메모리 판서 캐시 도입, 키보드 이중 트리거 차단 |
| `apps/boardest_teacher/lib/views/tbp/tbp_viewer_route.dart` | `_onKeyEvent`, `_setupWebview`, `_onDhashDetected` | 동일 적용 |
| `apps/boardest/lib/views/canva_board_view.dart` | `_setupWebview`, `_onDhashDetected` | `classId` 연동, 인메모리 판서 캐시 도입, 16:9 컨테이너 적용 |
| `apps/boardest_teacher/lib/views/canva_board_view.dart` | `_setupWebview`, `_onDhashDetected` | 동일 적용 |

---
*보고서 작성 완료: 팀 리드 및 구현 에이전트의 변경 작업에 즉시 활용 가능하도록 완결성 확보됨.*
