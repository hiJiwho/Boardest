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

  // 1. 보안 세션 토큰 검증 (무단 직접 접속 완벽 차단)
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

  // 5. 캡처 루프 (초고속 화면 동기화)
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
    }, 800); // 0.8초 주기 캡처 동기화
  }

  // 6. 우측 판서 엔진 (Smooth Bezier 2D Annotation)
  let currentTool = 'pen'; // 'pen', 'eraser'
  let currentColor = '#00F5D4';
  let strokeWidth = 4;
  let isDrawing = false;
  let strokes = []; // { tool, color, width, points: [{x,y}] }
  let currentStroke = null;
  let isInteractionPassThrough = false;

  penCanvas.addEventListener('pointerdown', (e) => {
    if (isInteractionPassThrough) {
      // 사이트 조작 통과 모드 시 대상 탭으로 이벤트 전달
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
    currentStroke = {
      tool: currentTool,
      color: currentColor,
      width: currentTool === 'eraser' ? 24 : strokeWidth,
      points: [{ x: e.offsetX, y: e.offsetY }],
    };
    strokes.push(currentStroke);
  });

  penCanvas.addEventListener('pointermove', (e) => {
    if (!isDrawing || !currentStroke || isInteractionPassThrough) return;
    const pt = { x: e.offsetX, y: e.offsetY };
    currentStroke.points.push(pt);

    // 증분 드로잉
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
      }
      penCtx.beginPath();
      penCtx.moveTo(pts[pts.length - 2].x, pts[pts.length - 2].y);
      penCtx.lineTo(pt.x, pt.y);
      penCtx.stroke();
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
      }
      penCtx.beginPath();
      penCtx.moveTo(s.points[0].x, s.points[0].y);
      for (let i = 1; i < s.points.length; i++) {
        penCtx.lineTo(s.points[i].x, s.points[i].y);
      }
      penCtx.stroke();
    }
    penCtx.globalCompositeOperation = 'source-over';
  }

  // 7. 우측 툴바 이벤트 연결
  const toolPenBtn = document.getElementById('tool-pen');
  const toolEraserBtn = document.getElementById('tool-eraser');
  const toolClearBtn = document.getElementById('tool-clear-all');
  const colorDots = document.querySelectorAll('.color-dot');

  toolPenBtn.addEventListener('click', () => {
    currentTool = 'pen';
    toolPenBtn.classList.add('active');
    toolEraserBtn.classList.remove('active');
  });

  toolEraserBtn.addEventListener('click', () => {
    currentTool = 'eraser';
    toolEraserBtn.classList.add('active');
    toolPenBtn.classList.remove('active');
  });

  toolClearBtn.addEventListener('click', () => {
    strokes = [];
    penCtx.clearRect(0, 0, penCanvas.width, penCanvas.height);
  });

  colorDots.forEach((dot) => {
    dot.addEventListener('click', () => {
      colorDots.forEach((d) => d.classList.remove('active'));
      dot.classList.add('active');
      currentColor = dot.dataset.color;
      currentTool = 'pen';
      toolPenBtn.classList.add('active');
      toolEraserBtn.classList.remove('active');
    });
  });

  // 8. 사이트 조작 / 판서 모드 토글
  modeBtn.addEventListener('click', () => {
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
  });

  // 뒤로가기
  document.getElementById('btn-back').addEventListener('click', () => {
    window.close();
  });
})();
