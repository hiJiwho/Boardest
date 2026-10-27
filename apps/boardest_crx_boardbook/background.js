// Boardest BoardBook Chrome Extension Background Worker (v5.0.13)
const activeSessions = new Map();

// 1. Boardest 웹앱과의 외부 메시지 통신 (Handshake & Launch)
chrome.runtime.onMessageExternal.addListener((request, sender, sendResponse) => {
  if (request.action === 'CHECK_INSTALLED') {
    sendResponse({ installed: true, version: '5.0.13', name: 'Boardest BoardBook' });
    return true;
  }

  if (request.action === 'LAUNCH_BOARDBOOK') {
    const { driveToken, fileUrl, title, type, pointerId, hotspots } = request;
    
    // 일회성 보안 세션 토큰 발급 (무단 직접 접속 방지)
    const sessionToken = 'bst_session_' + Date.now() + '_' + Math.random().toString(36).substring(2, 10);
    const sessionData = {
      sessionToken,
      driveToken: driveToken || '',
      fileUrl: fileUrl || '',
      title: title || '스마트 교재',
      type: type || 'TBP',
      pointerId: pointerId || '',
      hotspots: hotspots || [],
      createdAt: Date.now(),
      targetTabId: null,
    };

    activeSessions.set(sessionToken, sessionData);

    // 10분 후 만료 처리
    setTimeout(() => {
      activeSessions.delete(sessionToken);
    }, 10 * 60 * 1000);

    // BoardBook Flutter 전용 뷰어 탭 오픈
    const viewerUrl = chrome.runtime.getURL(`boardbook_flutter.html?session=${encodeURIComponent(sessionToken)}`);
    chrome.tabs.create({ url: viewerUrl }, (tab) => {
      sendResponse({ success: true, sessionToken, tabId: tab.id });
    });
    return true;
  }

  sendResponse({ success: false, error: 'Unknown action' });
  return true;
});

// 2. 내부 통신 (boardbook.html <-> background.js)
chrome.runtime.onMessage.addListener((request, sender, sendResponse) => {
  // 세션 유효성 검증
  if (request.action === 'VALIDATE_SESSION') {
    const session = activeSessions.get(request.sessionToken);
    if (!session) {
      sendResponse({ valid: false, error: '유효하지 않거나 만료된 세션입니다. Boardest에서 다시 열어주세요.' });
      return true;
    }
    sendResponse({ valid: true, data: session });
    return true;
  }

  // 대상 교과서/Canva 탭 열기 & ID 바인딩
  if (request.action === 'OPEN_CONTENT_TAB') {
    const { sessionToken, url } = request;
    const session = activeSessions.get(sessionToken);
    if (!session) {
      sendResponse({ success: false, error: 'Session not found' });
      return true;
    }

    chrome.tabs.create({ url, active: false }, (targetTab) => {
      session.targetTabId = targetTab.id;
      sendResponse({ success: true, targetTabId: targetTab.id });
    });
    return true;
  }

  // 초고속 무간섭 탭 스크린샷 캡처
  if (request.action === 'CAPTURE_TARGET_TAB') {
    const { targetTabId } = request;
    if (!targetTabId) {
      // 현재 창 보이는 영역 캡처
      chrome.tabs.captureVisibleTab(null, { format: 'jpeg', quality: 90 }, (dataUrl) => {
        if (chrome.runtime.lastError || !dataUrl) {
          sendResponse({ success: false, error: chrome.runtime.lastError?.message });
        } else {
          sendResponse({ success: true, dataUrl });
        }
      });
      return true;
    }

    // 대상 탭 정보 조회 후 윈도우 캡처
    chrome.tabs.get(targetTabId, (tab) => {
      if (chrome.runtime.lastError || !tab) {
        sendResponse({ success: false, error: 'Target tab closed' });
        return;
      }
      chrome.tabs.captureVisibleTab(tab.windowId, { format: 'jpeg', quality: 90 }, (dataUrl) => {
        if (chrome.runtime.lastError || !dataUrl) {
          sendResponse({ success: false, error: chrome.runtime.lastError?.message });
        } else {
          sendResponse({ success: true, dataUrl });
        }
      });
    });
    return true;
  }

  // 클릭/이벤트 패스스루 조작 대행
  if (request.action === 'DISPATCH_EVENT_TO_TAB') {
    const { targetTabId, eventType, x, y } = request;
    if (!targetTabId) {
      sendResponse({ success: false });
      return true;
    }

    chrome.scripting.executeScript({
      target: { tabId: targetTabId },
      func: (type, posX, posY) => {
        const el = document.elementFromPoint(posX, posY);
        if (el) {
          if (type === 'click') {
            el.click();
          } else {
            const evt = new MouseEvent(type, {
              bubbles: true,
              cancelable: true,
              clientX: posX,
              clientY: posY,
              view: window,
            });
            el.dispatchEvent(evt);
          }
        }
      },
      args: [eventType, x, y],
    }).then(() => sendResponse({ success: true })).catch((e) => sendResponse({ success: false, error: e.message }));
    return true;
  }

  // 대상 탭 페이지 전환 (이전/다음 키보드 이벤트 전달)
  if (request.action === 'NAVIGATE_TAB') {
    const { targetTabId, direction } = request;
    if (!targetTabId) {
      sendResponse({ success: false });
      return true;
    }
    chrome.scripting.executeScript({
      target: { tabId: targetTabId },
      func: (dir) => {
        const key = dir === 'prev' ? 'ArrowLeft' : 'ArrowRight';
        const keyCode = dir === 'prev' ? 37 : 39;
        window.dispatchEvent(new KeyboardEvent('keydown', { key, keyCode, bubbles: true }));
        window.dispatchEvent(new KeyboardEvent('keyup', { key, keyCode, bubbles: true }));
        if (dir === 'prev') {
          window.scrollBy({ top: -window.innerHeight * 0.8, behavior: 'smooth' });
        } else {
          window.scrollBy({ top: window.innerHeight * 0.8, behavior: 'smooth' });
        }
      },
      args: [direction],
    }).then(() => sendResponse({ success: true })).catch((e) => sendResponse({ success: false, error: e.message }));
    return true;
  }
});
