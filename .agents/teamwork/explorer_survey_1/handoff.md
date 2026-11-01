# Handoff Report — Issue Group 1 Investigation

- **Agent**: teamwork_explorer_survey_1
- **Working Directory**: `c:\Users\jiwho\Documents\boardest\.agents\teamwork\explorer_survey_1\`
- **Milestone**: Survey (Issue Group 1: TBP & Canva Viewers)
- **Handoff Type**: Hard (Task Complete)

---

## 1. Observation

### Obs 1: 1536px 배율 및 래스터 스케일링 코드
- **파일**: `apps/boardest_teacher/lib/services/tbp/tbp_dhash_engine.dart` (라인 71~110), `apps/boardest/lib/services/tbp/tbp_dhash_engine.dart` (라인 71~110)
- **직접 관찰 내용**:
  ```javascript
  function sync1536Scale() {
    var targetW = 1536;
    var targetH = 864;
    var winW = (window.__bstGetRealW ? window.__bstGetRealW() : window.innerWidth) || screen.width || 1536;
    var winH = (window.__bstGetRealH ? window.__bstGetRealH() : window.innerHeight) || screen.height || 864;
    var scale = Math.min(winW / targetW, winH / targetH);
    ...
    styleEl.textContent = 'html { width: 100% !important; ... } body { width: 1536px !important; ... ' +
      'transform: translate(' + offsetX.toFixed(2) + 'px, ' + offsetY.toFixed(2) + 'px) scale(' + scale.toFixed(4) + ') !important; ... }';
  }
  ```
  - 브라우저 DOM `body`에 강제로 CSS `transform: scale(...)`을 주입하여 컴포지터가 1536x864로 그린 텍스처를 확대함.
  - 이로 인해 FHD(1920x1080), QHD(2560x1440), 4K(3840x2160) 등 모니터에서 글꼴 힌팅이 깨지고 그래픽이 흐려짐.
  - 동시에 `Object.defineProperty(window, 'innerWidth', { get: function() { return 1536; } })`로 반응형 웹앱(Canva 등)의 자체 레이아웃 뷰포트 계산을 파괴함.
- 반면 `webview_windows` 패키지 소스 (`C:\Users\jiwho\AppData\Local\Pub\Cache\hosted\pub.dev\webview_windows-0.4.0\lib\src\webview.dart:442`)에 `Future<void> setZoomFactor(double zoomFactor)`가 지원되고 있음을 확인.

### Obs 2: 판서 파일 포맷 및 네이밍 규약
- **파일**: `apps/boardest_teacher/lib/services/tbp/tbp_storage_service.dart` (라인 883~929, 975~996), `apps/boardest/lib/services/tbp/tbp_storage_service.dart` (라인 848~895, 942~963)
- **직접 관찰 내용**:
  ```dart
  if (classKey != null) {
    final classDir = Directory(p.join(tbpFolderPath, 'BBPen', classKey));
    ...
    final classSvg = File(p.join(classDir.path, '$base.svg'));
    final classBstpen = File(p.join(classDir.path, '$base.bstpen'));
  } else {
    final bbpenFile = File(p.join(bbpenDir.path, '$base.svg'));
    final strokeFile = File(p.join(targetDir.path, '$base.bstpen'));
    final rootStrokeFile = File(p.join(tbpFolderPath, 'pen_$base.bstpen'));
  }
  ```
  - 저장 시 `BBPen/[classKey]/[base].svg` 및 `[base].bstpen`으로 저장하고 있어, 유저 요구사항인 `[교실ID]dhash.pen` (예: `기본_dhash.pen`, `[1반]dhash.pen`) 파일명이 생성되지 않음.
  - 또한 `canva_board_view.dart` (라인 451, 460)에서는 `savePenStrokes`와 `loadPenStrokes` 호출 시 `classId` 매개변수를 전혀 넘기지 않고 있음.
  - `tbp_viewer_route.dart` (라인 563)에서 `if (prevHash != 'default')`로 인해 첫 페이지가 `default`일 때 저장이 누락됨.

### Obs 3: 2페이지 건너뜀 (이중 트리거)
- **파일**: `apps/boardest_teacher/lib/views/tbp/tbp_viewer_route.dart` (라인 664~688, 863~867), `apps/boardest/lib/views/tbp/tbp_viewer_route.dart` (라인 664~688, 863~867)
- **직접 관찰 내용**:
  - `TbpViewerRoute`의 위젯 트리에 `Focus(focusNode: _keyboardFocus, onKeyEvent: _onKeyEvent)`가 장착되어 있음.
  - 키보드 방향키(`ArrowRight`) 또는 `PageDown` 입력 시:
    1) Windows OS가 자식 윈도우인 WebView2에 `WM_KEYDOWN`을 전달하여 웹페이지가 1페이지 이동.
    2) Flutter의 `_onKeyEvent`가 동일한 키를 감지하여 `_navigatePage(true)`를 호출하고, `_dhashEngine.navigatePage()` 스크립트를 웹뷰에 주입하여 버튼 클릭 또는 합성 키보드 이벤트를 재실행.
    3) 결과적으로 1회의 키 입력에 2페이지가 연속으로 건너뜀.
  - `tbp_dhash_engine.dart` (라인 267, 270, 403)에서 페이지 감지 폴링이 `250ms`, `120ms` 등으로 느리게 설정되어 있음.

### Obs 4: Canva 및 TBP dHash 고착 버그 (`hash__1` / `default`)
- **파일**: `apps/boardest_teacher/lib/services/tbp/tbp_dhash_engine.dart` (라인 182~188), `apps/boardest/lib/services/tbp/tbp_dhash_engine.dart` (라인 182~188)
- **직접 관찰 내용**:
  ```javascript
  var loc = (w && w.location) ? w.location : window.location;
  if (loc && loc.hostname && loc.hostname.indexOf('canva.com') !== -1) {
    var chash = (loc.hash && loc.hash.length > 1)
        ? loc.hash.replace(/[^a-zA-Z0-9_-]/g, '_')
        : '_1';
    return 'hash_' + chash;
  }
  ```
  - Canva 임베드 URL(`https://www.canva.com/design/.../view?embed`)은 슬라이드를 넘겨도 `loc.hash`가 항상 빈 문자열임.
  - 따라서 `chash`는 예외 없이 `'_1'`이 되어 **무조건 `'hash__1'`을 리턴**.
  - `checkPage()`에서 `detectedId === window.__bstLastPageId` ('hash__1' === 'hash__1')로 판단하여 이벤트 발송이 중단됨.
  - `tbp_storage_service.dart` (라인 730, 871)에서 `key == 'hash__1' || key == 'ui_home'`인 경우 `default.json`, `query__embed.json`으로 강제 리다이렉트하여 모든 페이지가 `default` 판서로 덮어씌워짐.

---

## 2. Logic Chain

1. **[Obs 1 -> 1536 선명도 결론]**:
   - `sync1536Scale()`의 CSS `transform: scale()`은 브라우저 텍스처를 인위적으로 확대하여 래스터 블러(blur)를 유발함.
   - `webview_windows`의 네이티브 `setZoomFactor(W / 1536.0)`를 사용하면 Chromium이 뷰포트를 1536x864로 인식하면서 렌더링은 네이티브 모니터 DPI 픽셀 단위로 선명하게 수행함.
   - 따라서 CSS transform scale을 제거하고 WebView2의 `setZoomFactor`와 16:9 컨테이너를 연동해야 함.

2. **[Obs 2 -> 판서 포맷 및 100% 복원 결론]**:
   - 현재 저장은 `BBPen/[classId]/[hash].svg` 형태로 되어 있어 명세인 `[교실ID]dhash.pen`과 불일치함.
   - 페이지 전환 시 비동기 디스크 쓰기가 끝나기 전에 이전 페이지를 로드하거나 리스너가 빈 배열을 저장하는 경쟁 상태가 발생함.
   - 따라서 파일명을 `[교실ID]dhash.pen` (예: `기본_dhash.pen`, `[1반]dhash.pen`)으로 생성/탐색하도록 일원화하고, 뷰어 State 내에 `_pageStrokesMemory` (인메모리 캐시)를 두어 페이지 이동 및 복귀 시 0ms 즉시 복원을 보장해야 함.

3. **[Obs 3 -> 2페이지 건너뜀 차단 결론]**:
   - WebView2 네이티브 키 이벤트와 Flutter `Focus` 이벤트가 동시에 작동하여 2회 트리거됨.
   - WebView2 내부에 Capture-phase 키보드 인터셉터를 설치해 네이티브 처리를 차단하고 Flutter를 통한 단일 제어 경로만 허용하면 1키 1페이지 정밀 이동이 달성됨.
   - 이동 직후 50ms 시점에 `checkPage()`를 강제 호출하면 초고속 감지가 이루어짐.

4. **[Obs 4 -> dHash 고착 해소 결론]**:
   - Canva에서 `loc.hash`에 의존하는 하드코딩이 `'hash__1'` 고착의 단일 원인임.
   - Canva DOM의 슬라이드 번호 텍스트(정규식 `/\b(\d+)\s*\/\s*(\d+)\b/`) 및 가상 페이지 카운터를 매핑하고, StorageService의 `hash__1` -> `default` 리다이렉트를 제거하면 각 슬라이드가 고유한 dHash를 가지게 됨.

---

## 3. Caveats

- 외부 CDN(예: html2canvas CDN)에 의존하지 않는 순수 DOM 및 셀렉터 기반 해시 추출을 기준으로 검토했습니다.
- Canva 외의 기타 타사 프레젠테이션 사이트(Google Slides, 미리캔버스 등)도 Canva와 동일하게 16:9 컨테이너 및 가상 슬라이드 인덱스의 수혜를 받습니다.
- 본 조사는 Explorer로서 Read-Only 모드로 진행되었으며, 소스 코드를 직접 수정하지 않고 제안 코드를 문서화하였습니다.

---

## 4. Conclusion

1. **1536px 배율**:
   - `tbp_dhash_engine.dart`의 `sync1536Scale()` 내 파괴적 CSS `transform: scale()` 제거.
   - `tbp_viewer_route.dart` 및 `canva_board_view.dart`에서 `LayoutBuilder`의 실제 폭 `W`를 기반으로 `_winWebview.setZoomFactor(W / 1536.0)`를 설정하여 모니터 해상도에 무관한 100% 벡터 선명도 보장.
2. **판서 파일 포맷 및 보존**:
   - `TbpStorageService.saveStrokeData` 및 `loadStrokeData`를 수정하여 `[교실ID]dhash.pen` (예: `기본_dhash.pen`, `[1반]dhash.pen`) 규약 적용.
   - 뷰어 State에 `_pageStrokesMemory` 맵을 탑재하여 페이지 전환 시 0ms 즉시 복원 보장.
3. **2페이지 건너뜀 제거**:
   - `tbp_dhash_engine.dart`의 JS 스크립트에 Capture-Phase 키보드 인터셉터 장착 (`preventDefault()`, `stopImmediatePropagation()`).
   - Flutter 네비게이션에 350ms 디바운스 및 50ms 초고속 페이지 감지 트리거 적용.
4. **dHash 고착 버그 해결**:
   - `tbp_dhash_engine.dart`의 Canva 전용 DOM 카운터 정규식 탐색(`/\b(\d+)\s*\/\s*(\d+)\b/`) 및 가상 페이지 fallback 도입.
   - `tbp_storage_service.dart`의 `hash__1` -> `default` 강제 폴백 매핑 제거.

---

## 5. Verification Method

구현 완료 후 아래 항목으로 독립 검증 가능:

1. **정적 분석 및 컴파일 검증**:
   - `flutter analyze apps/boardest`
   - `flutter analyze apps/boardest_teacher`
   - `flutter analyze packages/plugins/bst_tbp`
2. **단위 테스트 실행**:
   - `flutter test apps/boardest/test/tbp_pointer_resolution_test.dart`
   - `flutter test packages/plugins/bst_tbp/test/bst_tbp_test.dart`
3. **기능 검증 시나리오**:
   - **1536 선명도**: QHD/4K 모니터에서 TBP 교과서 및 Canva 실행 시 텍스트가 흐려지지 않고 네이티브 픽셀로 선명하게 렌더링되는지 확인.
   - **판서 파일 포맷**: 교과서/Canva 실행 후 1반 선택 -> 1페이지에 판서 -> `PEN/` 폴더 내에 `[1반]page_1.pen` (또는 `기본_page_1.pen`)이 생성되는지 확인.
   - **판서 복원**: 1페이지 판서 후 2페이지로 이동 -> 다시 1페이지로 복귀 시 판서가 0ms 즉시 복원되는지 확인.
   - **1키 1페이지**: PageDown 또는 ArrowRight를 1회 눌렀을 때 정확히 1페이지만 이동하는지 확인 (2페이지 건너뜀 재현 불가 확인).
   - **Canva dHash**: Canva 슬라이드 넘김 시 콘솔에 `canva_p1`, `canva_p2`, `canva_p3` 등 서로 다른 고유 dHash가 찍히는지 확인.
