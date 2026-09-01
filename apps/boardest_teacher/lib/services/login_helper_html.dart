class LoginHelperHtml {
  static String generate({
    required bool showBoardest,
    required bool showCloud,
    required bool showCanva,
    String? cloudDone,
    String? canvaDone,
    String? boardestDone,
  }) {
    final bool isDone = (boardestDone == 'true' || cloudDone == 'true');
    return '''
<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Boardest Teacher 로그인</title>
  <link href="https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;500;700&display=swap" rel="stylesheet">
  <link href="https://fonts.googleapis.com/icon?family=Material+Icons+Round" rel="stylesheet">
  <style>
    body {
      font-family: 'Noto Sans KR', sans-serif;
      background: #0F0E17;
      color: white;
      margin: 0;
      padding: 40px 20px;
      display: flex;
      flex-direction: column;
      align-items: center;
      min-height: 100vh;
      box-sizing: border-box;
    }
    h1 {
      color: #00F5D4;
      font-size: 1.8rem;
      margin-bottom: 30px;
      display: flex;
      align-items: center;
      gap: 10px;
    }
    .container {
      display: flex;
      flex-direction: column;
      gap: 20px;
      width: 100%;
      max-width: 440px;
    }
    .card {
      background: #16161A;
      border: 1px solid rgba(255,255,255,0.1);
      border-radius: 18px;
      padding: 24px;
      display: flex;
      flex-direction: column;
      gap: 16px;
      box-shadow: 0 12px 32px rgba(0,0,0,0.4);
    }
    .card-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .card-title {
      font-size: 1.2rem;
      font-weight: 700;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .badge {
      background: rgba(0,245,212,0.15);
      border: 1px solid #00F5D4;
      color: #00F5D4;
      padding: 4px 12px;
      border-radius: 20px;
      font-size: 0.85rem;
      font-weight: bold;
    }
    .cloud-option-box {
      background: rgba(255,255,255,0.03);
      border: 1px solid rgba(255,255,255,0.08);
      border-radius: 12px;
      padding: 14px;
      display: flex;
      flex-direction: column;
      gap: 6px;
    }
    .checkbox-label {
      display: flex;
      align-items: center;
      gap: 10px;
      font-size: 0.95rem;
      font-weight: 600;
      color: white;
      cursor: pointer;
    }
    .checkbox-label input {
      width: 18px;
      height: 18px;
      accent-color: #00F5D4;
      cursor: pointer;
    }
    .cloud-desc {
      font-size: 0.8rem;
      color: #94A1B2;
      margin: 0;
      padding-left: 28px;
      line-height: 1.4;
    }
    .btn {
      background: #7F5AF0;
      color: white;
      border: none;
      padding: 14px;
      border-radius: 12px;
      font-size: 1rem;
      font-weight: 700;
      cursor: pointer;
      transition: all 0.2s;
      text-align: center;
      text-decoration: none;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
    }
    .btn:hover {
      background: #6c46db;
      transform: translateY(-1px);
    }
    .btn:disabled {
      background: #242629;
      color: #666;
      cursor: not-allowed;
      transform: none;
    }
    .btn-complete {
      margin-top: 10px;
      background: #00F5D4;
      color: #0F0E17;
      font-weight: 800;
      font-size: 1.1rem;
      padding: 16px;
    }
    .btn-complete:hover {
      background: #00d8b9;
    }
  </style>
  <script>
    function startLogin() {
      const useCloud = document.getElementById('useCloudCheckbox').checked;
      if (useCloud) {
        window.location.href = '/start-cloud-oauth';
      } else {
        window.location.href = '/start-boardest-oauth';
      }
    }

    async function finishLogin() {
      const btn = document.getElementById('btn-complete');
      btn.disabled = true;
      btn.textContent = '앱에 전달 중...';
      try {
        await fetch('/notify-app', { method: 'POST' });
      } catch (e) {
        console.log('notify-app fetch:', e);
      }
      btn.textContent = '✅ 완료되었습니다! 이 창을 닫아주세요.';
      setTimeout(() => {
        try { window.close(); } catch (_) {}
      }, 500);
    }
  </script>
</head>
<body>
  <h1>
    <span class="material-icons-round" style="font-size:32px;">school</span>
    Boardest Teacher
  </h1>
  <div class="container">
    
    <div class="card">
      <div class="card-header">
        <div class="card-title">
          <span class="material-icons-round">account_circle</span>
          Google 계정 연동
        </div>
        ${isDone ? '<div class="badge">🟢 인증 완료</div>' : ''}
      </div>

      ${!isDone ? '''
      <div class="cloud-option-box">
        <label class="checkbox-label">
          <input type="checkbox" id="useCloudCheckbox" checked />
          <span>☁️ Boardest Cloud (Google Drive) 연동 사용</span>
        </label>
        <p class="cloud-desc">체크 시 교실 전자칠판 수업자료 동기화를 위한 Drive API 접근 권한을 요청합니다.</p>
      </div>

      <button class="btn" onclick="startLogin()">
        <span class="material-icons-round">login</span>
        Google 계정으로 로그인
      </button>
      ''' : '''
      <p style="color:#00F5D4; font-weight:600; margin:4px 0;">✅ Google 계정 로그인이 정상적으로 완료되었습니다.</p>
      '''}
    </div>

    ${showCanva ? '''
    <div class="card">
      <div class="card-header">
        <div class="card-title">
          <span class="material-icons-round">brush</span>
          Canva 연동 (선택)
        </div>
        ${canvaDone == 'true' ? '<div class="badge">🟢 완료</div>' : ''}
      </div>
      ${canvaDone != 'true' ? '<button class="btn" onclick="window.location.href=\'/start-canva-oauth\'">Canva 권한 부여하기</button>' : ''}
    </div>
    ''' : ''}

    <button id="btn-complete" class="btn btn-complete" ${isDone ? '' : 'disabled'} onclick="finishLogin()">
      🚀 앱으로 열기 (완료)
    </button>
  </div>
</body>
</html>
    ''';
  }
}
