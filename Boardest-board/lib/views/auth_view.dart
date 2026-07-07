import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';
import '../services/comcigan_service.dart';
import '../models/school.dart';
import 'dashboard_view.dart';
import 'setup_wizard_view.dart';

// 지역 목록
const _kRegions = [
  '서울', '경기', '인천', '강원', '충북', '충남', '대전', '세종',
  '경북', '경남', '대구', '울산', '부산', '전북', '전남', '광주', '제주',
];

class AuthView extends StatefulWidget {
  const AuthView({super.key});

  @override
  State<AuthView> createState() => _AuthViewState();
}

class _AuthViewState extends State<AuthView>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _storageService = StorageService();

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // 폼 컨트롤러
  final _schoolCtrl = TextEditingController();
  final _gradeCtrl = TextEditingController();
  final _classCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _pwConfirmCtrl = TextEditingController();

  String _region = '서울';
  bool _isLoading = false;
  String? _errorMessage;
  bool _pwVisible = false;
  bool _pwConfirmVisible = false;

  // 이메일 미리보기
  String get _previewEmail {
    final school = _schoolCtrl.text.trim();
    final grade = int.tryParse(_gradeCtrl.text.trim()) ?? 0;
    final cls = int.tryParse(_classCtrl.text.trim()) ?? 0;
    if (school.isEmpty || grade == 0 || cls == 0) return '';
    return AuthService.buildClassEmail(
      school: school,
      region: _region,
      grade: grade,
      classNum: cls,
    );
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _schoolCtrl.dispose();
    _gradeCtrl.dispose();
    _classCtrl.dispose();
    _pwCtrl.dispose();
    _pwConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final school = _schoolCtrl.text.trim();
    final grade = int.tryParse(_gradeCtrl.text.trim()) ?? 0;
    final cls = int.tryParse(_classCtrl.text.trim()) ?? 0;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    String? error = await _authService.loginOrSignupClass(
      region: _region,
      school: school,
      grade: grade,
      classNum: cls,
    );

    if (!mounted) return;

    if (error != null) {
      setState(() {
        _isLoading = false;
        _errorMessage = error;
      });
      return;
    }

    // 성공 → 다음 화면 결정
    final settings = await _storageService.getSettings();
    if (!mounted) return;

    // 임시/교실 계정으로 로그인한 경우, 설정을 자동 세팅하여 SetupWizard를 건너뛰고 Dashboard로 바로 진입하도록 보강
    final currentUser = await _authService.getCurrentUser();
    if (currentUser != null && currentUser.email.toLowerCase().contains('.nopw.bst')) {
      int schoolCode = 44134; // 기본 fallback
      int schoolId = 44134;
      try {
        final schools = await ComciganService().searchSchool(currentUser.school);
        if (schools.isNotEmpty) {
          schoolCode = schools.first.code;
          schoolId = schools.first.id;
        }
      } catch (_) {}

      final updatedSchool = School(
        id: schoolId,
        code: schoolCode,
        name: currentUser.school,
        region: currentUser.region,
      );

      final updatedSettings = settings.copyWith(
        isSetupComplete: true,
        selectedSchool: updatedSchool,
        selectedGrade: currentUser.grade,
        selectedClass: currentUser.classNum,
      );
      await _storageService.saveSettings(updatedSettings);
    }

    if (settings.isSetupComplete &&
        (settings.selectedSchool != null || settings.specialClassroomMode)) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardView()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SetupWizardView()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = Platform.isAndroid ? 1.0 : 1.4;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Stack(
        children: [
          // ─── 배경 오라 ───────────────────────────────────────────────
          Positioned(
            top: -120 * scale,
            left: -80 * scale,
            child: _GlowOrb(
              size: 350 * scale,
              color: const Color(0xFF7F5AF0).withValues(alpha: 0.15),
            ),
          ),
          Positioned(
            bottom: -100 * scale,
            right: -60 * scale,
            child: _GlowOrb(
              size: 300 * scale,
              color: const Color(0xFF2EC4B6).withValues(alpha: 0.12),
            ),
          ),
          Positioned(
            top: size.height * 0.4,
            right: size.width * 0.1,
            child: _GlowOrb(
              size: 180 * scale,
              color: const Color(0xFF2CB67D).withValues(alpha: 0.08),
            ),
          ),
          IgnorePointer(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: const SizedBox.expand(),
            ),
          ),

          // ─── 본문 ────────────────────────────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: 32.0 * scale,
                  vertical: 24.0 * scale,
                ),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 로고
                      _buildLogo(scale),
                      SizedBox(height: 36 * scale),

                      // 카드
                      _buildCard(scale),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(double scale) {
    return Column(
      children: [
        Container(
          width: 72 * scale,
          height: 72 * scale,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7F5AF0), Color(0xFF2EC4B6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20 * scale),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7F5AF0).withValues(alpha: 0.4),
                blurRadius: 24 * scale,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(
            Icons.school_rounded,
            color: Colors.white,
            size: 38 * scale,
          ),
        ),
        SizedBox(height: 16 * scale),
        Text(
          'Boardest',
          style: GoogleFonts.outfit(
            fontSize: 32 * scale,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        SizedBox(height: 6 * scale),
        Text(
          '교실 계정 연결 (비밀번호 없음)',
          style: GoogleFonts.notoSansKr(
            fontSize: 14 * scale,
            color: const Color(0xFF94A1B2),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(double scale) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24 * scale),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF16161A).withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(24 * scale),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.07),
            ),
          ),
          padding: EdgeInsets.all(28 * scale),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 지역 선택
                _buildRegionDropdown(scale),
                SizedBox(height: 14 * scale),

                // 학교명
                _buildTextField(
                  controller: _schoolCtrl,
                  label: '학교명 (풀네임)',
                  hint: '양동중학교',
                  icon: Icons.location_city_rounded,
                  scale: scale,
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return '학교명을 입력해 주세요.';
                    if (!v.trim().endsWith('학교') &&
                        !v.trim().endsWith('학원') &&
                        v.trim().length < 3) {
                      return '학교 풀네임을 입력해 주세요. (예: 양동중학교)';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 14 * scale),

                // 학년 / 반 (가로 배치)
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _gradeCtrl,
                        label: '학년',
                        hint: '2',
                        icon: Icons.looks_one_rounded,
                        scale: scale,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(1),
                        ],
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (n == null || n < 1 || n > 6) return '1~6 입력';
                          return null;
                        },
                      ),
                    ),
                    SizedBox(width: 12 * scale),
                    Expanded(
                      child: _buildTextField(
                        controller: _classCtrl,
                        label: '반',
                        hint: '1',
                        icon: Icons.group_rounded,
                        scale: scale,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(2),
                        ],
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          final n = int.tryParse(v ?? '');
                          if (n == null || n < 1 || n > 30) return '1~30 입력';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 14 * scale),

                // 이메일 미리보기
                if (_previewEmail.isNotEmpty) ...[
                  _buildEmailPreview(scale),
                  SizedBox(height: 14 * scale),
                ],

                // 오류 메시지
                if (_errorMessage != null) ...[
                  SizedBox(height: 8 * scale),
                  _buildErrorBox(scale),
                ],

                SizedBox(height: 20 * scale),

                // 제출 버튼
                _buildSubmitButton(scale),
              ],
            ),
          ),
        ),
      ),
    );
  }



  Widget _buildRegionDropdown(double scale) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0E17).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(
          color: const Color(0xFF7F5AF0).withValues(alpha: 0.3),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 2 * scale),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _region,
          isExpanded: true,
          dropdownColor: const Color(0xFF16161A),
          style: GoogleFonts.notoSansKr(
            fontSize: 14 * scale,
            color: Colors.white,
          ),
          icon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: const Color(0xFF7F5AF0),
            size: 20 * scale,
          ),
          hint: Row(
            children: [
              Icon(Icons.place_rounded,
                  color: const Color(0xFF7F5AF0), size: 18 * scale),
              SizedBox(width: 8 * scale),
              Text('지역 선택',
                  style: GoogleFonts.notoSansKr(
                      fontSize: 14 * scale, color: const Color(0xFF94A1B2))),
            ],
          ),
          items: _kRegions.map((r) {
            return DropdownMenuItem<String>(
              value: r,
              child: Row(
                children: [
                  Icon(Icons.place_rounded,
                      color: const Color(0xFF7F5AF0), size: 16 * scale),
                  SizedBox(width: 8 * scale),
                  Text(r,
                      style: GoogleFonts.notoSansKr(
                          fontSize: 14 * scale, color: Colors.white)),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _region = val);
          },
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required double scale,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    void Function(String)? onChanged,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onChanged: onChanged,
      style: GoogleFonts.notoSansKr(fontSize: 14 * scale, color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon:
            Icon(icon, color: const Color(0xFF7F5AF0), size: 20 * scale),
        labelStyle: GoogleFonts.notoSansKr(
          fontSize: 13 * scale,
          color: const Color(0xFF94A1B2),
        ),
        hintStyle: GoogleFonts.notoSansKr(
          fontSize: 13 * scale,
          color: const Color(0xFF94A1B2).withValues(alpha: 0.5),
        ),
        filled: true,
        fillColor: const Color(0xFF0F0E17).withValues(alpha: 0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12 * scale),
          borderSide:
              BorderSide(color: const Color(0xFF7F5AF0).withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12 * scale),
          borderSide:
              BorderSide(color: const Color(0xFF7F5AF0).withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12 * scale),
          borderSide:
              const BorderSide(color: Color(0xFF7F5AF0), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12 * scale),
          borderSide: const BorderSide(color: Color(0xFFEF4565)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12 * scale),
          borderSide:
              const BorderSide(color: Color(0xFFEF4565), width: 1.5),
        ),
        errorStyle: GoogleFonts.notoSansKr(
          fontSize: 11 * scale,
          color: const Color(0xFFEF4565),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16 * scale,
          vertical: 14 * scale,
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool visible,
    required VoidCallback onToggle,
    required double scale,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: !visible,
      style: GoogleFonts.notoSansKr(fontSize: 14 * scale, color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(Icons.lock_rounded,
            color: const Color(0xFF7F5AF0), size: 20 * scale),
        suffixIcon: IconButton(
          icon: Icon(
            visible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            color: const Color(0xFF94A1B2),
            size: 20 * scale,
          ),
          onPressed: onToggle,
        ),
        labelStyle: GoogleFonts.notoSansKr(
          fontSize: 13 * scale,
          color: const Color(0xFF94A1B2),
        ),
        filled: true,
        fillColor: const Color(0xFF0F0E17).withValues(alpha: 0.6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12 * scale),
          borderSide:
              BorderSide(color: const Color(0xFF7F5AF0).withValues(alpha: 0.3)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12 * scale),
          borderSide:
              BorderSide(color: const Color(0xFF7F5AF0).withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12 * scale),
          borderSide:
              const BorderSide(color: Color(0xFF7F5AF0), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12 * scale),
          borderSide: const BorderSide(color: Color(0xFFEF4565)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12 * scale),
          borderSide:
              const BorderSide(color: Color(0xFFEF4565), width: 1.5),
        ),
        errorStyle: GoogleFonts.notoSansKr(
          fontSize: 11 * scale,
          color: const Color(0xFFEF4565),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16 * scale,
          vertical: 14 * scale,
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildEmailPreview(double scale) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 14 * scale,
        vertical: 10 * scale,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF2EC4B6).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10 * scale),
        border: Border.all(
          color: const Color(0xFF2EC4B6).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.email_rounded,
              color: const Color(0xFF2EC4B6), size: 16 * scale),
          SizedBox(width: 8 * scale),
          Expanded(
            child: Text(
              _previewEmail,
              style: GoogleFonts.robotoMono(
                fontSize: 12 * scale,
                color: const Color(0xFF2EC4B6),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBox(double scale) {
    return Container(
      padding: EdgeInsets.all(12 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4565).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10 * scale),
        border: Border.all(
          color: const Color(0xFFEF4565).withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded,
              color: const Color(0xFFEF4565), size: 16 * scale),
          SizedBox(width: 8 * scale),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.notoSansKr(
                fontSize: 12 * scale,
                color: const Color(0xFFEF4565),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton(double scale) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7F5AF0), Color(0xFF2EC4B6)],
        ),
        borderRadius: BorderRadius.circular(14 * scale),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7F5AF0).withValues(alpha: 0.4),
            blurRadius: 16 * scale,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isLoading ? null : _submit,
          borderRadius: BorderRadius.circular(14 * scale),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16 * scale),
            child: Center(
              child: _isLoading
                  ? SizedBox(
                      width: 20 * scale,
                      height: 20 * scale,
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'Boardest 연결 및 시작하기',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 16 * scale,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }


}

// ─── 보조 위젯 ──────────────────────────────────────────────────────────────

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final bool selected;
  final double scale;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.selected,
    required this.scale,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: EdgeInsets.symmetric(vertical: 10 * scale),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF7F5AF0) : Colors.transparent,
            borderRadius: BorderRadius.circular(10 * scale),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF7F5AF0).withValues(alpha: 0.35),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(
              fontSize: 14 * scale,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? Colors.white : const Color(0xFF94A1B2),
            ),
          ),
        ),
      ),
    );
  }
}
