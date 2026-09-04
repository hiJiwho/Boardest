# Handoff Report: Electronic Board TBP Engine & Multi-Mode Canvas Exploration

**Agent**: `explorer_board_tbp_engine` (Archetype: `teamwork_preview_explorer`)  
**Target Path**: `c:/Users/jiwho/Documents/boardest/.agents/explorer_board_tbp_engine/handoff.md`  
**Related Report**: `c:/Users/jiwho/Documents/boardest/.agents/explorer_board_tbp_engine/analysis.md`  
**Handoff Type**: Hard (Investigation Complete)

---

## 1. Observation

Direct observations and evidence collected during code inspection:

1. **dHash Engine Offline Script Failure**:
   - `apps/boardest/lib/services/tbp/tbp_dhash_engine.dart:79-85` & `packages/plugins/bst_tbp/lib/src/services/tbp_dhash_engine.dart:79-85`:
     ```javascript
     if (typeof html2canvas === 'undefined') {
       var script = document.createElement('script');
       script.src = 'https://html2canvas.hertzen.com/dist/html2canvas.min.js';
       script.onload = function() {
         html2canvas(document.body).then(computeDhash).catch(function(e){ sendHash(null); });
       };
       script.onerror = function() { sendHash(null); };
       document.head.appendChild(script);
     }
     ```
   - Injected script loads `html2canvas` from external public CDN on every fresh webview session, failing when running on closed/offline school classroom smartboards.

2. **dHash Engine Logic Anomaly in `_onNewHash`**:
   - `apps/boardest/lib/services/tbp/tbp_dhash_engine.dart:183-204`:
     ```dart
     void _onNewHash(String newHash) {
       if (_currentDhash.isEmpty) {
         _currentDhash = newHash;
         onDhashChanged(newHash);
         return;
       }

       final dist = _hammingDistance(_currentDhash, newHash);

       // 노이즈 필터: 3비트 미만 변화는 무시
       if (dist < _noiseFilterBits) return;

       // 매칭 실패 (64비트 초과 → 완전히 다른 페이지로 간주)
       if (dist > _matchThreshold) {
         _currentDhash = newHash;
         onDhashChanged(newHash);
       } else if (dist >= _noiseFilterBits) {
         // 1~64비트 → 같은 페이지의 변형(해상도/렌더링 차이)이지만 일단 갱신
         _currentDhash = newHash;
         onDhashChanged(newHash);
       }
     }
     ```
   - Both `dist > _matchThreshold` (64 bits) and `dist >= _noiseFilterBits` (3 bits) execute identical logic: `_currentDhash = newHash; onDhashChanged(newHash);`. Any minor visual change (e.g. blinking cursor, hover, GIF) triggers full page change callbacks.

3. **Dual Concurrent Background Polling Timers**:
   - `apps/boardest/lib/services/tbp/tbp_dhash_engine.dart:146-157`:
     - `_focusPollingTimer`: `Timer.periodic(const Duration(seconds: 5), ...)`
     - `_fallbackPollingTimer`: `Timer.periodic(const Duration(seconds: 12), ...)`
     - `_burstTimers`: Schedules 7 timers `[0, 215, 462, 994, 2137, 4594, 9877]` ms.
   - 5s and 12s timers run simultaneously calling the same method `_requestHashFromJs()`.

4. **Point Serialization Key Inconsistency**:
   - `AnnotationStroke.toJson` (`apps/boardest/lib/widgets/annotation_canvas.dart:18-23`):
     `'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList()`
   - `AnnotationStroke.fromJson` (`apps/boardest/lib/widgets/annotation_canvas.dart:26-28`):
     `Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble())`
   - `BstPenData.toJson` (`packages/plugins/bst_pen/lib/src/bst_pen_data.dart:21`):
     `'points': stroke.points.map((pt) => {'dx': pt.dx, 'dy': pt.dy}).toList()`
   - `AnnotationStorageService.saveDocumentAnnotations` (`apps/boardest/lib/services/annotation_storage_service.dart:156`):
     `'points': stroke.points.map((pt) => {'dx': pt.dx, 'dy': pt.dy}).toList()`

5. **Store Level 0 TBP Extraction Cache Lifecycle**:
   - `TbpStorageService.instance._ensureExtracted` (`apps/boardest/lib/services/tbp/tbp_storage_service.dart:80-102`):
     - Unpacks `.bstTBP` ZIP to `%TEMP%/bstTBP_{tbpId}`.
     - Caches path in `_extractCache[bstTbpPath]`.
     - No cleanup or LRU eviction routine is provided upon closing the viewer.

6. **Windows Native Click-Through Support**:
   - `apps/boardest/windows/runner/flutter_window.cpp:20-39`: `EnumChildProc` toggles `EnableWindow(hwnd, FALSE)` and `WS_EX_TRANSPARENT` when `setWebviewClickThrough` is invoked.
   - `apps/boardest/lib/views/website_board_view.dart:242-250` calls `setWebviewClickThrough`, but `TbpViewerRoute` and `CanvaBoardView` do not call it on Windows.

7. **Test Suites in Plugin Packages**:
   - `packages/plugins/bst_tbp/test/bst_tbp_test.dart` and `packages/plugins/bst_pen/test/bst_pen_test.dart` contain placeholder template tests (`Calculator.addOne`).

8. **Plugin `packages/plugins/bst_tbp` Dependency Gaps**:
   - `packages/plugins/bst_tbp/pubspec.yaml` contains only `image: ^4.3.0` and lacks `bst_core`, `bst_pen`, `bst_ui`, `google_fonts`, `archive`, `webview_windows`, `universal_io`, generating 900+ analyzer errors in its views and test suites.

---

## 2. Logic Chain

1. **From Observation 1**: Because `TbpDhashEngine` injects a script tag pointing to `https://html2canvas.hertzen.com/dist/html2canvas.min.js`, when a classroom smartboard is connected to an offline LAN or intranet without external internet, the CDN fetch fails, `onerror` fires `sendHash(null)`, and the engine cannot compute dHash or load page-specific hotspots.
2. **From Observation 2**: Because both `if (dist > _matchThreshold)` and `else if (dist >= _noiseFilterBits)` update `_currentDhash` and invoke `onDhashChanged`, any minor visual change between 3 and 64 bits erroneously triggers `_onDhashDetected` in `TbpViewerRoute`, leading to unnecessary hotspot reload calls.
3. **From Observation 3**: Because 5s and 12s timers run concurrently alongside 7-step burst polling without a debounce guard on JS execution, repeated DOM rendering via `html2canvas` causes CPU/GPU spikes on resource-constrained smartboard hardware.
4. **From Observation 4**: Because `AnnotationStorageService` writes point maps with keys `{'dx', 'dy'}` while `AnnotationStroke.fromJson` reads `{'x', 'y'}`, deserializing stroke data through `AnnotationStroke.fromJson` directly results in null access errors unless defensive fallback `p['dx'] ?? p['x']` is used.
5. **From Observation 5**: Because `_extractCache` stores paths indefinitely and never deletes temporary directories, switching between multiple large `.bsttbp` textbook packages gradually leaks temporary disk space in `%TEMP%`.
6. **From Observation 6**: Because `EnumChildProc` in the Windows runner requires explicit invocation of `setWebviewClickThrough` to pass mouse events through native child HWNDs, invoking this method during Pen mode in all WebView-backed views ensures robust touch/pointer handling.
7. **From Observation 7**: Because unit test files in `bst_tbp` and `bst_pen` only test dummy calculator functions, the actual TBP ZIP parsing, dHash calculation, `.bstpen` serialization, and 3-mode canvas state machines are currently unverified by automated CI tests.
8. **From Observation 8**: Because `packages/plugins/bst_tbp/pubspec.yaml` lacks dependencies required by `tbp_viewer_route.dart` and `bst_tbp_test.dart`, static analysis fails with 900+ errors when analyzing the plugin in isolation.

---

## 3. Caveats

- Hardware-specific stylus pressure levels (Wacom/Active Pen vs passive stylus) were analyzed from code logic (`PointerDeviceKind.stylus`); physical hardware testing requires a connected stylus digitizer.
- Native C#/WPF PowerPoint overlay (`boardest_ppt_overlay.exe`) requires Microsoft PowerPoint COM automation on Windows; on non-Windows platforms, `WebHwpPptView` is the designated fallback.
- No other unexplored areas within the assigned scope.

---

## 4. Conclusion

The core architecture of `apps/boardest`, `bst_tbp`, and `bst_pen` is well-designed with Store Level 0 fast loading, 64-hex MAX_PATH protection, and multi-class stroke isolation. To ensure complete operational integrity:
1. Bundle `html2canvas.min.js` locally to eliminate WAN CDN failure.
2. Fix the branch condition in `TbpDhashEngine._onNewHash` to prevent minor visual noise from triggering false page switches.
3. Consolidate polling timers into a single throttled interval.
4. Standardize stroke point serialization to accept both `dx`/`x` and `dy`/`y`.
5. Add `_extractCache` cleanup on viewer disposal.
6. Fix `packages/plugins/bst_tbp/pubspec.yaml` dependencies (`bst_core`, `bst_pen`, `bst_ui`, `google_fonts`, `archive`, `webview_windows`, `universal_io`).
7. Populate unit tests in `packages/plugins/bst_tbp` and `packages/plugins/bst_pen`.

---

## 5. Verification Method

### Automated Tests
Run flutter unit tests across common and plugin packages:
```powershell
flutter test packages/plugins/bst_tbp/test
flutter test packages/plugins/bst_pen/test
flutter test apps/boardest/test
```

### Static Analysis
Run flutter analyzer on affected targets:
```powershell
flutter analyze packages/plugins/bst_tbp packages/plugins/bst_pen apps/boardest
```

### Manual Inspection & Invalidation Checks
- **dHash Offline**: Disconnect internet, launch a `.bsttbp` package in `TbpViewerRoute`, verify that dHash computation succeeds without CDN network requests.
- **dHash Tolerance**: Trigger dynamic animation on webview (e.g. 5-bit change), verify that `onDhashChanged` is NOT triggered when $3 \le \text{dist} \le 64$.
- **Serialization Key**: Inspect saved `.bstpen` JSON files to ensure both `{'dx', 'dy'}` and `{'x', 'y'}` parse seamlessly into `AnnotationStroke` without null errors.
