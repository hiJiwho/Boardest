import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../services/storage_service.dart';
import '../services/cloud_drive_service.dart';
import '../models/app_settings.dart';
import '../config/app_config.dart';
import '../helpers/notification_helper.dart';

/// Boardest 학급 쪽지 및 긴급 알림/공지 발송 네이티브 뷰어 (온라인 교실 전용)
class MessageView extends StatefulWidget {
  final double scaleFactor;
  final VoidCallback? onBack;

  const MessageView({super.key, required this.scaleFactor, this.onBack});

  @override
  State<MessageView> createState() => _MessageViewState();
}

class _MessageViewState extends State<MessageView> {
  static String get _apiKey => AppConfig.firebaseApiKey;

  final TextEditingController _msgController = TextEditingController();
  
  AppSettings? _settings;
  bool _isLoading = true;
  bool _isSending = false;
  String? _statusMessage;
  bool _statusIsError = false;

  // 온라인 교실 선택 상태: 전체 선택 또는 개별 온라인 교실 ID Set
  bool _selectAllOnline = true;
  final Set<String> _selectedOnlineDocIds = {};
  List<Map<String, dynamic>> _onlineClassrooms = [];
  Timer? _onlineClassroomTimer;
  bool _isFetchingOnline = false;

  final List<String> _quickPhrases = [
    '🏃 지금 교무실로 오세요.',
    '🏐 체육관으로 이동하세요.',
    '📋 조례/종례 준비하세요.',
    '📚 수업 준비물 챙겨서 대기하세요.',
    '🤫 선생님 말씀에 집중하세요.',
    '🍱 급식실로 순서대로 이동하세요.',
  ];

  final List<Map<String, String>> _sentHistory = [];
  final Set<String> _handledInboxMsgIds = {};
  final List<Map<String, dynamic>> _receivedMessages = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _onlineClassroomTimer?.cancel();
    _msgController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await StorageService().getSettings() ?? AppSettings();
    if (mounted) {
      setState(() {
        _settings = settings;
        _isLoading = false;
      });
    }
    await _fetchOnlineClassrooms();
    _onlineClassroomTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _fetchOnlineClassrooms();
    });
  }

  String _getSchoolConnName() {
    final isDemo = AppConfig.isDemoMode ||
        (_settings?.schoolId.toLowerCase() == 'demo') ||
        (_settings?.connectionName.toLowerCase() == 'demo') ||
        (_settings?.selectedSchool?.name.contains('데모') ?? false) ||
        (CloudDriveService.instance.userEmail?.toLowerCase().endsWith('boardest-teacher-demo.753210.xyz') ?? false);
    if (isDemo) return 'demo';

    if (_settings == null) return 'ydm';
    final code = _settings!.selectedSchool?.code?.toString() ?? '';
    final schoolId = _settings!.schoolId.trim();
    String connName = schoolId.isNotEmpty ? schoolId : _settings!.connectionName;
    if (connName.isEmpty || connName.toLowerCase() == 'my') {
      connName = code.isNotEmpty ? code : 'ydm';
    }
    return connName.toLowerCase();
  }

  Future<void> _fetchOnlineClassrooms() async {
    if (_isFetchingOnline) return;
    _isFetchingOnline = true;
    try {
      final connName = _getSchoolConnName();
      final List<Map<String, dynamic>> parsed = [];

      final nowUtc = DateTime.now().toUtc();
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // 1. Firebase Realtime Database (RTDB) 실시간 데이터 직접 조회 (최고 정확도, 실시간 하트비트)
      try {
        final rtdbUrl = 'https://jiwhosboardest-default-rtdb.firebaseio.com/eat_calls.json';
        final rtdbRes = await http.get(Uri.parse(rtdbUrl)).timeout(const Duration(seconds: 4));
        if (rtdbRes.statusCode == 200 && rtdbRes.body != 'null') {
          final rtdbData = json.decode(rtdbRes.body);
          if (rtdbData is Map) {
            rtdbData.forEach((key, val) {
              if (val is! Map) return;
              final docId = key.toString();
              if (docId.isEmpty) return;

              // ★ Lite 계정 및 비정규 학급은 쪽지 발송 목록에서 완전 제외!
              final isLite = val['isLite'] == true ||
                  docId.toLowerCase().contains('lite') ||
                  docId.toLowerCase().contains('local') ||
                  docId.toLowerCase().contains('special');
              if (isLite) return;

              // 학교 소속 필터링 (데모 모드 시 demo 프리픽스 및 데모 교실 전면 수용)
              final isDemoMatch = AppConfig.isDemoMode ||
                  connName == 'demo' ||
                  (_settings?.schoolId.toLowerCase() == 'demo') ||
                  (CloudDriveService.instance.userEmail?.toLowerCase().endsWith('boardest-teacher-demo.753210.xyz') ?? false);

              final docSchoolCode = (val['schoolCode']?.toString() ?? '').toLowerCase();
              final docSchoolName = (val['schoolName']?.toString() ?? '').toLowerCase();
              final schoolCode = (_settings?.selectedSchool?.code?.toString() ?? '').toLowerCase();
              final schoolId = (_settings?.schoolId ?? '').trim().toLowerCase();
              final schoolName = (_settings?.selectedSchool?.name ?? '').toLowerCase();

              bool isMatch = false;
              if (isDemoMatch) {
                isMatch = docSchoolCode == 'demo' || docSchoolName.contains('데모') || docId.toLowerCase().startsWith('demo');
              } else {
                if (schoolCode.isNotEmpty) {
                  isMatch = docSchoolCode == schoolCode || docId.toLowerCase().startsWith('${schoolCode}_');
                }
                if (!isMatch && schoolId.isNotEmpty) {
                  isMatch = docSchoolCode == schoolId || docId.toLowerCase().startsWith('${schoolId}_');
                }
                if (!isMatch && schoolName.isNotEmpty && docSchoolName.isNotEmpty) {
                  isMatch = docSchoolName == schoolName;
                }
                if (!isMatch && connName.isNotEmpty) {
                  isMatch = docId.toLowerCase().startsWith('${connName}_');
                }
              }
              if (!isMatch) return;

              // [친환경 24시간 윈도우]: 24시간 이내에 첫 실행/출석 신호가 있었던 모든 학급 유지
              final activeTimeVal = val['registeredAt'] ?? val['lastActive'];
              if (activeTimeVal != null) {
                int regMs = 0;
                if (activeTimeVal is num) {
                  regMs = activeTimeVal.toInt();
                } else {
                  regMs = DateTime.tryParse(activeTimeVal.toString())?.millisecondsSinceEpoch ?? 0;
                }
                if (regMs > 0) {
                  final diffHours = (nowMs - regMs).abs() / (1000 * 60 * 60);
                  if (diffHours > 24) return; // 24시간 지난 학급만 제외
                }
              }

              final grade = int.tryParse(val['grade']?.toString() ?? '') ?? 0;
              final cls = int.tryParse(val['classNum']?.toString() ?? val['class']?.toString() ?? '') ?? 0;
              final nickname = val['classNickname']?.toString() ?? (grade > 0 ? '$grade학년 $cls반' : docId);

              parsed.add({
                'docId': docId,
                'cafeteria': val['cafeteriaNum']?.toString() ?? val['cafeteria']?.toString() ?? '1',
                'grade': grade,
                'class': cls,
                'nickname': nickname,
                'isOnline': true,
                'lastActive': val['lastActive']?.toString() ?? '',
              });

              // 쪽지 발송 기록의 실시간 응답(O/X/TEXT) 확인
              final lastRespMsgId = val['lastResponseMsgId']?.toString() ?? '';
              final resp = (val['response']?.toString() ?? '').trim().toUpperCase();
              final respText = val['responseText']?.toString() ?? '';

              if (resp.isNotEmpty) {
                for (final hist in _sentHistory) {
                  final ids = (hist['docIds'] ?? '').split(',');
                  final histMsgId = hist['msgId']?.toString() ?? '';

                  // messageId가 일치하거나(최우선 격리), messageId 없는 레거시의 경우 docId 매칭
                  final isTargetMatch = histMsgId.isNotEmpty
                      ? (lastRespMsgId == histMsgId || ids.contains(docId))
                      : ids.contains(docId);

                  if (isTargetMatch && hist['response'] != resp) {
                    hist['response'] = resp;
                    hist['responseText'] = respText;
                    final clName = val['ackClassroom']?.toString() ?? nickname;
                    if (resp == 'O') {
                      showWebBrowserNotification(
                        title: '🟢 쪽지 응답 도착 [O]',
                        body: '$clName에서 "O (확인)" 응답을 보냈습니다.',
                      );
                    } else if (resp == 'X') {
                      showWebBrowserNotification(
                        title: '🔴 쪽지 응답 도착 [X]',
                        body: '$clName에서 "X (불가)" 응답을 보냈습니다.',
                      );
                    } else if (resp == 'TEXT') {
                      showWebBrowserNotification(
                        title: '💬 쪽지 답장 도착',
                        body: '$clName: "$respText"',
                      );
                    }
                  }
                }
              }

            });
          }
        }
      } catch (_) {}

      // 2. message_responses.json 조회하여 고유 msgId 별 응답 확정 (덮어쓰기 방지)
      try {
        final respUrl = 'https://jiwhosboardest-default-rtdb.firebaseio.com/message_responses.json';
        final respRes = await http.get(Uri.parse(respUrl)).timeout(const Duration(seconds: 3));
        if (respRes.statusCode == 200 && respRes.body != 'null') {
          final respData = json.decode(respRes.body);
          if (respData is Map) {
            respData.forEach((mId, rVal) {
              if (rVal is! Map) return;
              for (final hist in _sentHistory) {
                if (hist['msgId'] == mId.toString()) {
                  final rType = (rVal['response']?.toString() ?? '').toUpperCase();
                  final rText = rVal['responseText']?.toString() ?? '';
                  if (hist['response'] != rType || hist['responseText'] != rText) {
                    hist['response'] = rType;
                    hist['responseText'] = rText;
                  }
                }
              }
            });
          }
        }
      } catch (_) {}

      // 3. 교실에서 교사/교무실로 보낸 쪽지 (teacher_inbox) 확인
      try {
        final inboxUrl = 'https://jiwhosboardest-default-rtdb.firebaseio.com/teacher_inbox/$connName/messages.json';
        final inRes = await http.get(Uri.parse(inboxUrl)).timeout(const Duration(seconds: 3));
        if (inRes.statusCode == 200 && inRes.body != 'null') {
          final inData = json.decode(inRes.body);
          if (inData is Map) {
            inData.forEach((mId, mVal) {
              if (mVal is! Map) return;
              final msgId = mId.toString();
              if (!_handledInboxMsgIds.contains(msgId)) {
                _handledInboxMsgIds.add(msgId);
                final sClass = mVal['senderClass']?.toString() ?? '전자칠판';
                final sText = mVal['text']?.toString() ?? '';
                _receivedMessages.insert(0, {
                  'msgId': msgId,
                  'senderClass': sClass,
                  'senderDocId': mVal['senderDocId']?.toString() ?? '',
                  'text': sText,
                  'sentAt': mVal['sentAt']?.toString() ?? '',
                  'response': mVal['response']?.toString() ?? '',
                });
                showWebBrowserNotification(
                  title: '📩 교실 쪽지 수신 [$sClass]',
                  body: '$sClass: "$sText"',
                );
              }
            });
          }
        }
      } catch (_) {}

      // 데모 모드인데 실시간 온라인 기기가 아직 없으면 9개 데모 학급을 상시 노출하여 시연/쪽지 발송 보장
      final isDemoActive = AppConfig.isDemoMode || connName == 'demo';
      if (isDemoActive && parsed.isEmpty) {
        for (int g = 1; g <= 3; g++) {
          for (int c = 1; c <= 3; c++) {
            parsed.add({
              'docId': 'demo_1_${g}_$c',
              'cafeteria': '1',
              'grade': g,
              'class': c,
              'nickname': '$g학년 $c반 (데모)',
              'isOnline': true,
              'lastActive': DateTime.now().millisecondsSinceEpoch,
            });
          }
        }
      }

      // 동일 학급(2학년 1반 등) 중복 접속 시 최신 1개만 단일 병합 (중복 제거)
      final Map<String, Map<String, dynamic>> dedupMap = {};
      for (final c in parsed) {
        final key = '${c['grade']}-${c['class']}';
        if (!dedupMap.containsKey(key)) {
          dedupMap[key] = c;
        } else {
          final existingActive = dedupMap[key]!['lastActive']?.toString() ?? '';
          final newActive = c['lastActive']?.toString() ?? '';
          if (newActive.compareTo(existingActive) > 0) {
            dedupMap[key] = c;
          }
        }
      }

      final deduplicatedList = dedupMap.values.toList()
        ..sort((a, b) {
          if (a['grade'] != b['grade']) return (a['grade'] as int).compareTo(b['grade'] as int);
          return (a['class'] as int).compareTo(b['class'] as int);
        });

      if (mounted) {
        setState(() {
          _onlineClassrooms = deduplicatedList;
          final validDocIds = deduplicatedList.map((c) => c['docId'] as String).toSet();
          _selectedOnlineDocIds.removeWhere((id) => !validDocIds.contains(id));
          if (_selectAllOnline || _selectedOnlineDocIds.isEmpty) {
            _selectedOnlineDocIds.clear();
            _selectedOnlineDocIds.addAll(validDocIds);
          }
        });
      }
    } catch (_) {
    } finally {
      _isFetchingOnline = false;
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _statusMessage = '쪽지 내용을 입력해 주세요.';
        _statusIsError = true;
      });
      return;
    }

    final targetDocIds = _selectedOnlineDocIds.toList();
    if (targetDocIds.isEmpty) {
      setState(() {
        _statusMessage = '수신할 온라인 교실을 선택해 주세요.';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _isSending = true;
      _statusMessage = null;
    });

    final cloud = CloudDriveService.instance;
    final rawName = _settings?.selectedTeacherName.isNotEmpty == true
        ? _settings!.selectedTeacherName
        : (cloud.userName?.isNotEmpty == true ? cloud.userName! : '교사');
    final trimmed = rawName.trim();
    final senderName = trimmed.endsWith('선생님') || trimmed.endsWith('선생')
        ? trimmed
        : (trimmed.isNotEmpty ? '$trimmed 선생님' : '교사');

    final nowIso = DateTime.now().toIso8601String();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final msgId = 'msg_$nowMs';

    final sendFutures = targetDocIds.map((docId) async {
      bool sent = false;
      await Future.wait([
        // 1. RTDB 실시간 쪽지 전송 (0.05초 즉시 전달)
        () async {
          try {
            final rtdbUrl = 'https://jiwhosboardest-default-rtdb.firebaseio.com/eat_calls/$docId.json';
            final res = await http.patch(
              Uri.parse(rtdbUrl),
              headers: {"Content-Type": "application/json"},
              body: json.encode({
                'message': text,
                'messageId': msgId,
                'messageFrom': senderName,
                'messageSentAt': nowIso,
                'acknowledged': false,
              }),
            ).timeout(const Duration(seconds: 3));
            if (res.statusCode >= 200 && res.statusCode < 300) {
              sent = true;
            }
          } catch (_) {}
        }(),
        // 데모 모드일 경우 demo.json 공통 토픽에도 동시 발송하여 모든 데모 교실에 즉각 전달 보장
        if (_getSchoolConnName() == 'demo' || AppConfig.isDemoMode) () async {
          try {
            final demoAllUrl = 'https://jiwhosboardest-default-rtdb.firebaseio.com/eat_calls/demo.json';
            await http.patch(
              Uri.parse(demoAllUrl),
              headers: {"Content-Type": "application/json"},
              body: json.encode({
                'message': text,
                'messageId': msgId,
                'messageFrom': senderName,
                'messageSentAt': nowIso,
                'acknowledged': false,
              }),
            ).timeout(const Duration(seconds: 3));
          } catch (_) {}
        }(),
      ]);
      return sent;
    });

    final results = await Future.wait(sendFutures);
    final successCount = results.where((s) => s).length;

    if (mounted) {
      setState(() {
        _isSending = false;
        if (successCount > 0) {
          final targetNames = _onlineClassrooms
              .where((c) => _selectedOnlineDocIds.contains(c['docId']))
              .map((c) => c['nickname'] as String)
              .join(', ');
          final label = _selectAllOnline ? '온라인 ${successCount}개 교실' : targetNames;
          _statusMessage = '🎉 [$label] 전자칠판으로 쪽지가 전달되었습니다!';
          _statusIsError = false;
          _sentHistory.insert(0, {
            'msgId': msgId,
            'text': text,
            'time': '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
            'target': label,
            'docIds': _selectedOnlineDocIds.join(','),
            'response': '',
            'responseText': '',
          });
          _msgController.clear();
        } else {
          _statusMessage = '쪽지 전송에 실패했습니다. 네트워크 상태를 확인해주세요.';
          _statusIsError = true;
        }
      });
    }
  }

  Future<void> _replyToClassroomMessage(Map<String, dynamic> msgItem, String responseType, {String? customText}) async {
    final connName = _getSchoolConnName();
    final msgId = msgItem['msgId']?.toString() ?? '';
    final sDocId = msgItem['senderDocId']?.toString() ?? '';
    if (msgId.isEmpty) return;

    final nowIso = DateTime.now().toIso8601String();
    try {
      final replyUrl = 'https://jiwhosboardest-default-rtdb.firebaseio.com/teacher_inbox/$connName/messages/$msgId.json';
      await http.patch(
        Uri.parse(replyUrl),
        headers: {"Content-Type": "application/json"},
        body: json.encode({
          'response': responseType,
          'responseText': customText ?? '',
          'respondedAt': nowIso,
        }),
      );

      if (sDocId.isNotEmpty) {
        final cloud = CloudDriveService.instance;
        final teacherName = _settings?.selectedTeacherName.isNotEmpty == true
            ? _settings!.selectedTeacherName
            : (cloud.userName?.isNotEmpty == true ? cloud.userName! : '선생님');
        final clUrl = 'https://jiwhosboardest-default-rtdb.firebaseio.com/eat_calls/$sDocId.json';
        final replyMsgText = responseType == 'O'
            ? '🟢 [확인 (O)]'
            : (responseType == 'X' ? '🔴 [불가 (X)]' : '💬 $customText');
        await http.patch(
          Uri.parse(clUrl),
          headers: {"Content-Type": "application/json"},
          body: json.encode({
            'message': '선생님 답장: $replyMsgText',
            'messageFrom': teacherName,
            'messageSentAt': nowIso,
            'acknowledged': false,
          }),
        );
      }

      if (mounted) {
        setState(() {
          msgItem['response'] = responseType;
          msgItem['responseText'] = customText ?? '';
        });
      }
    } catch (_) {}
  }

  void _showTeacherReplyInputDialog(Map<String, dynamic> msgItem, double s) {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16 * s)),
        title: Text('교실로 답장 보내기', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 16 * s, fontWeight: FontWeight.bold)),
        content: Container(
          width: 380 * s,
          padding: EdgeInsets.symmetric(horizontal: 10 * s),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10 * s),
            border: Border.all(color: Colors.white24),
          ),
          child: TextField(
            controller: textCtrl,
            style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * s),
            decoration: InputDecoration(
              hintText: '답장 내용을 입력하세요...',
              hintStyle: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 13 * s),
              border: InputBorder.none,
            ),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 13 * s)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7F5AF0)),
            onPressed: () {
              final text = textCtrl.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);
              _replyToClassroomMessage(msgItem, 'TEXT', customText: text);
            },
            child: Text('전송', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13 * s, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0E17),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF7F5AF0))),
      );
    }

    final schoolName = _settings?.selectedSchool?.name ?? '학교';
    final teacherName = _settings?.selectedTeacherName.isNotEmpty == true
        ? _settings!.selectedTeacherName
        : '교사';

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () {
            if (widget.onBack != null) {
              widget.onBack!();
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Row(
          children: [
            const Icon(Icons.mark_email_unread_rounded, color: Color(0xFF00F5D4)),
            const SizedBox(width: 8),
            Text(
              '교내 긴급 쪽지 발송',
              style: GoogleFonts.notoSansKr(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16 * s,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00F5D4)),
            onPressed: _fetchOnlineClassrooms,
            tooltip: '온라인 교실 새로고침',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20 * s),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 800 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 상단 프로필 & 발신자 정보 바 ─────────────────
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 12 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A),
                    borderRadius: BorderRadius.circular(16 * s),
                    border: Border.all(color: const Color(0xFF242629)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8 * s),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7F5AF0).withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.school_rounded, color: Color(0xFF7F5AF0), size: 18),
                      ),
                      SizedBox(width: 10 * s),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$schoolName · $teacherName 선생님',
                              style: GoogleFonts.notoSansKr(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13 * s,
                              ),
                            ),
                            Text(
                              '연결 코드: ${_getSchoolConnName()}',
                              style: GoogleFonts.notoSansKr(
                                color: const Color(0xFF94A1B2),
                                fontSize: 11 * s,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16 * s),

                // ── 발송 대상 선택 (온라인 교실 전용) ───────────────────────────
                Container(
                  padding: EdgeInsets.all(16 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A),
                    borderRadius: BorderRadius.circular(16 * s),
                    border: Border.all(
                      color: _onlineClassrooms.isNotEmpty
                          ? const Color(0xFF00F5D4).withOpacity(0.4)
                          : const Color(0xFF242629),
                      width: _onlineClassrooms.isNotEmpty ? 1.2 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 8 * s,
                            height: 8 * s,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _onlineClassrooms.isNotEmpty
                                  ? const Color(0xFF00F5D4)
                                  : const Color(0xFF72757E),
                              boxShadow: _onlineClassrooms.isNotEmpty
                                  ? [
                                      BoxShadow(
                                        color: const Color(0xFF00F5D4).withOpacity(0.6),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      )
                                    ]
                                  : null,
                            ),
                          ),
                          SizedBox(width: 8 * s),
                          Text(
                            '🎯 수신 대상 (현재 접속 중인 온라인 교실: ${_onlineClassrooms.length}개)',
                            style: GoogleFonts.notoSansKr(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5 * s,
                            ),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: _fetchOnlineClassrooms,
                            borderRadius: BorderRadius.circular(8 * s),
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 4 * s),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.refresh_rounded,
                                    size: 14 * s,
                                    color: const Color(0xFF00F5D4),
                                  ),
                                  SizedBox(width: 4 * s),
                                  Text(
                                    '새로고침',
                                    style: TextStyle(
                                      color: const Color(0xFF00F5D4),
                                      fontSize: 11.5 * s,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12 * s),
                      if (_onlineClassrooms.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(vertical: 20 * s, horizontal: 14 * s),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F0E17),
                            borderRadius: BorderRadius.circular(12 * s),
                            border: Border.all(color: const Color(0xFF242629)),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.wifi_off_rounded, color: const Color(0xFF72757E), size: 30 * s),
                              SizedBox(height: 8 * s),
                              Text(
                                '현재 켜져 있는 전자칠판 교실이 없습니다.',
                                style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13 * s),
                              ),
                              SizedBox(height: 4 * s),
                              Text(
                                '교실에서 전자칠판 앱을 켜면 실시간으로 여기에 감지되어 목록에 나타납니다.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11.5 * s),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        Wrap(
                          spacing: 8 * s,
                          runSpacing: 8 * s,
                          children: [
                            // 전체 온라인 교실 선택 칩
                            ChoiceChip(
                              selected: _selectAllOnline,
                              selectedColor: const Color(0xFF7F5AF0),
                              backgroundColor: const Color(0xFF0F0E17),
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.campaign_rounded, size: 14, color: Colors.white),
                                  const SizedBox(width: 4),
                                  Text(
                                    '전체 온라인 교실 (${_onlineClassrooms.length}개)',
                                    style: TextStyle(
                                      color: _selectAllOnline ? Colors.white : Colors.white70,
                                      fontWeight: _selectAllOnline ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 12 * s,
                                    ),
                                  ),
                                ],
                              ),
                              onSelected: (val) {
                                setState(() {
                                  _selectAllOnline = true;
                                  _selectedOnlineDocIds.clear();
                                  _selectedOnlineDocIds.addAll(_onlineClassrooms.map((c) => c['docId'] as String));
                                });
                              },
                            ),
                            // 개별 온라인 교실 칩 목록
                            ..._onlineClassrooms.map((c) {
                              final docId = c['docId'] as String;
                              final isSel = !_selectAllOnline && _selectedOnlineDocIds.contains(docId);
                              final isHomeroom = (_settings?.selectedGrade == c['grade'] && _settings?.selectedClass == c['class']);

                              return ChoiceChip(
                                selected: isSel,
                                selectedColor: const Color(0xFF00F5D4),
                                backgroundColor: const Color(0xFF0F0E17),
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6 * s,
                                      height: 6 * s,
                                      margin: EdgeInsets.only(right: 4 * s),
                                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00F5D4)),
                                    ),
                                    Text(
                                      c['nickname'] as String,
                                      style: TextStyle(
                                        color: isSel ? Colors.black : Colors.white,
                                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 11.5 * s,
                                      ),
                                    ),
                                    if (isHomeroom) ...[
                                      SizedBox(width: 4 * s),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 4 * s, vertical: 1 * s),
                                        decoration: BoxDecoration(
                                          color: isSel ? Colors.black.withOpacity(0.2) : const Color(0xFF7F5AF0),
                                          borderRadius: BorderRadius.circular(4 * s),
                                        ),
                                        child: Text(
                                          '담임',
                                          style: TextStyle(
                                            color: isSel ? Colors.black : Colors.white,
                                            fontSize: 9 * s,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                onSelected: (val) {
                                  setState(() {
                                    _selectAllOnline = false;
                                    if (val) {
                                      _selectedOnlineDocIds.clear();
                                      _selectedOnlineDocIds.add(docId);
                                    } else {
                                      _selectedOnlineDocIds.remove(docId);
                                    }
                                  });
                                },
                              );
                            }),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 16 * s),

                // ── 빠른 상용구 칩 ────────────────────────────
                Wrap(
                  spacing: 8 * s,
                  runSpacing: 8 * s,
                  children: _quickPhrases.map((phrase) {
                    return ActionChip(
                      backgroundColor: const Color(0xFF242629),
                      label: Text(
                        phrase,
                        style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 11 * s),
                      ),
                      onPressed: () {
                        setState(() {
                          _msgController.text = phrase;
                        });
                      },
                    );
                  }).toList(),
                ),
                SizedBox(height: 12 * s),

                // ── 메시지 입력창 & 전송 버튼 ──────────────────
                Container(
                  padding: EdgeInsets.all(16 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A),
                    borderRadius: BorderRadius.circular(16 * s),
                    border: Border.all(color: const Color(0xFF242629)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _msgController,
                        maxLines: 4,
                        style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13 * s),
                        decoration: InputDecoration(
                          hintText: '전자칠판 화면에 팝업으로 띄울 쪽지나 공지 내용을 작성하세요...',
                          hintStyle: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12 * s),
                          filled: true,
                          fillColor: const Color(0xFF0F0E17),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12 * s),
                            borderSide: const BorderSide(color: Color(0xFF242629)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12 * s),
                            borderSide: const BorderSide(color: Color(0xFF7F5AF0), width: 1.5),
                          ),
                        ),
                      ),
                      SizedBox(height: 14 * s),
                      if (_statusMessage != null) ...[
                        Container(
                          padding: EdgeInsets.all(10 * s),
                          margin: EdgeInsets.only(bottom: 12 * s),
                          decoration: BoxDecoration(
                            color: _statusIsError ? const Color(0xFFEF4565).withOpacity(0.15) : const Color(0xFF2EC4B6).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10 * s),
                            border: Border.all(
                              color: _statusIsError ? const Color(0xFFEF4565) : const Color(0xFF2EC4B6),
                              width: 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _statusIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                                color: _statusIsError ? const Color(0xFFEF4565) : const Color(0xFF2EC4B6),
                                size: 16 * s,
                              ),
                              SizedBox(width: 8 * s),
                              Expanded(
                                child: Text(
                                  _statusMessage!,
                                  style: GoogleFonts.notoSansKr(
                                    color: _statusIsError ? const Color(0xFFEF4565) : const Color(0xFF2EC4B6),
                                    fontSize: 12 * s,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      SizedBox(
                        height: 46 * s,
                        child: ElevatedButton.icon(
                          onPressed: _isSending ? null : _sendMessage,
                          icon: _isSending
                              ? SizedBox(
                                  width: 18 * s,
                                  height: 18 * s,
                                  child: const CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.send_rounded, size: 18),
                          label: Text(
                            _isSending ? '전송 중...' : '온라인 교실로 쪽지 즉시 전송',
                            style: GoogleFonts.notoSansKr(
                              fontWeight: FontWeight.bold,
                              fontSize: 14 * s,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF7F5AF0),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12 * s),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 20 * s),

                // ── 교실에서 수신된 쪽지 바 ─────────────────────────
                if (_receivedMessages.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.mark_email_unread_rounded, color: Color(0xFF7F5AF0), size: 16),
                      SizedBox(width: 6 * s),
                      Text(
                        '교실에서 온 쪽지 (${_receivedMessages.length})',
                        style: GoogleFonts.notoSansKr(
                          color: const Color(0xFF7F5AF0),
                          fontSize: 13 * s,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8 * s),
                  ...List.generate(_receivedMessages.length, (idx) {
                    final item = _receivedMessages[idx];
                    final resp = (item['response'] ?? '').toString().toUpperCase();
                    final respText = item['responseText']?.toString() ?? '';

                    return Container(
                      margin: EdgeInsets.only(bottom: 8 * s),
                      padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 10 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B1B22),
                        borderRadius: BorderRadius.circular(12 * s),
                        border: Border.all(color: const Color(0xFF7F5AF0).withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 3 * s),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7F5AF0).withOpacity(0.25),
                              borderRadius: BorderRadius.circular(6 * s),
                            ),
                            child: Text(
                              item['senderClass'] ?? '교실',
                              style: GoogleFonts.notoSansKr(color: const Color(0xFF9E86F8), fontSize: 11 * s, fontWeight: FontWeight.bold),
                            ),
                          ),
                          SizedBox(width: 10 * s),
                          Expanded(
                            child: Text(
                              item['text'] ?? '',
                              style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13 * s, fontWeight: FontWeight.w500),
                            ),
                          ),
                          SizedBox(width: 8 * s),
                          if (resp.isEmpty) ...[
                            // 3종 답장 버튼 (X, 입력, O)
                            InkWell(
                              onTap: () => _replyToClassroomMessage(item, 'X'),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6 * s),
                                  border: Border.all(color: const Color(0xFFEF4444)),
                                ),
                                child: Text('🔴 X', style: TextStyle(color: const Color(0xFFEF4444), fontSize: 11 * s, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            SizedBox(width: 6 * s),
                            InkWell(
                              onTap: () => _showTeacherReplyInputDialog(item, s),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6 * s),
                                  border: Border.all(color: Colors.white30),
                                ),
                                child: Text('💬 답장', style: TextStyle(color: Colors.white, fontSize: 11 * s, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            SizedBox(width: 6 * s),
                            InkWell(
                              onTap: () => _replyToClassroomMessage(item, 'O'),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(6 * s),
                                  border: Border.all(color: const Color(0xFF10B981)),
                                ),
                                child: Text('🟢 O', style: TextStyle(color: const Color(0xFF10B981), fontSize: 11 * s, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 4 * s),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6 * s),
                              ),
                              child: Text(
                                resp == 'O'
                                    ? '🟢 O 회신 완료'
                                    : (resp == 'X' ? '🔴 X 회신 완료' : '💬 $respText'),
                                style: GoogleFonts.notoSansKr(
                                  color: resp == 'O'
                                      ? const Color(0xFF10B981)
                                      : (resp == 'X' ? const Color(0xFFEF4444) : const Color(0xFF9E86F8)),
                                  fontSize: 11 * s,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                  SizedBox(height: 16 * s),
                ],

                // ── 최근 발송 내역 바 ─────────────────────────
                if (_sentHistory.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.history_rounded, color: Color(0xFF94A1B2), size: 16),
                      SizedBox(width: 6 * s),
                      Text(
                        '최근 쪽지 발송 기록',
                        style: GoogleFonts.notoSansKr(
                          color: const Color(0xFF94A1B2),
                          fontSize: 12 * s,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8 * s),
                  ...List.generate(_sentHistory.length, (idx) {
                    final item = _sentHistory[idx];
                    return Container(
                      margin: EdgeInsets.only(bottom: 6 * s),
                      padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 10 * s),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16161A),
                        borderRadius: BorderRadius.circular(10 * s),
                        border: Border.all(color: const Color(0xFF242629)),
                      ),
                      child: Row(
                        children: [
                          // 1. 발송 대상 학급
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7F5AF0).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6 * s),
                            ),
                            child: Text(
                              item['target'] ?? '',
                              style: GoogleFonts.notoSansKr(color: const Color(0xFF7F5AF0), fontSize: 10 * s, fontWeight: FontWeight.bold),
                            ),
                          ),
                          SizedBox(width: 8 * s),
                          // 2. 응답 뱃지 (O는 초록, X는 빨강, TEXT는 보라/말풍선, 안읽으면 회색)
                          Builder(builder: (_) {
                            final resp = (item['response'] ?? '').toUpperCase();
                            final respText = item['responseText'] ?? '';
                            final isO = resp == 'O';
                            final isX = resp == 'X';
                            final isText = resp == 'TEXT';

                            Color badgeBg = Colors.white.withOpacity(0.08);
                            Color badgeFg = const Color(0xFF94A1B2);
                            String badgeText = '⚪ 안읽음';

                            if (isO) {
                              badgeBg = const Color(0xFF10B981).withOpacity(0.2);
                              badgeFg = const Color(0xFF10B981);
                              badgeText = '🟢 O (확인)';
                            } else if (isX) {
                              badgeBg = const Color(0xFFEF4444).withOpacity(0.2);
                              badgeFg = const Color(0xFFEF4444);
                              badgeText = '🔴 X (불가)';
                            } else if (isText) {
                              badgeBg = const Color(0xFF7F5AF0).withOpacity(0.2);
                              badgeFg = const Color(0xFF7F5AF0);
                              badgeText = respText.isNotEmpty ? '💬 $respText' : '💬 답장 완료';
                            }

                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: 6 * s, vertical: 2 * s),
                              decoration: BoxDecoration(
                                color: badgeBg,
                                borderRadius: BorderRadius.circular(6 * s),
                                border: Border.all(color: badgeFg.withOpacity(0.4), width: 0.8),
                              ),
                              child: Text(
                                badgeText,
                                style: TextStyle(color: badgeFg, fontSize: 10 * s, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }),
                          SizedBox(width: 8 * s),
                          Expanded(
                            child: Text(
                              item['text'] ?? '',
                              style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 11 * s),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            item['time'] ?? '',
                            style: GoogleFonts.outfit(color: const Color(0xFF94A1B2), fontSize: 10 * s),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

