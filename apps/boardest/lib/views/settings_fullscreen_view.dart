import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:universal_io/io.dart';

import '../config/app_config.dart';
import '../models/app_settings.dart';
import '../models/school.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../services/update_service.dart';
import '../services/comcigan_service.dart';
import 'setup_wizard_view.dart';

/// Boardest 전체화면 모던 시스템 설정 뷰
class SettingsFullscreenView extends StatefulWidget {
  final AppSettings settings;
  final VoidCallback? onSettingsChanged;

  const SettingsFullscreenView({
    super.key,
    required this.settings,
    this.onSettingsChanged,
  });

  @override
  State<SettingsFullscreenView> createState() => _SettingsFullscreenViewState();
}

class _SettingsFullscreenViewState extends State<SettingsFullscreenView> {
  final StorageService _storageService = StorageService();
  final AuthService _authService = AuthService();

  late AppSettings _currentSettings;
  int _activeCategoryIndex = 0;
  bool _isSaving = false;

  // Form Controllers
  late TextEditingController _schoolIdController;
  late TextEditingController _specialIdController;
  late double _currentScaleFactor;
  late int _selectedGrade;
  late int _selectedClass;
  late bool _specialClassMode;
  late int _specialClassType;
  late bool _autoSleepEnabled;
  late String _aspectRatio;
  late String _selectedCafeteria;

  final List<Map<String, dynamic>> _categories = [
    {
      'title': '학교 및 학급',
      'subtitle': '학교 식별 ID, 학년, 반 설정',
      'icon': Icons.school_rounded,
      'color': Color(0xFF00F5D4),
    },
    {
      'title': '교실 운영 모드',
      'subtitle': '일반 교실 vs 교사 특별실',
      'icon': Icons.meeting_room_rounded,
      'color': Color(0xFF7F5AF0),
    },
    {
      'title': '화면 및 디스플레이',
      'subtitle': '화면 배율(DPI), 화면비율, 전체화면',
      'icon': Icons.aspect_ratio_rounded,
      'color': Color(0xFF2EC4B6),
    },
    {
      'title': '시스템 및 자동화',
      'subtitle': '자동 절전, 시스템 업데이트',
      'icon': Icons.tune_rounded,
      'color': Color(0xFF00BAF2),
    },
    {
      'title': '데이터 및 계정',
      'subtitle': '설정 초기화, 로그아웃',
      'icon': Icons.shield_rounded,
      'color': Color(0xFFEF4565),
    },
  ];

  @override
  void initState() {
    super.initState();
    _currentSettings = widget.settings;
    _schoolIdController = TextEditingController(text: _currentSettings.schoolId);
    _specialIdController = TextEditingController(text: _currentSettings.classNickname);
    _currentScaleFactor = 1.30;
    _selectedGrade = _currentSettings.selectedGrade;
    _selectedClass = _currentSettings.selectedClass;
    _specialClassMode = _currentSettings.specialClassroomMode;
    _specialClassType = _currentSettings.specialClassroomType;
    _autoSleepEnabled = _currentSettings.autoSleepEnabled;
    _aspectRatio = _currentSettings.aspectRatio;
    _selectedCafeteria = _currentSettings.cafeteriaNum.isNotEmpty ? _currentSettings.cafeteriaNum : '급식실1';
  }

  @override
  void dispose() {
    _schoolIdController.dispose();
    _specialIdController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings({bool popAfter = false}) async {
    setState(() => _isSaving = true);
    final updated = _currentSettings.copyWith(
      schoolId: _schoolIdController.text.trim().toLowerCase(),
      selectedGrade: _selectedGrade,
      selectedClass: _selectedClass,
      scaleFactor: _currentScaleFactor,
      specialClassroomType: _specialClassMode ? (_specialClassType > 0 ? _specialClassType : 2) : 0,
      classNickname: _specialIdController.text.trim(),
      autoSleepEnabled: _autoSleepEnabled,
      aspectRatio: _aspectRatio,
      cafeteriaNum: _selectedCafeteria,
    );

    await _storageService.saveSettings(updated);
    _currentSettings = updated;
    widget.onSettingsChanged?.call();

    if (!mounted) return;
    setState(() => _isSaving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF00F5D4), size: 20),
            const SizedBox(width: 10),
            Text('설정이 안전하게 저장되었습니다.', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: const Color(0xFF161B26),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );

    if (popAfter && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _onSwitchModeRequested(bool toSpecial) async {
    if (_specialClassMode == toSpecial) return;
    final modeName = toSpecial ? '교사 1인 특별실 (Class Teacher)' : '일반 교실 (Class PRO)';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFEF4565), width: 1.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4565), size: 28),
            const SizedBox(width: 10),
            Text('교실 운영 모드 전환', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '교실 운영 모드를 [$modeName]로 변경하시겠습니까?\n\n⚠️ 운영 모드를 전환하면 기존 교실의 학교 설정 및 데이터가 모두 초기화되며, $modeName 초기 설정(로그인) 화면으로 이동합니다.',
          style: GoogleFonts.notoSansKr(color: const Color(0xFFCBD5E1), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4565),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('데이터 초기화 및 전환', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isSaving = true);
      await _authService.logout();
      final clearedSettings = AppSettings(
        schoolId: '',
        selectedSchool: toSpecial ? School(id: 0, code: 0, name: '교사용 연구실', region: '전국') : null,
        selectedGrade: 1,
        selectedClass: 1,
        specialClassroomType: toSpecial ? 1 : 0,
        isSetupComplete: false,
      );
      await _storageService.saveSettings(clearedSettings);

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => SetupWizardView(initialEditionMode: toSpecial ? 2 : 0),
          ),
          (route) => false,
        );
      }
    }
  }

  Future<void> _verifySchoolIdInline() async {
    final schoolId = _schoolIdController.text.trim();
    if (schoolId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('학교 ID를 입력해주세요.'), backgroundColor: Color(0xFFEF4565)),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final codeStr = await ComciganService.fetchCode(schoolId.toLowerCase());
      final parsedCode = int.tryParse(codeStr);
      if (parsedCode != null && parsedCode > 0) {
        final newSchool = School(
          id: parsedCode,
          code: parsedCode,
          name: _currentSettings.selectedSchool?.name.isNotEmpty == true && !_currentSettings.selectedSchool!.name.contains('미선택')
              ? _currentSettings.selectedSchool!.name
              : '$schoolId 학교',
          region: _currentSettings.selectedSchool?.region ?? '전국',
        );
        setState(() {
          _currentSettings = _currentSettings.copyWith(
            schoolId: schoolId,
            selectedSchool: newSchool,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 학교 ID 연결 성공! (컴시간 코드: $parsedCode)'),
            backgroundColor: const Color(0xFF00F5D4),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('유효한 학교 코드를 찾을 수 없습니다.'), backgroundColor: Color(0xFFEF4565)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('학교 ID 확인 실패: $e'), backgroundColor: const Color(0xFFEF4565)),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = _currentScaleFactor;
    final isDemo = AppConfig.isDemoMode || _currentSettings.schoolId.toLowerCase() == 'demo';

    return Scaffold(
      backgroundColor: const Color(0xFF0A0D14),
      body: Stack(
        children: [
          // Background Glow Decoration
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 400,
              height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF7F5AF0).withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            right: -150,
            child: Container(
              width: 500,
              height: 500,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00F5D4).withValues(alpha: 0.08),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // 1. Top Header Bar
                _buildTopHeader(scale, isDemo),

                // 2. Main 2-Column Split View
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Left Sidebar: Categories
                      SizedBox(
                        width: 280 * (scale > 1.2 ? 1.1 : 1.0),
                        child: _buildCategorySidebar(scale),
                      ),

                      // Vertical Divider
                      Container(width: 1, color: Colors.white.withValues(alpha: 0.08)),

                      // Right Content Panel
                      Expanded(
                        child: _buildCategoryDetailPanel(scale, isDemo),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Saving Overlay
          if (_isSaving)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00F5D4)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- Top Header ---
  Widget _buildTopHeader(double scale, bool isDemo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F141F).withValues(alpha: 0.85),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: '대시보드로 돌아가기',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(width: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/icons/logo.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.bolt, color: Color(0xFF00F5D4), size: 30),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'BOARDEST ${kIsWeb ? (_specialClassMode ? 'Class Teacher' : 'Class') : (_specialClassMode ? 'Teacher PRO' : 'Class PRO')}',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF00F5D4).withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          '${_currentSettings.selectedSchool?.name ?? "학교"} ${_selectedGrade}학년 ${_selectedClass}반',
                          style: GoogleFonts.notoSansKr(
                            color: const Color(0xFF00F5D4),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'by jiwho • v3.9 Beta',
                    style: TextStyle(
                      color: Color(0xFF94A1B2),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Actions
          Row(
            children: [
              if (isDemo)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_rounded, color: Colors.purpleAccent, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '데모 모드 (설정 잠금)',
                        style: GoogleFonts.notoSansKr(
                          color: Colors.purpleAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: () => _saveSettings(popAfter: true),
                  icon: const Icon(Icons.check_rounded, color: Colors.black, size: 18),
                  label: Text('저장 및 닫기', style: GoogleFonts.notoSansKr(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F5D4),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // --- Left Sidebar ---
  Widget _buildCategorySidebar(double scale) {
    return Container(
      color: const Color(0xFF0D111A).withValues(alpha: 0.7),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: ListView.separated(
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = _activeCategoryIndex == index;
          final color = cat['color'] as Color;

          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _activeCategoryIndex = index),
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? color.withValues(alpha: 0.5) : Colors.transparent,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected ? color : color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(cat['icon'] as IconData, color: isSelected ? Colors.black : color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            cat['title'] as String,
                            style: GoogleFonts.notoSansKr(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            cat['subtitle'] as String,
                            style: GoogleFonts.notoSansKr(
                              color: const Color(0xFF94A1B2),
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
        },
      ),
    );
  }

  // --- Right Main Detail Panel ---
  Widget _buildCategoryDetailPanel(double scale, bool isDemo) {
    if (isDemo) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF161B26),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.3)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_rounded, color: Colors.purpleAccent, size: 48),
              const SizedBox(height: 16),
              Text(
                '🔒 데모 모드에서는 설정을 변경할 수 없습니다.',
                style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '학교 정보 및 학급 시간표는 가상 시뮬레이션 데이터로 안전하게 격리되어 제공됩니다.',
                style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    Widget content;
    switch (_activeCategoryIndex) {
      case 0:
        content = _buildSchoolAndClassSection();
        break;
      case 1:
        content = _buildRoomModeSection();
        break;
      case 2:
        content = _buildDisplaySection();
        break;
      case 3:
        content = _buildSystemAutomationSection();
        break;
      case 4:
        content = _buildAccountSection();
        break;
      default:
        content = const SizedBox.shrink();
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: content,
        ),
      ),
    );
  }

  // 1. School & Class Section
  Widget _buildSchoolAndClassSection() {
    final school = _currentSettings.selectedSchool;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('🏫 학교 및 학급 설정', '학교 식별 ID와 현재 설치된 교실의 학년/반을 설정합니다.'),
        const SizedBox(height: 20),

        // School Info Card
        _buildSettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(school?.name ?? '학교 미선택', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('${school?.region ?? "-"} | 컴시간 학교 코드: ${school?.code ?? "-"}', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 13)),
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const SetupWizardView(startWithStepList: true)),
                      );
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('학교 변경 마법사'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00F5D4),
                      side: const BorderSide(color: Color(0xFF00F5D4)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _schoolIdController,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        labelText: '학교 ID (중앙 관리자 등록 ID)',
                        labelStyle: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2)),
                        prefixIcon: const Icon(Icons.vpn_key_rounded, color: Color(0xFF00F5D4)),
                        filled: true,
                        fillColor: const Color(0xFF0F141F),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F5D4),
                      foregroundColor: const Color(0xFF080D11),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _verifySchoolIdInline,
                    icon: const Icon(Icons.check_circle_rounded, size: 20),
                    label: Text('학교 연결', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Grade & Class Selector
        _buildSettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('학년 선택', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: List.generate(3, (index) {
                  final grade = index + 1;
                  final isSelected = _selectedGrade == grade;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ChoiceChip(
                      label: Text('$grade학년', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                      selected: isSelected,
                      selectedColor: const Color(0xFF00F5D4),
                      backgroundColor: const Color(0xFF0F141F),
                      checkmarkColor: Colors.black,
                      onSelected: (val) {
                        if (val) setState(() => _selectedGrade = grade);
                      },
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
              Text('반 선택 (1반 ~ 15반)', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(15, (index) {
                  final classNum = index + 1;
                  final isSelected = _selectedClass == classNum;
                  return ChoiceChip(
                    label: Text('$classNum반', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                    selected: isSelected,
                    selectedColor: const Color(0xFF7F5AF0),
                    backgroundColor: const Color(0xFF0F141F),
                    checkmarkColor: Colors.white,
                    onSelected: (val) {
                      if (val) setState(() => _selectedClass = classNum);
                    },
                  );
                }),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('급식실 배정 (급식실 1 ~ 급식실 9)', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  Text('배식 호출 및 순번 연동', style: GoogleFonts.notoSansKr(color: const Color(0xFF00F5D4), fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(9, (index) {
                  final cafeteriaName = '급식실${index + 1}';
                  final isSelected = _selectedCafeteria == cafeteriaName;
                  return ChoiceChip(
                    label: Text(cafeteriaName, style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                    selected: isSelected,
                    selectedColor: const Color(0xFFFF8906),
                    backgroundColor: const Color(0xFF0F141F),
                    checkmarkColor: Colors.black,
                    onSelected: (val) {
                      if (val) setState(() => _selectedCafeteria = cafeteriaName);
                    },
                  );
                }),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 2. Room Mode Section
  Widget _buildRoomModeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('👨‍🏫 교실 운영 모드 설정', '일반 학급 전자칠판과 교사 전용 특별실 모드를 선택합니다.'),
        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: _buildModeSelectCard(
                title: kIsWeb ? 'Boardest Class' : 'Boardest Class PRO',
                subtitle: '일반 교실 전자칠판\n학급 시간표, 급식, 학급 도구, OTP 연동',
                icon: Icons.school_rounded,
                color: const Color(0xFF00F5D4),
                isSelected: !_specialClassMode,
                onTap: () => _onSwitchModeRequested(false),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildModeSelectCard(
                title: kIsWeb ? 'Boardest Class Teacher' : 'Boardest Class Teacher PRO',
                subtitle: '교사 1인 특별실/연구실\n구글 계정 로그인, OTP 없이 Cloud 직결',
                icon: Icons.person_pin_rounded,
                color: const Color(0xFF7F5AF0),
                isSelected: _specialClassMode,
                onTap: () => _onSwitchModeRequested(true),
              ),
            ),
          ],
        ),

        if (_specialClassMode) ...[
          const SizedBox(height: 24),
          _buildSettingsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('특별실 고유 식별 명칭', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: _specialIdController,
                  style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: '예: 과학1실, 음악실, 3교무실',
                    hintStyle: GoogleFonts.notoSansKr(color: const Color(0xFF72757E)),
                    filled: true,
                    fillColor: const Color(0xFF0F141F),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // 3. Display Section
  Widget _buildDisplaySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('🖥️ 화면 및 디스플레이', '전자칠판 해상도와 UI 크기, 화면 비율을 조정합니다.'),
        const SizedBox(height: 20),

        // DPI Scale Slider
        _buildSettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text('화면 배율 (DPI 조정)', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8906).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFF8906).withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          '🔒 고정 배율',
                          style: GoogleFonts.notoSansKr(color: const Color(0xFFFF8906), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '130%',
                      style: GoogleFonts.outfit(color: const Color(0xFF00F5D4), fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Slider(
                value: 1.30,
                min: 1.0,
                max: 2.0,
                divisions: 10,
                activeColor: Color(0xFF00F5D4),
                inactiveColor: Colors.white12,
                onChanged: null,
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('100% (기본 모니터)', style: GoogleFonts.notoSansKr(color: const Color(0xFF72757E), fontSize: 11)),
                  Text('🔒 130% (표준 고정 - 수동 변경 불가)', style: GoogleFonts.notoSansKr(color: const Color(0xFF00F5D4), fontSize: 11, fontWeight: FontWeight.bold)),
                  Text('200% (초대형 전자칠판)', style: GoogleFonts.notoSansKr(color: const Color(0xFF72757E), fontSize: 11)),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Aspect Ratio
        _buildSettingsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('화면비율 (가상 칠판 캔버스)', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Row(
                children: [
                  ChoiceChip(
                    label: Text('16:9 (와이드 스크린)', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                    selected: _aspectRatio == '16:9',
                    selectedColor: const Color(0xFF00F5D4),
                    backgroundColor: const Color(0xFF0F141F),
                    checkmarkColor: Colors.black,
                    onSelected: (val) {
                      if (val) setState(() => _aspectRatio = '16:9');
                    },
                  ),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: Text('4:3 (고전 비율)', style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold)),
                    selected: _aspectRatio == '4:3',
                    selectedColor: const Color(0xFF00F5D4),
                    backgroundColor: const Color(0xFF0F141F),
                    checkmarkColor: Colors.black,
                    onSelected: (val) {
                      if (val) setState(() => _aspectRatio = '4:3');
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 4. System Automation
  Widget _buildSystemAutomationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('⚙️ 시스템 및 자동화', '절전 모드 및 플랫폼 시스템 설정을 관리합니다.'),
        const SizedBox(height: 20),

        if (!kIsWeb && Platform.isWindows) ...[
          _buildSettingsCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('자동 절전 모드', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text('쉬는 시간·점심·하교 후 모니터를 끄고 수업 교시 시작 시 자동 켬', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12)),
              value: _autoSleepEnabled,
              activeColor: const Color(0xFF00F5D4),
              onChanged: (val) => setState(() => _autoSleepEnabled = val),
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (!kIsWeb) ...[
          _buildSettingsCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('시스템 업데이트 확인', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('현재 버전: v${UpdateService.currentVersion} [채널: ${_currentSettings.updateChannel.toUpperCase()}]', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12)),
                  ],
                ),
                ElevatedButton(
                  onPressed: () => UpdateService.checkAndUpdate(
                    context,
                    silent: false,
                    channel: _currentSettings.updateChannel,
                  ),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2EC4B6)),
                  child: const Text('최신 버전 확인', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // 5. Account & Reset
  Widget _buildAccountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('🔒 데이터 및 세션 초기화', '학교 정보 외 모든 개인정보 저장을 금지하며 세션을 초기화합니다.'),
        const SizedBox(height: 20),

        _buildSettingsCard(
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout_rounded, color: Color(0xFFEF4565)),
                title: Text('로그아웃', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('현재 기기의 모든 로컬 세션 및 클라우드 연결 해제', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12)),
                trailing: OutlinedButton(
                  onPressed: () async {
                    await _authService.logout();
                    if (!mounted) return;
                    Navigator.of(context).pop();
                  },
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFEF4565))),
                  child: const Text('로그아웃', style: TextStyle(color: Color(0xFFEF4565))),
                ),
              ),
              const Divider(color: Colors.white12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4565)),
                title: Text('설정 전체 초기화', style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('저장된 학교 설정을 초기화하고 처음 시작 화면으로 전환', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12)),
                trailing: OutlinedButton(
                  onPressed: () async {
                    await _storageService.saveSettings(AppSettings());
                    if (!mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const SetupWizardView()),
                      (route) => false,
                    );
                  },
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFEF4565))),
                  child: const Text('초기화', style: TextStyle(color: Color(0xFFEF4565))),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Helper UI Builders
  Widget _buildSectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(subtitle, style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 13)),
      ],
    );
  }

  Widget _buildSettingsCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF141926).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildModeSelectCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.12) : const Color(0xFF141926).withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: isSelected ? color : Colors.white12, width: isSelected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: isSelected ? color : Colors.white60, size: 24),
                  const SizedBox(width: 8),
                  Text(title, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 10),
              Text(subtitle, style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 12, height: 1.4)),
            ],
          ),
        ),
      ),
    );
  }
}
