// Boardest BoardBook Core Engine (CRX Port v5.0.13)
(async function() {
  const urlParams = new URLSearchParams(window.location.search);
  const sessionToken = urlParams.get('session');

  const authBlocked = document.getElementById('auth-blocked');
  const viewerContainer = document.getElementById('viewer-container');
  const docTitle = document.getElementById('doc-title');
  const docTypeBadge = document.getElementById('doc-type-badge');
  const pageIndicator = document.getElementById('page-indicator');
  const modeBtn = document.getElementById('btn-toggle-interaction');
  const modeIcon = document.getElementById('mode-icon');
  const modeText = document.getElementById('mode-text');

  const bgCanvas = document.getElementById('bg-canvas');
  const penCanvas = document.getElementById('pen-canvas');
  const bgCtx = bgCanvas.getContext('2d');
  const penCtx = penCanvas.getContext('2d');

  // 1. 보안 세션 토큰 검증
  if (!sessionToken) {
    showAuthBlocked('세션 토큰이 전달되지 않았습니다.');
    return;
  }

  let sessionData = null;
  try {
    const res = await chrome.runtime.sendMessage({ action: 'VALIDATE_SESSION', sessionToken });
    if (!res || !res.valid) {
      showAuthBlocked(res?.error || '만료되었거나 유효하지 않은 세션입니다.');
      return;
    }
    sessionData = res.data;
  } catch (e) {
    showAuthBlocked('Boardest 익스텐션 인증 통신 실패: ' + e.message);
    return;
  }

  function showAuthBlocked(msg) {
    authBlocked.classList.remove('hidden');
    viewerContainer.classList.add('hidden');
    console.warn('[BoardBook] Access Denied:', msg);
  }

  // 2. 세션 데이터 초기화
  docTitle.textContent = sessionData.title || '스마트 교재';
  docTypeBadge.textContent = sessionData.type || 'TBP';
  if (sessionData.type === 'HTMLP') {
    docTypeBadge.style.background = 'rgba(0, 245, 212, 0.2)';
    docTypeBadge.style.color = '#00F5D4';
    docTypeBadge.style.borderColor = 'rgba(0, 245, 212, 0.5)';
  }

  // 3. 캔버스 리사이즈
  function resizeCanvases() {
    const stage = document.getElementById('stage');
    bgCanvas.width = stage.clientWidth;
    bgCanvas.height = stage.clientHeight;
    penCanvas.width = stage.clientWidth;
    penCanvas.height = stage.clientHeight;
    redrawStrokes();
  }
  window.addEventListener('resize', resizeCanvases);
  resizeCanvases();

  // 4. 대상 교과서/Canva 탭 오픈 및 캡처 바인딩
  let targetTabId = null;
  if (sessionData.fileUrl && sessionData.fileUrl.startsWith('http')) {
    chrome.runtime.sendMessage({
      action: 'OPEN_CONTENT_TAB',
      sessionToken,
      url: sessionData.fileUrl,
    }, (res) => {
      if (res && res.success) {
        targetTabId = res.targetTabId;
        startCaptureLoop();
      }
    });
  }

  // 5. 캡처 루프 (화면 동기화)
  let isCapturing = false;
  function startCaptureLoop() {
    setInterval(async () => {
      if (isCapturing || !targetTabId) return;
      isCapturing = true;
      try {
        const res = await chrome.runtime.sendMessage({ action: 'CAPTURE_TARGET_TAB', targetTabId });
        if (res && res.success && res.dataUrl) {
          const img = new Image();
          img.onload = () => {
            bgCtx.clearRect(0, 0, bgCanvas.width, bgCanvas.height);
            // 캔버스 중앙 비율 유지 렌더링
            const hRatio = bgCanvas.width / img.width;
            const vRatio = bgCanvas.height / img.height;
            const ratio = Math.min(hRatio, vRatio);
            const centerShiftX = (bgCanvas.width - img.width * ratio) / 2;
            const centerShiftY = (bgCanvas.height - img.height * ratio) / 2;
            bgCtx.drawImage(img, 0, 0, img.width, img.height,
              centerShiftX, centerShiftY, img.width * ratio, img.height * ratio);
            isCapturing = false;
          };
          img.src = res.dataUrl;
        } else {
          isCapturing = false;
        }
      } catch (_) {
        isCapturing = false;
      }
    }, 800);
  }

  // 6. 우측 판서 엔진 (Smooth Bezier 2D Annotation)
  let currentTool = 'pen'; // 'pen', 'highlighter', 'eraser'
  let currentColor = '#00F5D4';
  let isDrawing = false;
  let strokes = []; // { tool, color, width, opacity, points: [{x,y}] }
  let currentStroke = null;
  let isInteractionPassThrough = false;

  function getStrokeParams() {
    if (currentTool === 'eraser') {
      return { width: 26, opacity: 1.0 };
    } else if (currentTool === 'highlighter') {
      return { width: 18, opacity: 0.35 };
    }
    return { width: 4, opacity: 1.0 };
  }

  penCanvas.addEventListener('pointerdown', (e) => {
    if (isInteractionPassThrough) {
      chrome.runtime.sendMessage({
        action: 'DISPATCH_EVENT_TO_TAB',
        targetTabId,
        eventType: 'click',
        x: e.clientX,
        y: e.clientY - 56,
      });
      return;
    }

    isDrawing = true;
    penCanvas.setPointerCapture(e.pointerId);
    const params = getStrokeParams();
    currentStroke = {
      tool: currentTool,
      color: currentColor,
      width: params.width,
      opacity: params.opacity,
      points: [{ x: e.offsetX, y: e.offsetY }],
    };
    strokes.push(currentStroke);
  });

  penCanvas.addEventListener('pointermove', (e) => {
    if (!isDrawing || !currentStroke || isInteractionPassThrough) return;
    const pt = { x: e.offsetX, y: e.offsetY };
    currentStroke.points.push(pt);

    const pts = currentStroke.points;
    if (pts.length > 1) {
      penCtx.lineWidth = currentStroke.width;
      penCtx.lineCap = 'round';
      penCtx.lineJoin = 'round';

      if (currentStroke.tool === 'eraser') {
        penCtx.globalCompositeOperation = 'destination-out';
      } else {
        penCtx.globalCompositeOperation = 'source-over';
        penCtx.strokeStyle = currentStroke.color;
        penCtx.globalAlpha = currentStroke.opacity;
      }

      penCtx.beginPath();
      // Smooth quadratic curves
      if (pts.length > 2) {
        const xc = (pts[pts.length - 2].x + pt.x) / 2;
        const yc = (pts[pts.length - 2].y + pt.y) / 2;
        penCtx.moveTo(pts[pts.length - 2].x, pts[pts.length - 2].y);
        penCtx.quadraticCurveTo(xc, yc, pt.x, pt.y);
      } else {
        penCtx.moveTo(pts[0].x, pts[0].y);
        penCtx.lineTo(pt.x, pt.y);
      }
      penCtx.stroke();
      penCtx.globalAlpha = 1.0;
    }
  });

  penCanvas.addEventListener('pointerup', () => {
    isDrawing = false;
    currentStroke = null;
  });

  function redrawStrokes() {
    penCtx.clearRect(0, 0, penCanvas.width, penCanvas.height);
    for (const s of strokes) {
      if (s.points.length < 2) continue;
      penCtx.lineWidth = s.width;
      penCtx.lineCap = 'round';
      penCtx.lineJoin = 'round';

      if (s.tool === 'eraser') {
        penCtx.globalCompositeOperation = 'destination-out';
      } else {
        penCtx.globalCompositeOperation = 'source-over';
        penCtx.strokeStyle = s.color;
        penCtx.globalAlpha = s.opacity || 1.0;
      }

      penCtx.beginPath();
      penCtx.moveTo(s.points[0].x, s.points[0].y);
      for (let i = 1; i < s.points.length - 1; i++) {
        const xc = (s.points[i].x + s.points[i + 1].x) / 2;
        const yc = (s.points[i].y + s.points[i + 1].y) / 2;
        penCtx.quadraticCurveTo(s.points[i].x, s.points[i].y, xc, yc);
      }
      penCtx.lineTo(s.points[s.points.length - 1].x, s.points[s.points.length - 1].y);
      penCtx.stroke();
      penCtx.globalAlpha = 1.0;
    }
    penCtx.globalCompositeOperation = 'source-over';
  }

  function undoLastStroke() {
    if (strokes.length > 0) {
      strokes.pop();
      redrawStrokes();
    }
  }

  // 7. 우측 툴바 이벤트 연결
  const toolPenBtn = document.getElementById('tool-pen');
  const toolHighlighterBtn = document.getElementById('tool-highlighter');
  const toolEraserBtn = document.getElementById('tool-eraser');
  const toolUndoBtn = document.getElementById('tool-undo');
  const toolClearBtn = document.getElementById('tool-clear-all');
  const toolHelpBtn = document.getElementById('tool-help');
  const colorDots = document.querySelectorAll('.color-dot');
  const shortcutsModal = document.getElementById('shortcuts-modal');
  const btnCloseModal = document.getElementById('btn-close-modal');

  function setActiveTool(tool) {
    currentTool = tool;
    toolPenBtn.classList.toggle('active', tool === 'pen');
    if (toolHighlighterBtn) toolHighlighterBtn.classList.toggle('active', tool === 'highlighter');
    toolEraserBtn.classList.toggle('active', tool === 'eraser');
  }

  toolPenBtn.addEventListener('click', () => setActiveTool('pen'));
  if (toolHighlighterBtn) {
    toolHighlighterBtn.addEventListener('click', () => setActiveTool('highlighter'));
  }
  toolEraserBtn.addEventListener('click', () => setActiveTool('eraser'));
  if (toolUndoBtn) {
    toolUndoBtn.addEventListener('click', undoLastStroke);
  }
  toolClearBtn.addEventListener('click', () => {
    strokes = [];
    penCtx.clearRect(0, 0, penCanvas.width, penCanvas.height);
  });

  colorDots.forEach((dot) => {
    dot.addEventListener('click', () => {
      colorDots.forEach((d) => d.classList.remove('active'));
      dot.classList.add('active');
      currentColor = dot.dataset.color;
      if (currentTool === 'eraser') {
        setActiveTool('pen');
      }
    });
  });

  // 8. 사이트 조작 / 판서 모드 토글
  function toggleInteractionMode() {
    isInteractionPassThrough = !isInteractionPassThrough;
    if (isInteractionPassThrough) {
      modeBtn.classList.remove('active');
      modeBtn.style.background = 'rgba(255, 209, 102, 0.2)';
      modeBtn.style.borderColor = 'rgba(255, 209, 102, 0.5)';
      modeBtn.style.color = '#FFD166';
      modeIcon.textContent = '👆';
      modeText.textContent = '사이트 조작 모드';
      penCanvas.style.cursor = 'default';
    } else {
      modeBtn.classList.add('active');
      modeBtn.style.background = 'rgba(0, 245, 212, 0.15)';
      modeBtn.style.borderColor = 'rgba(0, 245, 212, 0.4)';
      modeBtn.style.color = '#00F5D4';
      modeIcon.textContent = '✏️';
      modeText.textContent = '판서 모드';
      penCanvas.style.cursor = 'crosshair';
    }
  }
  modeBtn.addEventListener('click', toggleInteractionMode);

  // 9. 페이지 이동
  function navigatePage(direction) {
    if (targetTabId) {
      chrome.runtime.sendMessage({
        action: 'NAVIGATE_TAB',
        targetTabId,
        direction,
      });
    }
  }

  document.getElementById('btn-prev-page').addEventListener('click', () => navigatePage('prev'));
  document.getElementById('btn-next-page').addEventListener('click', () => navigatePage('next'));

  // 뒤로가기
  document.getElementById('btn-back').addEventListener('click', () => {
    window.close();
  });

  // 10. 단축키 모달
  function toggleShortcutsModal() {
    shortcutsModal.classList.toggle('hidden');
  }
  if (toolHelpBtn) toolHelpBtn.addEventListener('click', toggleShortcutsModal);
  if (btnCloseModal) btnCloseModal.addEventListener('click', () => shortcutsModal.classList.add('hidden'));
  shortcutsModal.addEventListener('click', (e) => {
    if (e.target === shortcutsModal) shortcutsModal.classList.add('hidden');
  });

  // 11. 전역 단축키 핸들러
  window.addEventListener('keydown', (e) => {
    // 텍스트 필드 포커스 중 제외
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;

    if (e.ctrlKey && (e.key === 'z' || e.key === 'Z')) {
      e.preventDefault();
      undoLastStroke();
      return;
    }

    if (e.key === 'p' || e.key === 'P') {
      setActiveTool('pen');
    } else if (e.key === 'h' || e.key === 'H') {
      setActiveTool('highlighter');
    } else if (e.key === 'e' || e.key === 'E') {
      setActiveTool('eraser');
    } else if (e.key === 'c' || e.key === 'C') {
      strokes = [];
      penCtx.clearRect(0, 0, penCanvas.width, penCanvas.height);
    } else if (e.key === ' ') {
      e.preventDefault();
      toggleInteractionMode();
    } else if (e.key === 'ArrowLeft') {
      navigatePage('prev');
    } else if (e.key === 'ArrowRight') {
      navigatePage('next');
    } else if (e.key === '?' || e.key === 'F1') {
      toggleShortcutsModal();
    } else if (e.key === 'Escape') {
      shortcutsModal.classList.add('hidden');
    }
  });
})();
