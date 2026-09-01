import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../services/storage_service.dart';
import '../services/cloud_drive_service.dart';
import '../models/app_settings.dart';

/// Boardest 학급 쪽지 및 긴급 알림/공지 발송 네이티브 뷰어 (온라인 교실 전용)
class MessageView extends StatefulWidget {
  final double scaleFactor;
  final VoidCallback? onBack;

  const MessageView({super.key, required this.scaleFactor, this.onBack});

  @override
  State<MessageView> createState() => _MessageViewState();
}

class _MessageViewState extends State<MessageView> {
  static const String _apiKey = 'AIzaSyBMoJZHMBN4eYJtiZR2iGePcmIB7bg8wGo';

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

      // 1. Cloudflare Worker 빠른 조회 (429 없음)
      try {
        final workerUrl = 'https://boardest-cloud-token.jiwho.workers.dev/api/classrooms?schoolCode=$connName';
        final workerRes = await http.get(Uri.parse(workerUrl)).timeout(const Duration(seconds: 3));
        if (workerRes.statusCode == 200) {
          final wData = json.decode(workerRes.body);
          final wList = wData['classrooms'] as List? ?? [];
          for (final c in wList) {
            final docId = c['docId']?.toString() ?? '';
            if (docId.isEmpty) continue;
            final lastActiveStr = c['lastActive']?.toString() ?? '';
            bool isOnline = true;
            if (lastActiveStr.isNotEmpty) {
              try {
                final activeTime = DateTime.parse(lastActiveStr).toUtc();
                final diffMin = DateTime.now().toUtc().difference(activeTime).inMinutes.abs();
                isOnline = (diffMin <= 120);
              } catch (_) {}
            }
            final grade = int.tryParse(c['grade']?.toString() ?? '') ?? 0;
            final cls = int.tryParse(c['class']?.toString() ?? '') ?? 0;
            final nickname = c['nickname']?.toString() ?? (grade > 0 ? '$grade학년 $cls반' : docId);
            parsed.add({
              'docId': docId,
              'cafeteria': c['cafeteria']?.toString() ?? '1',
              'grade': grade,
              'class': cls,
              'nickname': nickname,
              'isOnline': isOnline,
            });
          }
        }
      } catch (_) {}

      // 2. Firestore fallback if worker list is empty
      if (parsed.isEmpty) {
        final url = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls?pageSize=100&key=$_apiKey';
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = json.decode(res.body);
          final docs = data['documents'] as List? ?? [];

          final schoolCode = _settings?.selectedSchool?.code?.toString() ?? '';
          final schoolId = _settings?.schoolId.trim() ?? '';
          final schoolName = _settings?.selectedSchool?.name ?? '';

          for (final doc in docs) {
            final name = doc['name'] as String? ?? '';
            final docId = name.split('/').last;
            final fields = doc['fields'] as Map<String, dynamic>? ?? {};

            final docSchoolCode = fields['schoolCode']?['stringValue'] ?? '';
            final docSchoolName = fields['schoolName']?['stringValue'] ?? '';

            bool isMatch = docId.toLowerCase().startsWith(connName);
            if (!isMatch && schoolCode.isNotEmpty) {
              isMatch = docId.toLowerCase().startsWith(schoolCode.toLowerCase()) || docSchoolCode == schoolCode;
            }
            if (!isMatch && schoolId.isNotEmpty) {
              isMatch = docId.toLowerCase().startsWith(schoolId.toLowerCase());
            }
            if (!isMatch && schoolName.isNotEmpty && docSchoolName.isNotEmpty) {
              isMatch = docSchoolName.contains(schoolName) || schoolName.contains(docSchoolName);
            }
            if (!isMatch && docs.length <= 3) {
              isMatch = true;
            }
            if (!isMatch) continue;
            final lastActiveStr = fields['lastActive']?['timestampValue'] as String? ?? fields['lastActive']?['stringValue'] as String? ?? '';
            final cafeteria = fields['cafeteriaNum']?['stringValue'] as String? ?? '1';

            final gradeVal = fields['grade']?['integerValue'] ?? fields['grade']?['stringValue'] ?? '0';
            final classVal = fields['classNum']?['integerValue'] ?? fields['classNum']?['stringValue'] ?? '0';
            final grade = int.tryParse(gradeVal.toString()) ?? 0;
            final cls = int.tryParse(classVal.toString()) ?? 0;
            final nickname = fields['classNickname']?['stringValue'] ?? (grade > 0 ? '$grade학년 $cls반' : docId);

            bool isOnline = true;
            if (lastActiveStr.isNotEmpty) {
              try {
                final activeTime = DateTime.parse(lastActiveStr).toUtc();
                final diffMin = DateTime.now().toUtc().difference(activeTime).inMinutes.abs();
                isOnline = (diffMin <= 120);
              } catch (_) {}
            }

            parsed.add({
              'docId': docId,
              'cafeteria': cafeteria,
              'grade': grade,
              'class': cls,
              'nickname': nickname,
              'isOnline': isOnline,
            });
          }
        }
      }

      parsed.sort((a, b) {
        if (a['grade'] != b['grade']) return (a['grade'] as int).compareTo(b['grade'] as int);
        return (a['class'] as int).compareTo(b['class'] as int);
      });

      if (mounted) {
        setState(() {
          _onlineClassrooms = parsed;
          if (_selectAllOnline || _selectedOnlineDocIds.isEmpty) {
            _selectedOnlineDocIds.clear();
            _selectedOnlineDocIds.addAll(parsed.map((c) => c['docId'] as String));
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
    int successCount = 0;

    for (final docId in targetDocIds) {
      try {
        const updateMask = 'updateMask.fieldPaths=message&updateMask.fieldPaths=messageFrom&updateMask.fieldPaths=messageSentAt';
        final firestoreUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls/$docId?$updateMask&key=$_apiKey';

        final payload = {
          "fields": {
            "message": {"stringValue": text},
            "messageFrom": {"stringValue": senderName},
            "messageSentAt": {"stringValue": nowIso},
          }
        };

        final res = await http.patch(
          Uri.parse(firestoreUrl),
          headers: {"Content-Type": "application/json"},
          body: json.encode(payload),
        ).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          successCount++;
        } else {
          final createUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls?documentId=$docId&key=$_apiKey';
          await http.post(
            Uri.parse(createUrl),
            headers: {"Content-Type": "application/json"},
            body: json.encode(payload),
          ).timeout(const Duration(seconds: 4));
          successCount++;
        }

        // 2. Worker FCM Push 동시 발송 (High-Priority Push)
        try {
          await http.post(
            Uri.parse('https://boardest-cloud-token.jiwho.workers.dev/api/push/send'),
            headers: {"Content-Type": "application/json"},
            body: json.encode({
              'topic': 'eat_call_${docId.toLowerCase()}',
              'title': '📩 $senderName 쪽지',
              'body': text,
              'data': {
                'type': 'message',
                'docId': docId,
                'message': text,
                'messageFrom': senderName,
                'messageSentAt': nowIso,
              }
            }),
          ).timeout(const Duration(seconds: 3));
        } catch (_) {}
      } catch (_) {}
    }

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
            'text': text,
            'time': '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}',
            'target': label,
          });
          _msgController.clear();
        } else {
          _statusMessage = '쪽지 전송에 실패했습니다. 네트워크 상태를 확인해주세요.';
          _statusIsError = true;
        }
      });
    }
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
                          SizedBox(width: 10 * s),
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

