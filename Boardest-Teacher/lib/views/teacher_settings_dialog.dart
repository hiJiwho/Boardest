import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/app_settings.dart';
import '../models/school.dart';
import '../services/storage_service.dart';
import '../services/comcigan_service.dart';
import 'google_login_webview.dart';

/// Boardest Teacher 전역 설정 변경 다이얼로그 (학교, 학년, 반 설정)
class TeacherSettingsDialog extends StatefulWidget {
  final double scaleFactor;
  const TeacherSettingsDialog({super.key, required this.scaleFactor});

  @override
  State<TeacherSettingsDialog> createState() => _TeacherSettingsDialogState();
}

class _TeacherSettingsDialogState extends State<TeacherSettingsDialog> {
  final StorageService _storage = StorageService();
  final ComciganService _comcigan = ComciganService();

  AppSettings? _settings;
  bool _loading = true;
  String? _error;

  // 선택 값들
  School? _selectedSchool;
  int _selectedGrade = 1;
  int _selectedClass = 1;
  List<String> _teachers = [];
  String _selectedTeacher = '';
  bool _loadingTeachers = false;
  bool _homeroomMatched = false;
  String _themeMode = 'system';
  String _themeColor = 'system';
  String _windowFrameStyle = 'mac';

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _dialogBg => _isDark ? const Color(0xFF16161A) : Colors.white;
  Color get _borderColor => _isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.08);
  Color get _borderColorLight => _isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.06);
  Color get _textColor => _isDark ? Colors.white : Colors.black87;
  Color get _textColor54 => _isDark ? Colors.white54 : Colors.black54;
  Color get _textColor38 => _isDark ? Colors.white30 : Colors.black38;
  Color get _textColor24 => _isDark ? Colors.white24 : Colors.black26;
  Color get _dropdownColor => _isDark ? const Color(0xFF1E1E24) : Colors.white;
  Color get _textFillColor => _isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02);

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _teacherController = TextEditingController();
  List<School> _searchResults = [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _teacherController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final s = await _storage.getSettings() ?? AppSettings();
      List<String> teachersList = [];
      if (s.selectedSchool != null) {
        setState(() => _loadingTeachers = true);
        teachersList = await _comcigan.getTeachers(s.selectedSchool!.code);
      }
      setState(() {
        _settings = s;
        _selectedSchool = s.selectedSchool;
        _selectedGrade = s.selectedGrade;
        _selectedClass = s.selectedClass;
        _teachers = teachersList;
        _selectedTeacher = s.selectedTeacher;
        _teacherController.text = s.selectedTeacher;
        _themeMode = s.themeMode;
        _themeColor = s.themeColor;
        _windowFrameStyle = s.windowFrameStyle;
        _loading = false;
        _loadingTeachers = false;
      });
      if (s.selectedTeacher.isNotEmpty) {
        await _autoDetectHomeroomClass(s.selectedTeacher);
      }
    } catch (e) {
      setState(() {
        _error = '설정을 불러오지 못했습니다: $e';
        _loading = false;
        _loadingTeachers = false;
      });
    }
  }

  Future<void> _searchSchool(String keyword) async {
    if (keyword.trim().isEmpty) return;
    setState(() => _searching = true);
    try {
      final results = await _comcigan.searchSchool(keyword);
      setState(() {
        _searchResults = results;
        _searching = false;
      });
    } catch (e) {
      setState(() {
        _error = '학교 검색 실패: $e';
        _searching = false;
      });
    }
  }

  Future<void> _loadSchoolTeachers(School school) async {
    setState(() {
      _selectedSchool = school;
      _searchResults.clear();
      _searchController.clear();
      _loadingTeachers = true;
      _teachers.clear();
      _selectedTeacher = '';
      _teacherController.clear();
      _homeroomMatched = false;
    });
    try {
      final list = await _comcigan.getTeachers(school.code);
      setState(() {
        _teachers = list;
        if (list.isNotEmpty) {
          _selectedTeacher = list.first;
          _teacherController.text = list.first;
        }
        _loadingTeachers = false;
      });
      if (list.isNotEmpty) {
        await _autoDetectHomeroomClass(list.first);
      }
    } catch (e) {
      setState(() {
        _error = '교사 목록 로드 실패: $e';
        _loadingTeachers = false;
      });
    }
  }

  Future<void> _autoDetectHomeroomClass(String teacherName) async {
    if (_selectedSchool == null) return;
    try {
      final raw = await _comcigan.fetchTimetableRaw(_selectedSchool!.code);
      final result = _comcigan.parseTimetable(raw);
      
      final teacherSanitized = teacherName.replaceAll('*', '').trim().toUpperCase();
      if (teacherSanitized.isEmpty) return;

      int? matchedGrade;
      int? matchedClass;

      for (final gradeEntry in result.homeroomTeachers.entries) {
        final grade = gradeEntry.key;
        for (final classEntry in gradeEntry.value.entries) {
          final cls = classEntry.key;
          final homeroomTeacher = classEntry.value.replaceAll('*', '').trim().toUpperCase();
          if (homeroomTeacher == teacherSanitized) {
            matchedGrade = grade;
            matchedClass = cls;
            break;
          }
        }
        if (matchedGrade != null) break;
      }

      if (matchedGrade != null && matchedClass != null) {
        setState(() {
          _selectedGrade = matchedGrade!;
          _selectedClass = matchedClass!;
          _homeroomMatched = true;
        });
      } else {
        setState(() {
          _homeroomMatched = false;
        });
      }
    } catch (e) {
      debugPrint('Error auto detecting homeroom class: $e');
    }
  }

  Future<void> _saveSettings() async {
    if (_settings == null) return;
    setState(() => _loading = true);
    try {
      final updated = _settings!.copyWith(
        selectedSchool: _selectedSchool,
        selectedGrade: _selectedGrade,
        selectedClass: _selectedClass,
        selectedTeacher: _selectedTeacher,
        themeMode: _themeMode,
        themeColor: _themeColor,
        windowFrameStyle: _windowFrameStyle,
        isSetupComplete: true,
      );

      await _storage.saveSettings(updated);
      if (mounted) {
        Navigator.of(context).pop(true); // 성공 리턴
      }
    } catch (e) {
      setState(() {
        _error = '설정 저장 실패: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scaleFactor;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 450,
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7F5AF0).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.settings_rounded, color: Color(0xFF7F5AF0), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Bst Teacher 설정',
                        style: GoogleFonts.notoSansKr(
                          color: _textColor,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4565).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(_error!, style: GoogleFonts.notoSansKr(color: const Color(0xFFEF4565), fontSize: 12)),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 1. 학교 검색 및 선택
                  _buildLabel('학교 검색'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: '학교명을 입력하세요 (예: 한빛중)',
                            hintStyle: GoogleFonts.notoSansKr(color: Colors.white24, fontSize: 13),
                            fillColor: Colors.white.withOpacity(0.03),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                            ),
                          ),
                          style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14),
                          onSubmitted: _searchSchool,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => _searchSchool(_searchController.text),
                        icon: const Icon(Icons.search_rounded, color: Color(0xFF7F5AF0)),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF7F5AF0).withOpacity(0.08),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_searching)
                    const Center(child: LinearProgressIndicator(color: Color(0xFF7F5AF0)))
                  else if (_searchResults.isNotEmpty)
                    Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.02),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final school = _searchResults[index];
                          return ListTile(
                            title: Text(school.name, style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13)),
                            subtitle: Text(school.region, style: GoogleFonts.notoSansKr(color: Colors.white30, fontSize: 11)),
                            onTap: () => _loadSchoolTeachers(school),
                          );
                        },
                      ),
                    ),

                  if (_selectedSchool != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2CB67D).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline_rounded, color: Color(0xFF2CB67D), size: 16),
                          const SizedBox(width: 8),
                          Text(
                            '선택된 학교: ${_selectedSchool!.name} (${_selectedSchool!.region})',
                            style: GoogleFonts.notoSansKr(color: const Color(0xFF2CB67D), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),

                    // 담당 교사 선택 영역
                    const SizedBox(height: 16),
                    _buildLabel('교사명 기입'),
                    const SizedBox(height: 8),
                    if (_loadingTeachers)
                      const Center(child: LinearProgressIndicator(color: Color(0xFF7F5AF0)))
                    else if (_teachers.isEmpty)
                      Text('교사 목록을 가져오지 못했습니다.', style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 13))
                    else ...[
                      TextField(
                        controller: _teacherController,
                        decoration: InputDecoration(
                          hintText: '교사명을 기입하세요 (예: 김교사)',
                          hintStyle: GoogleFonts.notoSansKr(color: Colors.white24, fontSize: 13),
                          fillColor: Colors.white.withOpacity(0.03),
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
                          ),
                        ),
                        style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14),
                        onChanged: (val) {
                          setState(() {
                            _selectedTeacher = val;
                          });
                          _autoDetectHomeroomClass(val);
                        },
                      ),
                      Builder(
                        builder: (context) {
                          final query = _teacherController.text.replaceAll('*', '').trim().toUpperCase();
                          final filtered = _teachers.where((t) {
                            final name = t.replaceAll('*', '').trim().toUpperCase();
                            return name.contains(query) && name != query;
                          }).take(5).toList();

                          if (filtered.isEmpty) return const SizedBox.shrink();

                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: filtered.map((t) {
                                return ActionChip(
                                  backgroundColor: const Color(0xFF7F5AF0).withOpacity(0.08),
                                  side: BorderSide(color: const Color(0xFF7F5AF0).withOpacity(0.3)),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  label: Text(
                                    t,
                                    style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 11),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _selectedTeacher = t;
                                      _teacherController.text = t;
                                    });
                                    _autoDetectHomeroomClass(t);
                                  },
                                );
                              }).toList(),
                            ),
                          );
                        },
                      ),
                      if (_selectedTeacher.isNotEmpty && _homeroomMatched) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2CB67D).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF2CB67D).withOpacity(0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Color(0xFF2CB67D), size: 14),
                              const SizedBox(width: 6),
                              Text(
                                '담임 학급 확인: $_selectedGrade학년 $_selectedClass반',
                                style: GoogleFonts.notoSansKr(
                                  color: const Color(0xFF2CB67D),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (_selectedTeacher.isNotEmpty && !_homeroomMatched && !_loadingTeachers) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.withOpacity(0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                '담임 미확인 (아래 학년/반을 직접 설정해주세요)',
                                style: GoogleFonts.notoSansKr(
                                  color: Colors.amber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],

                  const SizedBox(height: 16),

                  // 2. 학년 및 반
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('학년'),
                            const SizedBox(height: 8),
                            _buildDropdown<int>(
                              value: _selectedGrade,
                              items: [1, 2, 3],
                              labelBuilder: (v) => '$v학년',
                              onChanged: (v) => setState(() => _selectedGrade = v!),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('반'),
                            const SizedBox(height: 8),
                            _buildDropdown<int>(
                              value: _selectedClass,
                              items: List.generate(15, (i) => i + 1),
                              labelBuilder: (v) => '$v반',
                              onChanged: (v) => setState(() => _selectedClass = v!),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('화면 모드'),
                            const SizedBox(height: 8),
                            _buildDropdown<String>(
                              value: 'dark',
                              items: const ['dark'],
                              labelBuilder: (v) => '다크 모드 (기본)',
                              onChanged: (v) => setState(() => _themeMode = 'dark'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.login_rounded, size: 16, color: Color(0xFF7F5AF0)),
                        label: Text('구글 로그인', style: GoogleFonts.notoSansKr(color: const Color(0xFF7F5AF0), fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => const GoogleLoginWebview(),
                            ),
                          );
                        },
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white38)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _selectedSchool == null ? null : _saveSettings,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF7F5AF0),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                            child: Text('저장', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
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
