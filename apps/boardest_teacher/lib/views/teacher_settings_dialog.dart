import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_settings.dart';
import '../models/school.dart';
import '../services/storage_service.dart';
import '../services/comcigan_service.dart';
import '../services/cloud_drive_service.dart';
import 'components/oauth_iframe_view.dart';

/// Boardest Teacher 전역 설정 모던 다이얼로그 (Class 스타일 2-패널 + OAuth iframe 연동)
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
  int _activeCategoryIndex = 0;

  // 1. 학교 및 교사
  School? _selectedSchool;
  int _selectedGrade = 1;
  int _selectedClass = 1;
  List<String> _teachers = [];
  String _selectedTeacher = '';
  bool _loadingTeachers = false;
  bool _homeroomMatched = false;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _teacherController = TextEditingController();
  List<School> _searchResults = [];
  bool _searching = false;

  // 2. 테마 & UI
  String _themeMode = 'dark';
  double _uiScale = 1.0;

  // 3. OAuth 상태
  bool _hasCloudDrive = false;
  String _cloudUserEmail = '';

  final List<Map<String, dynamic>> _categories = [
    {
      'title': '학교 및 교사',
      'subtitle': '소속 학교, 학년/반, 담당 교사',
      'icon': Icons.school_rounded,
      'color': Color(0xFF00F5D4),
    },
    {
      'title': 'Cloud & OAuth',
      'subtitle': 'Google Drive & 전용 웹 계정 설정',
      'icon': Icons.cloud_sync_rounded,
      'color': Color(0xFF7F5AF0),
    },
    {
      'title': '화면 및 테마',
      'subtitle': '다크 모드, UI 확대/축소 배율',
      'icon': Icons.aspect_ratio_rounded,
      'color': Color(0xFF2EC4B6),
    },
    {
      'title': '시스템 및 데이터',
      'subtitle': '설정 초기화, 캐시 비우기',
      'icon': Icons.shield_rounded,
      'color': Color(0xFFEF4565),
    },
  ];

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
      final hasDrive = CloudDriveService.instance.isLoggedIn;
      final driveEmail = CloudDriveService.instance.userEmail ?? '';

      if (mounted) {
        setState(() {
          _settings = s;
          _selectedSchool = s.selectedSchool;
          _selectedGrade = s.selectedGrade;
          _selectedClass = s.selectedClass;
          _teachers = teachersList;
          _selectedTeacher = s.selectedTeacher;
          _teacherController.text = s.selectedTeacher;
          _themeMode = s.themeMode;
          _uiScale = s.scaleFactor;
          _hasCloudDrive = hasDrive;
          _cloudUserEmail = driveEmail;
          _loading = false;
          _loadingTeachers = false;
        });
      }
      if (s.selectedTeacher.isNotEmpty) {
        await _autoDetectHomeroomClass(s.selectedTeacher);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '설정을 불러오지 못했습니다: $e';
          _loading = false;
          _loadingTeachers = false;
        });
      }
    }
  }

  Future<void> _searchSchool(String keyword) async {
    if (keyword.trim().isEmpty) return;
    setState(() => _searching = true);
    try {
      final results = await _comcigan.searchSchool(keyword);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _searching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '학교 검색 실패: $e';
          _searching = false;
        });
      }
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
      if (mounted) {
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
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '교사 목록 로드 실패: $e';
          _loadingTeachers = false;
        });
      }
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

      if (mounted) {
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
      }
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    if (_settings == null) return;
    setState(() => _loading = true);
    try {
      final teacherName = _teacherController.text.trim().isNotEmpty
          ? _teacherController.text.trim()
          : _selectedTeacher;
      final updated = _settings!.copyWith(
        selectedSchool: _selectedSchool,
        selectedGrade: _selectedGrade,
        selectedClass: _selectedClass,
        selectedTeacher: teacherName,
        selectedTeacherName: teacherName,
        themeMode: _themeMode,
        scaleFactor: _uiScale,
      );
      await _storage.saveSettings(updated);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '저장 실패: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final dialogWidth = (size.width * 0.85).clamp(800.0, 1100.0);
    final dialogHeight = (size.height * 0.88).clamp(560.0, 780.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF0F141E),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00F5D4).withOpacity(0.08),
              blurRadius: 36,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.8),
              blurRadius: 30,
            ),
          ],
        ),
        child: Column(
          children: [
            // Header Bar
            _buildHeaderBar(),
            const Divider(color: Colors.white10, height: 1),

            // Main 2-Panel Content
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF00F5D4)),
                    )
                  : Row(
                      children: [
                        // Left Sidebar Navigation (Class Style)
                        _buildSidebar(),
                        const VerticalDivider(color: Colors.white10, width: 1),

                        // Right Content Area
                        Expanded(
                          child: Container(
                            color: const Color(0xFF0A0E17),
                            child: _buildActiveTabContent(),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF141A29),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00F5D4).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.settings_rounded, color: Color(0xFF00F5D4), size: 22),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Boardest Teacher 환경설정',
                    style: GoogleFonts.notoSansKr(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '학급 시간표, 교사 정보 및 Cloud OAuth 계정 통합 관리',
                    style: GoogleFonts.notoSansKr(
                      color: const Color(0xFF94A1B2),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white70)),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00F5D4),
                  foregroundColor: const Color(0xFF080D11),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _saveSettings,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  '설정 저장',
                  style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 250,
      color: const Color(0xFF0E131F),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Column(
        children: List.generate(_categories.length, (index) {
          final cat = _categories[index];
          final isSelected = _activeCategoryIndex == index;
          final color = cat['color'] as Color;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => setState(() => _activeCategoryIndex = index),
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? color.withOpacity(0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? color.withOpacity(0.4) : Colors.transparent,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(cat['icon'] as IconData, color: isSelected ? color : const Color(0xFF94A1B2), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cat['title'] as String,
                            style: GoogleFonts.notoSansKr(
                              color: isSelected ? Colors.white : const Color(0xFF94A1B2),
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 13.5,
                            ),
                          ),
                          Text(
                            cat['subtitle'] as String,
                            style: GoogleFonts.notoSansKr(
                              color: const Color(0xFF64748B),
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (_activeCategoryIndex) {
      case 0:
        return _buildSchoolTab();
      case 1:
        return _buildCloudOAuthTab();
      case 2:
        return _buildDisplayThemeTab();
      case 3:
        return _buildSystemTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // 1. 학교 및 교사 탭
  Widget _buildSchoolTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('소속 학교 설정', '전국 중·고등학교 컴시간 시간표 연동 학교를 선택합니다.'),
          const SizedBox(height: 14),

          // 현재 선택된 학교 배지
          if (_selectedSchool != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF00F5D4).withOpacity(0.1),
                border: Border.all(color: const Color(0xFF00F5D4).withOpacity(0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF00F5D4), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${_selectedSchool!.name} (${_selectedSchool!.region}) · 코드 ${_selectedSchool!.code}',
                      style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 12),
          // 학교 검색 입력창
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '학교명을 입력하세요 (예: 길동중학교)',
                    hintStyle: GoogleFonts.notoSansKr(color: const Color(0xFF64748B)),
                    filled: true,
                    fillColor: const Color(0xFF141A29),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  onSubmitted: _searchSchool,
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7F5AF0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _searchSchool(_searchController.text),
                child: _searching
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('검색'),
              ),
            ],
          ),

          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: const Color(0xFF141A29),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _searchResults.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
                itemBuilder: (context, idx) {
                  final sc = _searchResults[idx];
                  return ListTile(
                    dense: true,
                    title: Text(sc.name, style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text('${sc.region} · 코드 ${sc.code}', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11)),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF00F5D4), size: 14),
                    onTap: () => _loadSchoolTeachers(sc),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 28),
          _buildSectionHeader('담임 및 담당 교사', '선생님 성함을 선택하면 주간 시간표와 담임 학급이 자동 매칭됩니다.'),
          const SizedBox(height: 14),

          // 교사 드롭다운 / 입력
          if (_loadingTeachers)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Color(0xFF00F5D4), strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('교사 명단을 컴시간에서 불러오는 중...', style: TextStyle(color: Color(0xFF94A1B2), fontSize: 13)),
                ],
              ),
            )
          else if (_teachers.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              value: _teachers.contains(_selectedTeacher) ? _selectedTeacher : null,
              dropdownColor: const Color(0xFF141A29),
              style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: '교사 명단 선택',
                labelStyle: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2)),
                filled: true,
                fillColor: const Color(0xFF141A29),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              items: _teachers.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedTeacher = val;
                    _teacherController.text = val;
                  });
                  _autoDetectHomeroomClass(val);
                }
              },
            ),
          ] else ...[
            TextField(
              controller: _teacherController,
              style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: '선생님 성함 직접 입력',
                labelStyle: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2)),
                filled: true,
                fillColor: const Color(0xFF141A29),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],

          const SizedBox(height: 20),
          // 학년 및 반
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedGrade,
                  dropdownColor: const Color(0xFF141A29),
                  style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: '학년',
                    labelStyle: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2)),
                    filled: true,
                    fillColor: const Color(0xFF141A29),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                  items: [1, 2, 3, 4, 5, 6].map((g) => DropdownMenuItem(value: g, child: Text('$g학년'))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedGrade = val);
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _selectedClass,
                  dropdownColor: const Color(0xFF141A29),
                  style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: '학급 (반)',
                    labelStyle: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2)),
                    filled: true,
                    fillColor: const Color(0xFF141A29),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                  items: List.generate(15, (i) => i + 1).map((c) => DropdownMenuItem(value: c, child: Text('$c반'))).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedClass = val);
                  },
                ),
              ),
            ],
          ),

          if (_homeroomMatched) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: Color(0xFF7F5AF0), size: 16),
                const SizedBox(width: 6),
                Text('컴시간 시간표에서 담임 학급이 자동 인식되었습니다.', style: GoogleFonts.notoSansKr(color: const Color(0xFF7F5AF0), fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // 2. Cloud & OAuth 탭 (iframe 임베드 지원)
  Widget _buildCloudOAuthTab() {
    const oauthUrl = 'https://boardest-cloud-connect.web.app';

    return Column(
      children: [
        // 상단 안내 & 팝업 열기 바
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: const Color(0xFF141A29),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _hasCloudDrive ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _hasCloudDrive ? 'Google Drive 연동됨 ($_cloudUserEmail)' : 'Google Drive 미연동 (로그인 필요)',
                    style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7F5AF0),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => launchUrl(Uri.parse(oauthUrl), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text('새 탭에서 OAuth 열기', style: GoogleFonts.notoSansKr(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),

        // 임베드 IFrame
        Expanded(
          child: Container(
            color: const Color(0xFF0F0E17),
            child: const OAuthIFrameView(url: oauthUrl),
          ),
        ),
      ],
    );
  }

  // 3. 화면 및 테마 탭
  Widget _buildDisplayThemeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('화면 테마 모드', '시각적 피로도를 줄여주는 다크 모드와 고대비 모드를 지원합니다.'),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildThemeOption('dark', '다크 모드', Icons.dark_mode_rounded, const Color(0xFF0F141E)),
              const SizedBox(width: 14),
              _buildThemeOption('light', '라이트 모드', Icons.light_mode_rounded, const Color(0xFFF8FAFC)),
            ],
          ),
          const SizedBox(height: 32),
          _buildSectionHeader('UI 배율 (DPI)', '고해상도 모니터나 소형 노트북 환경에 맞게 인터페이스 크기를 조절합니다.'),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF141A29),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('배율: ${(_uiScale * 100).toInt()}%', style: GoogleFonts.outfit(color: const Color(0xFF00F5D4), fontWeight: FontWeight.bold, fontSize: 16)),
                    TextButton(onPressed: () => setState(() => _uiScale = 1.0), child: const Text('기본값 (100%)', style: TextStyle(color: Colors.white54, fontSize: 12))),
                  ],
                ),
                Slider(
                  value: _uiScale,
                  min: 0.8,
                  max: 1.4,
                  divisions: 6,
                  activeColor: const Color(0xFF00F5D4),
                  inactiveColor: Colors.white12,
                  onChanged: (val) => setState(() => _uiScale = val),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption(String id, String label, IconData icon, Color previewBg) {
    final isSelected = _themeMode == id;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _themeMode = id),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF141A29),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? const Color(0xFF00F5D4) : Colors.white12,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: isSelected ? const Color(0xFF00F5D4) : Colors.white54, size: 24),
              const SizedBox(width: 12),
              Text(label, style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  // 4. 시스템 및 데이터 탭
  Widget _buildSystemTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('데이터 및 캐시 관리', '임시 파일 및 로컬 저장 데이터를 초기화합니다.'),
          const SizedBox(height: 14),

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF141A29),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('로컬 캐시 비우기', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('시간표 및 급식 임시 캐시를 즉시 새로고침합니다.', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12)),
                  ],
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF00F5D4), side: const BorderSide(color: Color(0xFF00F5D4))),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('로컬 캐시가 성공적으로 비워졌습니다.')));
                  },
                  child: const Text('캐시 정리'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF141A29),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Google 계정 로그아웃', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('연동된 Google Drive 토큰을 연결 해제합니다.', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12)),
                  ],
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4565), foregroundColor: Colors.white),
                  onPressed: () async {
                    await CloudDriveService.instance.logout();
                    if (mounted) {
                      setState(() {
                        _hasCloudDrive = false;
                        _cloudUserEmail = '';
                      });
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Google Drive 연결이 해제되었습니다.')));
                    }
                  },
                  child: const Text('연결 해제'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String desc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(desc, style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12)),
      ],
    );
  }
}
