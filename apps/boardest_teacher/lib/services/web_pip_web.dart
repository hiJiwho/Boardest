import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;

class WebPipService {
  static dynamic _pipWindow;

  static bool get isSupported => true;

  static Future<void> openMiniPipWindow({
    required String periodText,
    required String teacherClass,
    required String teacherSubject,
    required String classroomSubject,
    required String classroomTeacher,
    required String schoolName,
    required bool isDark,
    String otpCode = '------',
    String cloudId = '12',
    int remainingSeconds = 60,
  }) async {
    try {
      final docPip = js.context['documentPictureInPicture'];
      if (docPip != null) {
        final promise = (docPip as dynamic).requestWindow(js.JsObject.jsify({
          'width': 360,
          'height': 160,
        }));
        final pipWin = await js.context['Promise'].callMethod('resolve', [promise]);
        if (pipWin != null) {
          _pipWindow = pipWin;
          final doc = (pipWin as dynamic)['document'];
          _injectPipContent(doc, periodText, teacherClass, teacherSubject, classroomSubject, classroomTeacher, schoolName, isDark, otpCode, cloudId, remainingSeconds);
          return;
        }
      }
    } catch (e) {
      // Fallback to popup window
    }

    final width = 360;
    final height = 180;
    final left = (html.window.screen?.width != null) ? html.window.screen!.width! - width - 20 : 100;
    final top = 80;
    final features = 'width=$width,height=$height,left=$left,top=$top,menubar=no,toolbar=no,location=no,status=no,resizable=yes';

    final win = js.context.callMethod('open', ['', 'boardest_mini_pip', features]);
    if (win != null) {
      _pipWindow = win;
      final doc = win['document'];
      _injectPipContent(doc, periodText, teacherClass, teacherSubject, classroomSubject, classroomTeacher, schoolName, isDark, otpCode, cloudId, remainingSeconds);
    }
  }

  static void _injectPipContent(
    dynamic doc,
    String periodText,
    String teacherClass,
    String teacherSubject,
    String classroomSubject,
    String classroomTeacher,
    String schoolName,
    bool isDark,
    String otpCode,
    String cloudId,
    int remainingSeconds,
  ) {
    if (doc == null) return;
    final bg = isDark ? '#0F0E17' : '#F7F7F9';
    final cardBg = isDark ? '#16161A' : '#FFFFFF';
    final border = isDark ? '#242629' : '#E2E8F0';
    final text = isDark ? '#FFFFFE' : '#1A202C';
    final textMuted = isDark ? '#94A1B2' : '#718096';
    final mint = '#00F5D4';
    final purple = '#7F5AF0';
    final indigo = '#6366F1';

    final htmlContent = '''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Boardest Mini</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Noto Sans KR", sans-serif; user-select: none; }
    body { background: $bg; color: $text; padding: 10px 12px; overflow: hidden; height: 100vh; display: flex; flex-direction: column; justify-content: space-between; }
    .header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 6px; }
    .title { font-size: 11px; font-weight: 700; color: $textMuted; }
    .tabs { display: flex; gap: 4px; }
    .tab-btn { background: rgba(255,255,255,0.06); border: 1px solid rgba(255,255,255,0.12); color: $textMuted; font-size: 10px; font-weight: 600; padding: 2px 7px; border-radius: 5px; cursor: pointer; }
    .tab-btn.active { background: rgba(99,102,241,0.25); border-color: $indigo; color: #FFF; font-weight: 700; }
    .content-pane { display: none; height: calc(100% - 28px); }
    .content-pane.active { display: flex; flex-direction: column; justify-content: center; }
    .otp-card { background: rgba(99,102,241,0.12); border: 1px solid rgba(99,102,241,0.3); border-radius: 8px; padding: 8px 12px; display: flex; align-items: center; justify-content: space-between; cursor: pointer; }
    .otp-digits { font-size: 24px; font-weight: 900; color: #FFF; letter-spacing: 3px; font-family: monospace; }
    .otp-id { font-size: 11px; font-weight: 700; color: #818CF8; margin-bottom: 2px; }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
    .card { background: $cardBg; border: 1px solid $border; border-radius: 8px; padding: 8px; }
    .card-label { font-size: 10px; font-weight: 600; color: $textMuted; margin-bottom: 3px; display: flex; align-items: center; }
    .card-label span { width: 5px; height: 5px; border-radius: 50%; margin-right: 4px; }
    .t-dot { background: $mint; }
    .c-dot { background: $purple; }
    .card-main { font-size: 13px; font-weight: 800; color: $text; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
    .card-sub { font-size: 11px; color: $textMuted; margin-top: 2px; }
    .period { font-size: 10.5px; font-weight: 700; color: #FF8906; margin-bottom: 4px; }
  </style>
</head>
<body>
  <div class="header">
    <div class="title">✨ $schoolName</div>
    <div class="tabs">
      <button class="tab-btn active" onclick="switchTab(0)">🔑 OTP</button>
      <button class="tab-btn" onclick="switchTab(1)">👨‍🏫 교사</button>
      <button class="tab-btn" onclick="switchTab(2)">🏫 교실</button>
    </div>
  </div>

  <!-- Tab 0: OTP -->
  <div id="pane-0" class="content-pane active">
    <div class="otp-card" onclick="copyOtp()">
      <div>
        <div class="otp-id">ID: $cloudId (터치하여 복사)</div>
        <div class="otp-digits">$otpCode</div>
      </div>
      <div style="font-size: 11px; color: $textMuted; font-weight: 600;">⏱️ ${remainingSeconds}s</div>
    </div>
  </div>

  <!-- Tab 1: Teacher Timetable -->
  <div id="pane-1" class="content-pane">
    <div class="card" style="border-left: 3px solid $mint;">
      <div class="period">$periodText</div>
      <div class="card-label"><span class="t-dot"></span>내 수업</div>
      <div class="card-main">${teacherClass.isNotEmpty ? teacherClass : '수업 없음'}</div>
      <div class="card-sub">${teacherSubject.isNotEmpty ? teacherSubject : '-'}</div>
    </div>
  </div>

  <!-- Tab 2: Classroom Timetable -->
  <div id="pane-2" class="content-pane">
    <div class="card" style="border-left: 3px solid $purple;">
      <div class="period">$periodText</div>
      <div class="card-label"><span class="c-dot"></span>우리 반</div>
      <div class="card-main">${classroomSubject.isNotEmpty ? classroomSubject : '수업 없음'}</div>
      <div class="card-sub">${classroomTeacher.isNotEmpty ? classroomTeacher : '-'}</div>
    </div>
  </div>

  <script>
    function switchTab(idx) {
      document.querySelectorAll('.tab-btn').forEach((b, i) => {
        b.classList.toggle('active', i === idx);
      });
      document.querySelectorAll('.content-pane').forEach((p, i) => {
        p.classList.toggle('active', i === idx);
      });
    }
    function copyOtp() {
      navigator.clipboard.writeText('$otpCode');
      alert('접속 코드 [$otpCode] 복사 완료!');
    }
  </script>
</body>
</html>''';

    doc.callMethod('open');
    doc.callMethod('write', [htmlContent]);
    doc.callMethod('close');
  }
}
