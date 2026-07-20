import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import '../models/lesson.dart';
import '../models/app_settings.dart';
import '../services/storage_service.dart';
import '../services/comcigan_service.dart';

/// Boardest Pro 교안 매핑 다이얼로그 (노트북 팝업)
/// 폴더 우클릭 → "Boardest Pro로 교안 매핑" 선택 시 표시됩니다.
/// - 가로 확장형 분할 구조 (너비 840)
/// - 좌측: 교사 본인 수업용 매핑
/// - 우측: 담임 학급용 매핑
class LiteMapDialog extends StatefulWidget {
  final String folderPath;

  const LiteMapDialog({super.key, required this.folderPath});

  @override
  State<LiteMapDialog> createState() => _LiteMapDialogState();
}

class _LiteMapDialogState extends State<LiteMapDialog> {
  final StorageService _storage = StorageService();
  final ComciganService _comcigan = ComciganService();

  AppSettings? _settings;
  TimetableResult? _timetable;
  bool _loading = true;
  String? _error;

  // 좌측 (교사 수업용) 선택 상태
  int _teacherGrade = 1;
  int _teacherClass = 1;
  int _teacherPeriod = 1;

  // 우측 (본인 반용) 선택 상태
  int _homeroomPeriod = 1;

  bool _saving = false;
  String? _successMessage;
  Timer? _periodTimer;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _dialogBg => _isDark ? const Color(0xFF16161A) : Colors.white;
  Color get _borderColor => _isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08);
  Color get _textColor => _isDark ? Colors.white : Colors.black87;
  Color get _textColor54 => _isDark ? Colors.white54 : Colors.black54;
  Color get _textColor38 => _isDark ? Colors.white30 : Colors.black38;
  Color get _dropdownColor => _isDark ? const Color(0xFF1E1E24) : Colors.white;
  Color get _textFillColor => _isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02);

  @override
  void initState() {
    super.initState();
    _init();
    _periodTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _periodTimer?.cancel();
    super.dispose();
  }

  String _getPeriodInfo() {
    final now = DateTime.now();
    final timeVal = now.hour * 60 + now.minute;

    const defaults = [
      {'start': 540, 'end': 585, 'name': '1교시'},
      {'start': 585, 'end': 595, 'name': '1교시 쉬는시간'},
      {'start': 595, 'end': 640, 'name': '2교시'},
      {'start': 640, 'end': 650, 'name': '2교시 쉬는시간'},
      {'start': 650, 'end': 695, 'name': '3교시'},
      {'start': 695, 'end': 705, 'name': '3교시 쉬는시간'},
      {'start': 705, 'end': 750, 'name': '4교시'},
      {'start': 750, 'end': 800, 'name': '점심시간'},
      {'start': 800, 'end': 845, 'name': '5교시'},
      {'start': 845, 'end': 855, 'name': '5교시 쉬는시간'},
      {'start': 855, 'end': 900, 'name': '6교시'},
      {'start': 900, 'end': 910, 'name': '6교시 쉬는시간'},
      {'start': 910, 'end': 955, 'name': '7교시'},
      {'start': 955, 'end': 1005, 'name': '7교시 쉬는시간'},
      {'start': 1005, 'end': 1050, 'name': '8교시'},
    ];

    for (final item in defaults) {
      if (timeVal >= (item['start'] as int) && timeVal < (item['end'] as int)) {
        return item['name'] as String;
      }
    }
    return '수업 시간 외';
  }

  Future<void> _init() async {
    try {
      _settings = await _storage.getSettings();
      if (_settings?.selectedSchool != null) {
        final raw = await _comcigan.fetchTimetableRaw(_settings!.selectedSchool!.code);
        _timetable = _comcigan.parseTimetable(raw);
      }
      
      if (mounted) {
        setState(() {
          _teacherGrade = _settings?.selectedGrade ?? 1;
          _teacherClass = _settings?.selectedClass ?? 1;
          _loading = false;
          _updateTeacherMappingDefaultsForPeriod(_teacherPeriod);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '시간표 데이터를 가져오지 못했습니다.';
          _loading = false;
        });
      }
    }
  }

  // 교사의 특정 교시 선택 시, 해당 교시에 실제로 들어가는 학급으로 자동 세팅
  void _updateTeacherMappingDefaultsForPeriod(int period) {
    if (_timetable == null || _settings == null) return;
    final today = DateTime.now().weekday;
    final displayDay = (today >= 1 && today <= 5) ? today : 1;

    final teacherName = _settings!.selectedTeacher.replaceAll('*', '').trim().toUpperCase();
    if (teacherName.isEmpty) return;

    for (final lesson in _timetable!.lessons) {
      if (lesson.weekday == displayDay && lesson.classTime == period) {
        final lessonTeacher = lesson.teacher.replaceAll('*', '').trim().toUpperCase();
        if (lessonTeacher == teacherName) {
          setState(() {
            _teacherGrade = lesson.grade;
            _teacherClass = lesson.classNum;
          });
          break;
        }
      }
    }
  }

  String? _findUsbRoot() {
    final path = widget.folderPath;
    final drive = path.length >= 3 ? path.substring(0, 3) : null;
    return drive;
  }

  Future<void> _saveMapping({
    required bool isHomeroom,
    required int grade,
    required int classNum,
    required int period,
  }) async {
    final usbRoot = _findUsbRoot();
    if (usbRoot == null) {
      setState(() => _error = 'USB 루트를 인식하지 못했습니다.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final jsonPath = '${usbRoot}BoardestUSB.json';
      final jsonFile = File(jsonPath);

      Map<String, dynamic> config = {};
      if (jsonFile.existsSync()) {
        try {
          if (Platform.isWindows) {
            await Process.run('cmd', ['/c', 'attrib', '-h', '"$jsonPath"']);
          }
          config = jsonDecode(jsonFile.readAsStringSync()) as Map<String, dynamic>;
        } catch (_) {}
      }

      config['type'] ??= 'Lite';
      config['version'] ??= 1;

      // 1. mappings 리스트 업데이트 (교시 기준 중복 제거)
      final mappings = (config['mappings'] as List<dynamic>?) ?? [];
      mappings.removeWhere((m) => m['period'] == period && m['grade'] == grade && m['class'] == classNum);
      
      final folderName = widget.folderPath.split(Platform.pathSeparator).last;
      
      mappings.add({
        'grade': grade,
        'class': classNum,
        'folder': folderName,
        'fullPath': widget.folderPath,
        'period': period,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      config['mappings'] = mappings;

      // 2. lite_settings 맵 업데이트 (전자칠판 자동 로딩 호환용)
      final liteSettings = (config['lite_settings'] as Map<String, dynamic>?) ?? {};
      final classKey = '$grade학년 ${classNum}반';
      liteSettings[classKey] = folderName;
      config['lite_settings'] = liteSettings;

      config['updatedAt'] = DateTime.now().toIso8601String();

      jsonFile.writeAsStringSync(jsonEncode(config));

      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'attrib', '+h', '"$jsonPath"']);
      }

      if (mounted) {
        setState(() {
          _saving = false;
          _successMessage = isHomeroom
              ? '✅ [담임 반] ${period}교시 → $classKey 매핑 완료!'
              : '✅ [교사 수업] ${period}교시 → $classKey 매핑 완료!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '저장 실패: $e';
        });
      }
    }
  }

  bool _isHomeroomTeacher() {
    if (_timetable == null || _settings == null) return false;
    final homeroomMap = _timetable!.homeroomTeachers[_settings!.selectedGrade];
    if (homeroomMap == null) return false;
    final homeroomTeacher = homeroomMap[_settings!.selectedClass];
    if (homeroomTeacher == null) return false;
    
    final selectedTeacherSanitized = _settings!.selectedTeacher.replaceAll('*', '').trim().toUpperCase();
    final homeroomTeacherSanitized = homeroomTeacher.replaceAll('*', '').trim().toUpperCase();
    
    return selectedTeacherSanitized.isNotEmpty && selectedTeacherSanitized == homeroomTeacherSanitized;
  }

  List<int> _getMaxClass(int grade) {
    if (_timetable == null) return List.generate(10, (i) => i + 1);
    final count = _timetable!.classCounts[grade] ?? 0;
    if (count == 0) return List.generate(10, (i) => i + 1);
    return List.generate(count, (i) => i + 1);
  }

  @override
  Widget build(BuildContext context) {
    final folderName = widget.folderPath.split(Platform.pathSeparator).last;
    final isHomeroom = _isHomeroomTeacher();
    final hasHomeroom = _settings != null && _settings!.isSetupComplete;
    final homeroomClassLabel = hasHomeroom ? '${_settings!.selectedGrade}학년 ${_settings!.selectedClass}반' : '설정 없음';

    final dialogWidth = isHomeroom ? 840.0 : 420.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: dialogWidth,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _dialogBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: _borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7F5AF0).withOpacity(0.12),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF7F5AF0)))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 헤더 영역
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7F5AF0).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.laptop_chromebook_rounded, color: Color(0xFF7F5AF0), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Boardest Pro 교안 매핑 (노트북)',
                              style: GoogleFonts.notoSansKr(
                                color: _textColor,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '매핑할 폴더: 📁 $folderName',
                                    style: GoogleFonts.outfit(color: const Color(0xFF7F5AF0), fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00F5D4).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.2)),
                                  ),
                                  child: Text(
                                    '⏰ 현재 시간: ${_getPeriodInfo()}',
                                    style: GoogleFonts.notoSansKr(
                                      color: const Color(0xFF00F5D4),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white38),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 에러 및 성공 피드백 알림
                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4565).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_error!, style: GoogleFonts.notoSansKr(color: const Color(0xFFEF4565), fontSize: 12)),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (_successMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2CB67D).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_successMessage!, style: GoogleFonts.notoSansKr(color: const Color(0xFF2CB67D), fontSize: 12)),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 좌우 분할 콘텐츠 (담임교사일 때만 양쪽 노출, 비담임일 때는 교사용만 노출)
                  if (isHomeroom)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildTeacherColumn()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildHomeroomColumn(homeroomClassLabel, hasHomeroom)),
                      ],
                    )
                  else
                    _buildTeacherColumn(),
                ],
              ),
      ),
    );
  }

  Widget _buildTeacherColumn() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_ind_rounded, color: Color(0xFF2EC4B6), size: 18),
              const SizedBox(width: 8),
              Text(
                '교사용 (본인 수업 매핑)',
                style: GoogleFonts.notoSansKr(
                  color: _textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _buildLabel('1. 교시 선택'),
          const SizedBox(height: 6),
          _buildDropdown<int>(
            value: _teacherPeriod,
            items: List.generate(8, (i) => i + 1),
            labelBuilder: (p) => '$p교시',
            onChanged: (v) {
              setState(() => _teacherPeriod = v!);
              _updateTeacherMappingDefaultsForPeriod(v!);
            },
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('2. 학년 선택'),
                    const SizedBox(height: 6),
                    _buildDropdown<int>(
                      value: _teacherGrade,
                      items: [1, 2, 3],
                      labelBuilder: (g) => '$g학년',
                      onChanged: (v) {
                        setState(() {
                          _teacherGrade = v!;
                          _teacherClass = 1;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLabel('3. 반 선택'),
                    const SizedBox(height: 6),
                    _buildDropdown<int>(
                      value: _teacherClass,
                      items: _getMaxClass(_teacherGrade),
                      labelBuilder: (c) => '$c반',
                      onChanged: (v) => setState(() => _teacherClass = v!),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving
                  ? null
                  : () => _saveMapping(
                        isHomeroom: false,
                        grade: _teacherGrade,
                        classNum: _teacherClass,
                        period: _teacherPeriod,
                      ),
              icon: const Icon(Icons.save_rounded, size: 16),
              label: Text('교사 수업 매핑 저장', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2EC4B6),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeroomColumn(String homeroomClassLabel, bool hasHomeroom) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.home_work_rounded, color: Color(0xFF7F5AF0), size: 18),
              const SizedBox(width: 8),
              Text(
                '본인 반용 (담임 학급 매핑)',
                style: GoogleFonts.notoSansKr(
                  color: _textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          _buildLabel('1. 매핑 학급 (고정)'),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: _textFillColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _borderColor),
            ),
            child: Text(
              homeroomClassLabel,
              style: GoogleFonts.notoSansKr(
                color: const Color(0xFF7F5AF0),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 12),

          _buildLabel('2. 교시 선택'),
          const SizedBox(height: 6),
          _buildDropdown<int>(
            value: _homeroomPeriod,
            items: List.generate(8, (i) => i + 1),
            labelBuilder: (p) => '$p교시',
            onChanged: (v) => setState(() => _homeroomPeriod = v!),
          ),
          const SizedBox(height: 48),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_saving || !hasHomeroom)
                  ? null
                  : () => _saveMapping(
                        isHomeroom: true,
                        grade: _settings!.selectedGrade,
                        classNum: _settings!.selectedClass,
                        period: _homeroomPeriod,
                      ),
              icon: const Icon(Icons.save_rounded, size: 16),
              label: Text('담임 학급 매핑 저장', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7F5AF0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.notoSansKr(color: _textColor54, fontSize: 12, fontWeight: FontWeight.w600),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) labelBuilder,
    required void Function(T?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: _textFillColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: _dropdownColor,
          style: GoogleFonts.notoSansKr(color: _textColor, fontSize: 13),
          iconEnabledColor: _textColor38,
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(labelBuilder(item)),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
