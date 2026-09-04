# Comprehensive Analysis: Boardest Electronic Board, TBP Engine, dHash Matching & Multi-Mode Canvas

**Investigator**: `explorer_board_tbp_engine` (Archetype: `teamwork_preview_explorer`)  
**Date**: 2026-08-21  
**Scope**: `apps/boardest`, `packages/plugins/bst_tbp`, `packages/plugins/bst_pen`, `packages/common/bst_core`

---

## 1. Executive Summary

A comprehensive architectural inspection and diagnostics were performed on the **Boardest Electronic Board app (`apps/boardest`)**, the **Store Level 0 TBP (TextBook Plus) engine (`packages/plugins/bst_tbp` & `apps/boardest/lib/services/tbp`)**, the **dHash visual page matching algorithm**, the **`.bstpen` drawing stroke persistence/serialization pipeline**, and the **3-mode canvas / multi-platform touch event dispatching system**.

### Key Assessment Summary
| Domain | Health / Status | Key Diagnostics & Vulnerabilities |
| :--- | :--- | :--- |
| **App Architecture (`apps/boardest`)** | 🟢 Solid | Clean entry flow, defensive error logging (`NativeStartupHelper.writeCrashLog`), multi-tool routing, platform-specific initialization ladders for Windows, Android, and Web. |
| **Store Level 0 TBP Engine** | 🟡 Functional with Caching Defect | `.bstTBP` (Store Level 0 uncompressed ZIP) provides low-latency extraction. However, extracted temp folders in `%TEMP%/bstTBP_*` are never garbage-collected during the session, risking disk bloat on long-running smartboard sessions. |
| **dHash Visual Matching Engine** | 🔴 Critical Defects Identified | 1) **Offline failure**: Injected JS attempts to load `html2canvas` from external CDN (`https://html2canvas.hertzen.com/...`), failing on offline school intranets.<br>2) **Algorithmic branch flaw in `_onNewHash`**: `dist > 64` and `dist >= 3` execute identical page transition logic, triggering spurious page reloads on 4-63 bit noise.<br>3) **Dual timer redundancy**: 5s focus polling and 12s fallback timers run simultaneously calling the same routine. |
| **`.bstpen` Stroke Persistence & Integrity** | 🟡 Functional with Schema Key Inconsistency | `.bstpen` files are safely written with atomic flush (`flush: true`) and sanitized paths avoiding Win32 `MAX_PATH` (260 char) errors. However, key serialization disparity exists: `AnnotationStroke.toJson` serializes points as `{'x', 'y'}` while `BstPenData` and `AnnotationStorageService` serialize points as `{'dx', 'dy'}`. |
| **3-Mode Canvas & Event Pipeline** | 🟡 Functional with Minor Platform Gaps | 3-mode canvas (Pen, Smart, Touch) is cleanly implemented in `TbpViewerRoute` via 500ms long-press disambiguation. Windows native HWND click-through works in `WebsiteBoardView` via `EnumChildProc` (`setWebviewClickThrough`), but is omitted in `TbpViewerRoute` and `CanvaBoardView`. |

---

## 2. Architecture of `apps/boardest` (Boardest Electronic Board App)

### 2.1 Initialization Ladder (`apps/boardest/lib/main.dart`)
1. **Global Error Traps**:
   - `FlutterError.onError`: Logs unhandled Flutter framework errors to console and writes to `%APPDATA%/jiwho.boardest.board/crash_logs.txt`.
   - `PlatformDispatcher.instance.onError`: Catches asynchronous platform errors.
2. **Platform Setup**:
   - Non-Web (`!kIsWeb`): Calls `AppPaths.init()`, `BstSaveService.instance.ensureStructure()`, and `NativeStartupHelper.runWindowsStartupTasks()`.
   - Smartboard UI Ergonomics: Calls `SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight])` and `SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)`.
3. **Firebase Authentication Strategy**:
   - On Web and Mobile (Android/iOS/macOS), calls `Firebase.initializeApp`.
   - On Web, invokes a tiered persistence strategy: `Persistence.LOCAL` $\rightarrow$ `Persistence.SESSION` $\rightarrow$ `Persistence.NONE`.
   - On Windows/Linux desktop, Firebase initialization is deliberately bypassed to prevent native DLL initialization crashes; desktop utilizes local school credentials and Direct REST/Firestore endpoints.
4. **Auto-Healing & Silent Auto-Login**:
   - If `settings.isSetupComplete` is true but `currentUser` is null, automatically attempts class login via `authService.loginOrSignupClass(...)` using saved region, school, grade, and class numbers (`apps/boardest/lib/main.dart:110-132`).
5. **Multi-Tool CLI & Android Intent Dispatch**:
   - CLI flags: `-board` (whiteboard), `-timer`, `-picker`, `-weather`, `-calendar`, `-ppt` / `-ppt_board`, `-hwp` / `-hwp_board`, `-s` (fullscreen PPT), `-pdf` / `-pdf_board`, `-site` / `-website_board`, `-calculator`, `-notepad`, `-dice`, `-timetable`, `-noise`, `-settings`, `-explorer`.
   - File associations: `.bsttbp` / `.tbp` $\rightarrow$ `tbp_viewer`, `.bstcanva` $\rightarrow$ `canva_board`.
   - Android MethodChannel: `com.boardest/launch_args` $\rightarrow$ `getLaunchTool`.

---

## 3. Store Level 0 TBP Package Loading, Unpacking & Caching

### 3.1 Store Level 0 Format Specification
The `.bstTBP` package is an uncompressed ZIP container (Store Level 0, `compressionType = 0`) designed for zero-decompression CPU overhead on smartboard hardware.

```
[Package.bsttbp] (Store Level 0 ZIP)
├── meta.bstsave          # Metadata: title, author, folderId, scopeKey, timestamps (JSON)
├── info.json             # Backward-compatible configuration (e.g., target webUrl)
├── HOTspot/              # Interactive hotspots indexed by dHash
│   └── {dHash_hex}/
│       └── hotspot.bstsave
├── PEN/                  # Class-specific pen stroke vectors indexed by dHash
│   └── {classCode}/
│       └── {dHash_hex}.bstpen
└── Downloads/            # Cached downloadable assets (PDF, PPT, HWP, images, videos)
    └── {dHash_hex}/
        └── {filename}
```

### 3.2 Packaging & Unpacking Mechanism (`TbpStorageService`)
- **Packaging (`packageBstTbp`)**:
  Located at `apps/boardest/lib/services/tbp/tbp_storage_service.dart:244-269`:
  ```dart
  final archive = Archive();
  // Iterates directory and adds uncompressed files:
  archive.addFile(ArchiveFile.noCompress(relative, bytes.length, bytes));
  final encodedBytes = ZipEncoder().encode(archive);
  await File(outputBstTbpPath).writeAsBytes(encodedBytes);
  ```
- **Unpacking & In-Memory Extraction Cache (`_ensureExtracted`)**:
  Located at `apps/boardest/lib/services/tbp/tbp_storage_service.dart:80-102`:
  - Decodes ZIP bytes using `ZipDecoder().decodeBytes(bytes)`.
  - Unpacks contents into `%TEMP%/bstTBP_{tbpId}`.
  - Caches extract path in `_extractCache[bstTbpPath] = extractDir.path`.

### 3.3 Diagnostic Findings & Risks
1. **Extraction Cache Lifecycle Leak**:
   - `_extractCache` is retained in the singleton `TbpStorageService` without an LRU eviction or disposal mechanism. If a teacher opens multiple large TBP textbooks during a school day, temporary directories accumulate in `%TEMP%` and are never cleaned up until manual OS temp purge.
2. **Universal IO Platform Guard on Web**:
   - `TbpStorageService` directly invokes `universal_io/io.dart` file system calls (`File(p.join(...)).existsSync()`). On Flutter Web, local file system operations do not map to physical disk. `TbpViewerRoute` handles this on Web by checking `widget.tbpFilePath.startsWith('http')` and delegating to `getIframeViewWidget`, but opening local `.bsttbp` files on Web without cloud storage returns null.

---

## 4. dHash Visual Page Matching Engine & Indexing

### 4.1 Perceptual Differential Hashing Algorithm (`TbpDhashEngine`)
The perceptual hashing algorithm runs in the embedded WebView context (`apps/boardest/lib/services/tbp/tbp_dhash_engine.dart:35-93`):

1. **Screen Capture**: Takes a raster snapshot of `document.body` using `html2canvas`.
2. **Center Square Crop**: Extracts a square region from the center of the rendered canvas:
   $$size = \min(w, h), \quad sx = \frac{w - size}{2}, \quad sy = \frac{h - size}{2}$$
3. **Resize to $17 \times 16$ Matrix**: Draws into an offscreen canvas of width 17 and height 16 ($17 \times 16 = 272$ pixels).
4. **Grayscale Conversion**: Calculates luminance using standard ITU-R BT.601 coefficients:
   $$Gray = 0.299 \cdot R + 0.587 \cdot G + 0.114 \cdot B$$
5. **Differential Comparison (dHash)**:
   For each row $y \in [0, 15]$ and column $x \in [0, 15]$:
   $$\text{bit}(y, x) = \begin{cases} '1' & \text{if } Gray[y \cdot 17 + x] > Gray[y \cdot 17 + x + 1] \\ '0' & \text{otherwise} \end{cases}$$
   Produces a **256-bit binary string** representing horizontal luminance gradients.
6. **IPC Message Passing**: Sends the 256-bit hash back to Flutter via `window.chrome.webview.postMessage` (Windows) or `window.TbpChannel.postMessage` (Android).

### 4.2 Hash Indexing & Win32 `MAX_PATH` Protection
- **Problem**: When 256-character binary strings (`010110...`) were used directly as folder names on Windows (`%APPDATA%/.../HOTspot/{dHash}/...`), the total path length exceeded the Win32 `MAX_PATH` limit (260 characters), causing `errno = 123` file system crashes.
- **Solution (`TbpStorageService.sanitizeKey`)**:
  Compact 256-bit binary strings into **64-character hexadecimal strings** by grouping 4 bits into radix-16 characters:
  ```dart
  static String sanitizeKey(String key) {
    if (key.length > 32 && RegExp(r'^[01]+$').hasMatch(key)) {
      final sb = StringBuffer();
      for (int i = 0; i < key.length; i += 4) {
        final end = (i + 4 < key.length) ? i + 4 : key.length;
        final chunk = key.substring(i, end).padRight(4, '0');
        sb.write(int.parse(chunk, radix: 2).toRadixString(16));
      }
      return sb.toString();
    }
    return key;
  }
  ```

### 4.3 Detailed Defects & Anomalies in `TbpDhashEngine`

```
                                 [ Incoming dHash ]
                                         │
                         ┌───────────────┴───────────────┐
                         │  Hamming Distance Metric (d)  │
                         └───────────────┬───────────────┘
                                         │
               ┌─────────────────────────┼─────────────────────────┐
               ▼                         ▼                         ▼
         [ d < 3 bits ]          [ 3 <= d <= 64 bits ]       [ d > 64 bits ]
         (Noise Filter)          (Expected: SAME Page)       (Expected: NEW Page)
               │                         │                         │
            IGNORED             ⚠️ BUG: Fires NEW Page       Fires NEW Page
                              (identical to d > 64)
```

#### Defect 1: External CDN Network Dependency (Offline Failure)
- **Location**: `apps/boardest/lib/services/tbp/tbp_dhash_engine.dart:80`
- **Code**: `script.src = 'https://html2canvas.hertzen.com/dist/html2canvas.min.js';`
- **Impact**: Smartboards on closed school LANs or intranet environments fail to load `html2canvas.min.js`. The script onerror handler returns `sendHash(null)`, completely disabling page matching and hotspot loading.
- **Remedy**: Bundle `html2canvas.min.js` in `assets/bst-web/` or inline the minified JS directly in the injected string.

#### Defect 2: Algorithmic Branch Duplication in `_onNewHash`
- **Location**: `apps/boardest/lib/services/tbp/tbp_dhash_engine.dart:183-204`
- **Code**:
  ```dart
  void _onNewHash(String newHash) {
    if (_currentDhash.isEmpty) {
      _currentDhash = newHash;
      onDhashChanged(newHash);
      return;
    }
    final dist = _hammingDistance(_currentDhash, newHash);
    if (dist < _noiseFilterBits) return; // < 3

    if (dist > _matchThreshold) { // > 64
      _currentDhash = newHash;
      onDhashChanged(newHash);
    } else if (dist >= _noiseFilterBits) { // 3 <= dist <= 64
      _currentDhash = newHash;
      onDhashChanged(newHash);
    }
  }
  ```
- **Impact**: The `else if (dist >= _noiseFilterBits)` branch executes the exact same state mutation and `onDhashChanged(newHash)` callback as `dist > _matchThreshold`. Consequently, whenever any minor on-screen animation or GIF alters 4 to 63 bits, the engine interprets it as a complete page transition, reloading hotspots and clearing active annotations.
- **Remedy**: When $3 \le \text{dist} \le 64$, the engine should recognize that the user is on the *same* page (within tolerance) and update `_currentDhash` without firing a full page transition callback, or use the matched canonical dHash key.

#### Defect 3: Redundant Concurrent Polling Timers
- **Location**: `apps/boardest/lib/services/tbp/tbp_dhash_engine.dart:145-157`
- **Code**:
  - `_focusPollingTimer`: `Timer.periodic(const Duration(seconds: 5), ...)`
  - `_fallbackPollingTimer`: `Timer.periodic(const Duration(seconds: 12), ...)`
  - `_burstTimers`: 7 timers scheduled at `[0, 215, 462, 994, 2137, 4594, 9877]` ms.
- **Impact**: Both periodic timers call `_requestHashFromJs()`. At seconds 60, 120, 180, etc., both 5s and 12s timers collide. Furthermore, running `html2canvas(document.body)` every 200ms during burst capture incurs significant CPU/GPU rendering overhead on low-power Intel Celeron/Core i3 or ARM smartboards.

---

## 5. `.bstpen` Drawing Stroke Data Serialization, Persistence & Integrity

### 5.1 Serialization Format Comparison
There are two minor schema dialects for serializing point coordinates in the codebase:

| Implementation | File | Points Key Schema | Color / Type Format |
| :--- | :--- | :--- | :--- |
| **`AnnotationStroke`** | `apps/boardest/lib/widgets/annotation_canvas.dart:18-35` | `{'x': p.dx, 'y': p.dy}` | `Color(json['color'] as int)` |
| **`BstPenData`** | `packages/plugins/bst_pen/lib/src/bst_pen_data.dart:21,46` | `{'dx': pt.dx, 'dy': pt.dy}` | `Color(strokeMap['color'] as int)` |
| **`AnnotationStorageService`** | `apps/boardest/lib/services/annotation_storage_service.dart:156,217` | `{'dx': pt.dx, 'dy': pt.dy}` | `Color(strokeMap['color'] as int)` |
| **`BoardStorageService` (`.iwb`)** | `apps/boardest/lib/services/board_storage_service.dart:118-127` | `{'dx': pt.dx, 'dy': pt.dy}` | `type: int` (Pen, Marker, etc.) |
| **Native WPF Overlay (`.iwb`)** | `apps/boardest/boardest_ppt_overlay.cs:1340-1370` | `{'dx': pt.dx, 'dy': pt.dy}` | `color: int`, `strokeWidth: double` |

#### Compatibility Analysis
- `AnnotationStorageService` and `BstPenData` write and parse `{'dx', 'dy'}`.
- `AnnotationStroke.fromJson` expects `{'x', 'y'}`.
- If an `AnnotationStroke` is deserialized via `AnnotationStroke.fromJson` from a `.bstpen` file written by `AnnotationStorageService`, it encounters null values for `json['x']` and throws a TypeError.
- **Remedy**: Standardize `AnnotationStroke.fromJson` to defensively accept both `p['dx'] ?? p['x']` and `p['dy'] ?? p['y']`.

### 5.2 Multi-Class Pen Isolation (`classToCode`)
- `AnnotationStorageService.classToCode` (`apps/boardest/lib/services/annotation_storage_service.dart:32-43`):
  - `"1학년 1반"` $\rightarrow$ `"[101]"`
  - `"2학년 3반"` $\rightarrow$ `"[203]"`
  - Special classrooms: `"과학실"` $\rightarrow$ `"[과학실]"`
  - Integrated/Common: `"전체 반 공용 (통합)"` $\rightarrow$ `""`
- **Layering Logic on Load**:
  When loading annotations for `[101]`, `AnnotationStorageService.loadDocumentAnnotations` (`lines 228-260`) loads `[101]{filename}.bstpen`, then reads the master common file (`{filename}.bstpen`), and prepends the common master strokes at index 0 (`result[pageIdx]!.insertAll(0, commonStrokes)`). This enables teachers to maintain shared textbook markings while preserving individual class notes.

### 5.3 Auto-Save, Undo/Redo & Corruption Prevention
1. **Atomic Flush**: All file writes in `AnnotationStorageService`, `TbpStorageService`, and `BoardStorageService` use `writeAsString(..., flush: true)` to ensure that OS write buffers are flushed to disk before returning, preventing zero-byte file corruption during sudden power-offs on smartboards.
2. **Legacy Format Fallback Ladder**:
   `AnnotationStorageService._findLegacyFile` scans `.bstpen` $\rightarrow$ `.iwb` $\rightarrow$ `.IWB` across `bst-pen/` and `bst-save/` directories, ensuring 100% backward compatibility with legacy versions.
3. **Undo/Redo Stack**:
   - `AnnotationController`: Maintains a 30-step deep-copied snapshot queue `_undoHistory` (`List<AnnotationStroke>.from(_strokes)`).
   - `BoardestPenView`: Maintains per-page `_undoHistory[p]` and `_redoStack[p]` with automatic snapshot capture on `_onPanStart` for drawing, erasing, lasso manipulation, and shape generation.

---

## 6. 3-Mode Canvas, Event Passing & Multi-Platform Stability

### 6.1 3-Mode Canvas Architecture in `TbpViewerRoute`

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Stack (16:9 Aspect Ratio)                                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│ 1. WebView Layer: IgnorePointer(ignoring: _isAnnotationEnabled)             │
│    - WebviewController (Windows) / WebViewController (Android) / Iframe(Web)│
├─────────────────────────────────────────────────────────────────────────────┤
│ 2. Annotation Layer: IgnorePointer(ignoring: !_isAnnotationEnabled)          │
│    - AnnotationCanvas (CustomPaint, Pen/Eraser/Shape/Select)                │
├─────────────────────────────────────────────────────────────────────────────┤
│ 3. Hotspot Overlay Layer: TbpHotspotOverlay                                 │
│    - 8 Hotspot types (URL, Doc, Video, Image, Memo, Timer, Audio, Page)     │
│    - Listener(behavior: HitTestBehavior.opaque, onPointerDown: ...)         │
└─────────────────────────────────────────────────────────────────────────────┘
```

| Mode | Canvas State | Gesture / Touch Behavior | Hotspot Status |
| :--- | :--- | :--- | :--- |
| **`TbpInputMode.pen`** | Enabled (`_isAnnotationEnabled = true`) | All touches and mouse drags draw strokes on the canvas. WebView is ignored. | Dimmed (opacity 0.45), non-interactable. |
| **`TbpInputMode.smart`** *(Default)* | Enabled by default; toggled on long-press | Standard tap/drag draws strokes. **500ms Long-press** activates `_longPressActive = true` $\rightarrow$ `_isAnnotationEnabled = false`, passing touch events through to interactive textbook elements & hotspots. | Fully interactable. |
| **`TbpInputMode.touch`** | Disabled (`_isAnnotationEnabled = false`) | All touches and gestures pass directly to the underlying WebView for navigation, zooming, and website interaction. | Fully interactable. |

### 6.2 Windows Native Event Passthrough (`EnumChildProc`)
- In `WebsiteBoardView` (`apps/boardest/lib/views/website_board_view.dart:242-250`), toggling `_isDrawMode` invokes the native method channel `setWebviewClickThrough`.
- In `apps/boardest/windows/runner/flutter_window.cpp:20-39`, `EnumChildProc` iterates through child HWNDs (the WebView2 container window):
  - When `clickThrough == true` (Draw mode): Disables the native child window with `EnableWindow(hwnd, FALSE)` and applies `WS_EX_TRANSPARENT`, allowing Win32 pointer messages to pass through to Flutter's DirectX view.
  - When `clickThrough == false` (Site interaction mode): Re-enables the child window with `EnableWindow(hwnd, TRUE)` and strips `WS_EX_TRANSPARENT`.
- **Finding**: In `TbpViewerRoute` and `CanvaBoardView`, `setWebviewClickThrough` is not explicitly called on Windows when switching between Pen and Touch modes; they rely on Flutter texture composition. For embedded webviews rendering as HWND children, adding `setWebviewClickThrough` guarantees touch dispatch consistency.

### 6.3 Stylus & Palm Rejection Mechanism (`BoardestPenView`)
- `apps/boardest/lib/views/boardest_pen_view.dart:938-952`:
  - Intercepts pointer events via `Listener(onPointerDown: ...)`:
    ```dart
    _lastPointerKind = event.kind;
    if (event.kind == PointerDeviceKind.stylus || event.kind == PointerDeviceKind.invertedStylus) {
      _hasSeenStylus = true;
    }
    if (event.kind == PointerDeviceKind.invertedStylus) {
      if (_tool != ToolMode.eraser) setState(() => _tool = ToolMode.eraser);
    }
    ```
  - **Inverted Stylus Auto-Eraser**: Turning the digital pen upside-down automatically triggers `ToolMode.eraser`.
  - **Palm Rejection Guard** (`lines 564-570`):
    When `_palmRejectionEnabled` is active and stylus input has been detected, simultaneous or trailing `PointerDeviceKind.touch` events on the canvas are ignored, preventing palm resting artifacts.

### 6.4 Multi-Platform Stability Matrix
| Feature / Platform | Windows (Desktop) | Android (Smartboard) | Web (Chrome / Edge) |
| :--- | :--- | :--- | :--- |
| **WebView Engine** | `webview_windows` (WebView2) | `webview_flutter` (Android System WebView) | `IframeElement` via `getIframeViewWidget` |
| **Window Frame & Scaling** | Custom DWM borderless with rounded corners (`DwmSetWindowAttribute`) | Immersive Sticky Mode & Landscape orientation lock | Browser viewport responsive scaling |
| **Native Document Overlays** | C#/WPF Overlay Bridges (`boardest_ppt_overlay.exe`, `boardest_hwp_overlay.exe`) | In-app `PdfBoardView` / `WebHwpPptView` | `WebHwpPptView` / in-memory PDF reader |
| **Persistence Storage** | `%APPDATA%/jiwho.boardest.board/` | App Support Directory via `path_provider` | HTML5 `LocalStorage` (`SharedPreferences`) |

---

## 7. Diagnostic Findings & Issue Matrix

| # | Component | Severity | Description | Recommended Remediation |
| :--- | :--- | :--- | :--- | :--- |
| **1** | `tbp_dhash_engine.dart` | 🔴 **High** | External CDN dependency (`html2canvas.min.js`) fails in offline/intranet classrooms. | Bundle `html2canvas.min.js` locally in `assets/bst-web/` or embed directly into the script string. |
| **2** | `tbp_dhash_engine.dart` | 🔴 **High** | `_onNewHash` treats noise (3–64 bits) identically to page change (>64 bits). | Correct branch condition so that 3–64 bit variations update reference hash without triggering full `onDhashChanged`. |
| **3** | `tbp_dhash_engine.dart` | 🟡 **Medium** | Redundant dual timers (5s + 12s) and excessive 7-timer burst polling schedules. | Consolidate background polling into a single 5s timer and throttle burst timers to 3 intervals (e.g. 0, 300, 1000ms). |
| **4** | `annotation_canvas.dart` vs `bst_pen_data.dart` | 🟡 **Medium** | Schema key disparity (`x`/`y` vs `dx`/`dy`) in stroke serialization. | Update `AnnotationStroke.fromJson` and `BstPenData.fromJson` to handle both `dx`/`x` and `dy`/`y`. |
| **5** | `tbp_storage_service.dart` | 🟡 **Medium** | `%TEMP%/bstTBP_*` directories are not cleaned up on viewer exit. | Add cleanup/cache eviction routine in `TbpStorageService` or on `TbpViewerRoute.dispose()`. |
| **6** | `tbp_download_interceptor.dart` | 🟡 **Medium** | `openSupportedViewer` only handles `.pdf`, `.ppt`, `.hwp`; images and videos fall through without opening. | Route `.mp4`/`.avi` to `VideoBoardView` and image formats to `_showImagePopup`. |
| **7** | `pdf_board_view.dart` | 🟡 **Low** | In-memory page cache `_cachedPages` has no LRU eviction limit, risking high memory on 200+ page PDFs. | Implement a sliding window LRU cache (e.g. current $\pm 5$ pages). |
| **8** | `bst_tbp_test.dart` / `bst_pen_test.dart` | 🟡 **Medium** | Unit tests in plugin packages are boilerplate placeholder templates (`Calculator.addOne`). | Implement comprehensive unit tests covering TBP Store Level 0 parsing, dHash calculation, `.bstpen` serialization, and 3-mode canvas state machines. |
| **9** | `packages/plugins/bst_tbp/pubspec.yaml` | 🔴 **High** | Standalone plugin `bst_tbp` lacks dependencies (`bst_core`, `bst_pen`, `bst_ui`, `google_fonts`, `archive`, `webview_windows`, `webview_flutter`, `universal_io`), causing 900+ analyzer errors in `packages/plugins/bst_tbp/lib/src/views/tbp_viewer_route.dart`. | Add missing package dependencies and path references to `packages/plugins/bst_tbp/pubspec.yaml` or streamline plugin exports. |

---

## 8. Conclusion

The core architectural foundations of `apps/boardest`, `bst_tbp`, and `bst_pen` are robust, high-performing, and well-adapted for classroom smartboard interaction. Addressing the identified dHash offline script bundling, matching branch conditions, serialization key fallbacks, and plugin test suites will bring the electronic board engine to production-grade stability and zero-defect reliability.
