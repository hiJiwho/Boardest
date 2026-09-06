import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import '../services/storage_service.dart';
import '../services/cloud_drive_service.dart';
import '../services/neis_service.dart';
import '../models/app_settings.dart';

/// Boardest 네이티브 실시간 급식 지도 & 반별 급식 호출 뷰어
class MealView extends StatefulWidget {
  final double scaleFactor;
  final VoidCallback? onBack;

  const MealView({super.key, required this.scaleFactor, this.onBack});

  @override
  State<MealView> createState() => _MealViewState();
}

class _MealViewState extends State<MealView> {
  static const String _apiKey = 'AIzaSyBMoJZHMBN4eYJtiZR2iGePcmIB7bg8wGo';

  AppSettings? _settings;
  bool _isLoading = true;
  String _selectedCafeteria = '1';
  bool _isCalling = false;
  String? _statusMessage;

  List<Map<String, dynamic>> _onlineClassrooms = [];
  Timer? _pollingTimer;

  List<String> _mealMenu = [];
  String _mealDateLabel = '';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final s = await StorageService().getSettings() ?? AppSettings();
    String caf = s.cafeteriaNum.replaceAll(RegExp(r'[^0-9]'), '');
    if (caf.isEmpty) caf = '1';

    if (mounted) {
      setState(() {
        _settings = s;
        _selectedCafeteria = caf;
        _isLoading = false;
      });
    }

    _fetchOnlineClassrooms();
    _loadMealMenu();
    _fetchOnlineClassrooms();
    _loadMealMenu();
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
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

  Future<void> _loadMealMenu() async {
    try {
      final now = DateTime.now();
      _mealDateLabel = '${now.month}월 ${now.day}일 급식 식단';
      final schoolName = _settings?.selectedSchool?.name ?? '양동중학교';
      final mealStr = await NeisService().fetchTodayMeal(schoolName, now);
      final dishes = mealStr.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (mounted && dishes.isNotEmpty) {
        setState(() {
          _mealMenu = dishes;
        });
      }
    } catch (_) {
      if (mounted && _mealMenu.isEmpty) {
        setState(() {
          _mealMenu = ['친환경 쌀밥', '쇠고기 미역국', '수제 돈까스 & 소스', '깍두기', '요구르트'];
        });
      }
    }
  }

  Future<void> _fetchOnlineClassrooms() async {
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
              'isCalled': c['called'] == true,
              'isOnline': isOnline,
              'lastActive': lastActiveStr,
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
            final isCalled = fields['called']?['booleanValue'] as bool? ?? false;
            final lastActiveStr = fields['lastActive']?['timestampValue'] as String? ?? fields['lastActive']?['stringValue'] as String? ?? '';
            var cafeteria = fields['cafeteriaNum']?['stringValue'] as String? ?? fields['cafeteriaNum']?['integerValue']?.toString() ?? '1';
            cafeteria = cafeteria.replaceAll(RegExp(r'[^0-9]'), '');
            if (cafeteria.isEmpty || cafeteria == '0') cafeteria = '1';

            final classNickname = fields['classNickname']?['stringValue'] ?? '';
            final place = fields['place']?['stringValue'] ?? '';

            // 1. 알파벳이 포함된 비정규 학급(Music1, LabA, 교수학습실, Special 등) 완전 제외!
            if (RegExp(r'[a-zA-Z]').hasMatch(docId.split('_').last) || 
                RegExp(r'[a-zA-Z]').hasMatch(classNickname) ||
                classNickname.contains('교수학습실') || 
                classNickname.contains('특별실') ||
                place.contains('교수학습실') ||
                place.contains('특별실')) {
              continue;
            }

            // 2. 순수 숫자 교실 ID 파싱: 105 -> 1학년 05반, 123 -> 1학년 23반
            int grade = 0;
            int cls = 0;
            final lastSegment = docId.split('_').last;
            final pureDigits = lastSegment.replaceAll(RegExp(r'[^\d]'), '');
            
            if (pureDigits.length >= 2 && RegExp(r'^\d+$').hasMatch(lastSegment)) {
              grade = int.tryParse(pureDigits.substring(0, 1)) ?? 0;
              cls = int.tryParse(pureDigits.substring(1)) ?? 0;
            } else {
              final gradeVal = fields['grade']?['integerValue'] ?? fields['grade']?['stringValue'] ?? '0';
              final classVal = fields['classNum']?['integerValue'] ?? fields['classNum']?['stringValue'] ?? '0';
              grade = int.tryParse(gradeVal.toString()) ?? 0;
              cls = int.tryParse(classVal.toString()) ?? 0;
            }

            // 정규 학급 검사 (grade > 0 && class > 0)
            if (grade <= 0 || cls <= 0) continue;
            final classFormatted = cls.toString().padLeft(2, '0');
            final nickname = '$grade학년 $classFormatted반';

            // 3. 실시간 온라인 기준: 지금 당장 활성(최근 2분 이내 하트비트)만 표시!
            bool isOnline = false;
            if (lastActiveStr.isNotEmpty) {
              try {
                final activeTime = DateTime.parse(lastActiveStr).toUtc();
                final diffSeconds = DateTime.now().toUtc().difference(activeTime).inSeconds.abs();
                isOnline = (diffSeconds <= 150); // 2.5분 이내 활성
              } catch (_) {}
            }
            if (!isOnline) continue;

            parsed.add({
              'docId': docId,
              'cafeteria': cafeteria,
              'grade': grade,
              'class': cls,
              'nickname': nickname,
              'isCalled': isCalled,
              'isOnline': isOnline,
              'lastActive': lastActiveStr,
            });
          }
        }
      }

      // 3. 동일 학급(2학년 8반 등) 중복 엔트리 단일 병합 (최신 활성 기준)
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
        });
      }
    } catch (_) {}
  }

  Future<void> _callClass(String docId, bool call) async {
    setState(() => _isCalling = true);
    try {
      const updateMask = 'updateMask.fieldPaths=called&updateMask.fieldPaths=lastCalledAt';
      final firestoreUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls/$docId?$updateMask&key=$_apiKey';
      final payload = {
        'fields': {
          'called': {'booleanValue': call},
          'lastCalledAt': {'stringValue': DateTime.now().toIso8601String()},
        }
      };

      await http.patch(
        Uri.parse(firestoreUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 4));

      // 2. RTDB 실시간 전송 (0.1초 즉시 전달, Firestore 읽기 0 소모)
      try {
        final rtdbUrl = 'https://jiwhosboardest-default-rtdb.firebaseio.com/eat_calls/$docId.json';
        await http.patch(
          Uri.parse(rtdbUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'called': call,
            'lastCalledAt': DateTime.now().toIso8601String(),
          }),
        ).timeout(const Duration(seconds: 4));
      } catch (_) {}

      await _fetchOnlineClassrooms();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(call ? '🔔 전자칠판으로 급식 호출 신호를 즉시 발송했습니다!' : '호출이 취소되었습니다.'),
            backgroundColor: call ? const Color(0xFFFF8906) : Colors.blueGrey,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('호출 실패: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isCalling = false);
    }
  }

  Future<void> _callAllInCafeteria() async {
    final targets = _onlineClassrooms.where((c) => c['cafeteria'] == _selectedCafeteria).toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 급식실에 접속된 학급이 없습니다.')),
      );
      return;
    }

    setState(() => _isCalling = true);
    int count = 0;
    final nowIso = DateTime.now().toIso8601String();
    for (final t in targets) {
      final docId = t['docId'] as String;
      try {
        const updateMask = 'updateMask.fieldPaths=called&updateMask.fieldPaths=lastCalledAt';
        final firestoreUrl = 'https://firestore.googleapis.com/v1/projects/jiwhosboardest/databases/(default)/documents/eat_calls/$docId?$updateMask&key=$_apiKey';
        await http.patch(
          Uri.parse(firestoreUrl),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'fields': {
              'called': {'booleanValue': true},
              'lastCalledAt': {'stringValue': nowIso},
            }
          }),
        );

        // RTDB 실시간 전송
        try {
          final rtdbUrl = 'https://jiwhosboardest-default-rtdb.firebaseio.com/eat_calls/$docId.json';
          await http.patch(
            Uri.parse(rtdbUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'called': true,
              'lastCalledAt': nowIso,
            }),
          ).timeout(const Duration(seconds: 4));
        } catch (_) {}
        count++;
      } catch (_) {}
    }

    await _fetchOnlineClassrooms();
    if (mounted) {
      setState(() => _isCalling = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📢 총 $count개 학급에 급식실 이동 호출 신호를 발송했습니다!'),
          backgroundColor: const Color(0xFFFF8906),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0E17),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFF8906))),
      );
    }

    final filtered = _selectedCafeteria == 'all' ? _onlineClassrooms : _onlineClassrooms.where((c) => c['cafeteria'] == _selectedCafeteria).toList();
    final schoolName = _settings?.selectedSchool?.name ?? '학교';
    final teacherName = _settings?.selectedTeacherName.isNotEmpty == true
        ? _settings!.selectedTeacherName
        : '급식지도교사';

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
            const Icon(Icons.restaurant_menu_rounded, color: Color(0xFFFF8906)),
            const SizedBox(width: 8),
            Text(
              'Boardest 실시간 급식 지도 & 반별 호출',
              style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16 * s),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFFFF8906)),
            onPressed: _fetchOnlineClassrooms,
            tooltip: '실시간 새로고침',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20 * s),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 860 * s),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. 급식실 선택 & 당번 정보 바
                Container(
                  padding: EdgeInsets.all(16 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A),
                    borderRadius: BorderRadius.circular(16 * s),
                    border: Border.all(color: const Color(0xFF242629)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.meeting_room_rounded, color: const Color(0xFFFF8906), size: 18 * s),
                          SizedBox(width: 8 * s),
                          Text(
                            '급식실 선택 (1~9급식실)',
                            style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13 * s),
                          ),
                          const Spacer(),
                          Text(
                            '$schoolName · $teacherName 선생님',
                            style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11 * s),
                          ),
                        ],
                      ),
                      SizedBox(height: 12 * s),
                      Wrap(
                        spacing: 8 * s,
                        runSpacing: 8 * s,
                        children: [
                          ChoiceChip(
                            selected: _selectedCafeteria == 'all',
                            selectedColor: const Color(0xFF00F5D4),
                            backgroundColor: const Color(0xFF0F0E17),
                            label: Text(
                              '전체 학급 (${_onlineClassrooms.length})',
                              style: TextStyle(
                                color: _selectedCafeteria == 'all' ? Colors.black : Colors.white,
                                fontWeight: _selectedCafeteria == 'all' ? FontWeight.bold : FontWeight.normal,
                                fontSize: 11.5 * s,
                              ),
                            ),
                            onSelected: (val) {
                              if (val) setState(() => _selectedCafeteria = 'all');
                            },
                          ),
                          ...List.generate(9, (idx) {
                            final numStr = '${idx + 1}';
                            final isSelected = _selectedCafeteria == numStr;
                            final count = _onlineClassrooms.where((c) => c['cafeteria'] == numStr).length;
                            return ChoiceChip(
                              selected: isSelected,
                              selectedColor: const Color(0xFFFF8906),
                              backgroundColor: const Color(0xFF0F0E17),
                              label: Text(
                                '$numStr급식실${count > 0 ? " ($count)" : ""}',
                                style: TextStyle(
                                  color: isSelected ? Colors.black : Colors.white,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 11.5 * s,
                                ),
                              ),
                              onSelected: (val) {
                                if (val) setState(() => _selectedCafeteria = numStr);
                              },
                            );
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16 * s),

                // 2. 실시간 온라인 교실 목록 & 개별 호출 버튼
                Container(
                  padding: EdgeInsets.all(18 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A),
                    borderRadius: BorderRadius.circular(16 * s),
                    border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10 * s,
                            height: 10 * s,
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00F5D4)),
                          ),
                          SizedBox(width: 8 * s),
                          Text(
                            '실시간 온라인 교실 (${_selectedCafeteria}급식실 전용: ${filtered.length}개 학급)',
                            style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14 * s),
                          ),
                          const Spacer(),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7F5AF0),
                              padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 8 * s),
                            ),
                            icon: const Icon(Icons.campaign_rounded, size: 16, color: Colors.white),
                            label: Text('전체 동시 호출', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12 * s)),
                            onPressed: _isCalling ? null : _callAllInCafeteria,
                          ),
                        ],
                      ),
                      SizedBox(height: 14 * s),
                      if (filtered.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 24 * s),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.signal_cellular_nodata_rounded, color: Colors.white30, size: 36 * s),
                                SizedBox(height: 8 * s),
                                Text(
                                  '현재 접속된 전자칠판이 없습니다.\n(교실 칠판 앱이 켜지면 자동으로 감지됩니다)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white54, fontSize: 12 * s, height: 1.5),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final c = filtered[i];
                            final isCalled = c['isCalled'] as bool;
                            final nickname = c['nickname'] as String;
                            final docId = c['docId'] as String;

                            return Container(
                              margin: EdgeInsets.only(bottom: 8 * s),
                              padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 10 * s),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F0E17),
                                borderRadius: BorderRadius.circular(12 * s),
                                border: Border.all(
                                  color: isCalled ? const Color(0xFFFF8906).withOpacity(0.8) : const Color(0xFF242629),
                                  width: isCalled ? 1.5 : 1.0,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8 * s,
                                    height: 8 * s,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isCalled ? const Color(0xFFFF8906) : const Color(0xFF00F5D4),
                                    ),
                                  ),
                                  SizedBox(width: 10 * s),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nickname,
                                          style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5 * s),
                                        ),
                                        Text(
                                          isCalled ? '🔔 급식실 이동 호출 팝업 표시 중' : '🟢 온라인 대기 중',
                                          style: TextStyle(
                                            color: isCalled ? const Color(0xFFFF8906) : const Color(0xFF00F5D4),
                                            fontSize: 11 * s,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isCalled)
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white70,
                                        side: const BorderSide(color: Colors.white30),
                                        padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 6 * s),
                                      ),
                                      onPressed: _isCalling ? null : () => _callClass(docId, false),
                                      child: Text('호출 취소', style: TextStyle(fontSize: 11.5 * s)),
                                    )
                                  else
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFFF8906),
                                        foregroundColor: Colors.black,
                                        padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 8 * s),
                                      ),
                                      icon: const Icon(Icons.notifications_active_rounded, size: 15, color: Colors.black),
                                      label: Text('급식 호출', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12 * s)),
                                      onPressed: _isCalling ? null : () => _callClass(docId, true),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                SizedBox(height: 16 * s),

                // 3. 오늘의 급식 식단 카드
                Container(
                  padding: EdgeInsets.all(18 * s),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A),
                    borderRadius: BorderRadius.circular(16 * s),
                    border: Border.all(color: const Color(0xFFFF8906).withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.restaurant_rounded, color: Color(0xFFFF8906), size: 20),
                          SizedBox(width: 8 * s),
                          Text(
                            '$_mealDateLabel ($schoolName)',
                            style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14 * s),
                          ),
                        ],
                      ),
                      SizedBox(height: 10 * s),
                      Wrap(
                        spacing: 8 * s,
                        runSpacing: 6 * s,
                        children: _mealMenu.map((m) {
                          return Chip(
                            backgroundColor: const Color(0xFF0F0E17),
                            side: BorderSide(color: Colors.white.withOpacity(0.1)),
                            label: Text(m, style: TextStyle(color: Colors.white, fontSize: 11.5 * s)),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
