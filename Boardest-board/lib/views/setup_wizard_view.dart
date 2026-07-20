import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/school.dart';
import '../models/app_settings.dart';
import '../services/comcigan_service.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../services/system_app_scanner.dart';
import 'timetable_view.dart';
import 'dashboard_view.dart';

class SetupWizardView extends StatefulWidget {
  final bool startWithStepList;
  const SetupWizardView({super.key, this.startWithStepList = false});

  @override
  State<SetupWizardView> createState() => _SetupWizardViewState();
}

class _SetupWizardViewState extends State<SetupWizardView> {
  late PageController _pageController;
  final ComciganService _comciganService = ComciganService();
  final StorageService _storageService = StorageService();
  final AuthService _authService = AuthService();

  int _currentStep = 0;
  bool _isLoading = true;
  String? _errorMessage;

  // Wizard state data
  String? _selectedRegion = '서울';
  School? _selectedSchool;
  TimetableResult? _timetableResult;
  int _selectedGrade = 1;
  int _selectedClass = 1;

  // Time Settings
  int _lessonDuration = 45;
  int _breakDuration = 10;
  int _lunchDuration = 50;
  int _lunchAfterPeriod = 4;
  String _firstPeriodStart = "08:40";
  String _morningAssemblyStart = "08:25";
  String _morningAssemblyEnd = "08:40";
  String _afternoonAssemblyStart = "16:10";
  String _afternoonAssemblyEnd = "16:30";
  int? _afternoonAssemblyAfterMinutes; // null=fixed time, non-null=N분 after last class
  bool _afternoonRelativeMode = false;
  int? _morningAssemblyBeforeMinutes = 15;
  bool _morningRelativeMode = true;
  // UI state for step-list re-entry mode
  bool _showStepList = false;

  final List<SystemApp> _selectedSystemApps = [
    SystemApp(name: '파일 탐색기', appId: Platform.isWindows ? 'explorer.exe' : 'com.android.documentsui'),
    SystemApp(name: 'PowerPoint', appId: Platform.isWindows ? 'powerpnt.exe' : 'com.microsoft.office.powerpoint'),
    SystemApp(name: '그림판', appId: Platform.isWindows ? 'mspaint.exe' : 'com.sec.android.app.writeonpdf'),
    SystemApp(name: 'YouTube', appId: 'https://www.youtube.com'),
  ];

  // Subject Textbook Image Mappings (subjectStem -> localPath)
  final Map<String, String> _textbookImages = {};

  // Teacher Name Mappings (teacherKey -> fullName)
  final Map<String, String> _teacherFullNames = {};
  final Map<String, TextEditingController> _teacherControllers = {};

  // UI state
  final TextEditingController _schoolSearchController = TextEditingController();
  final TextEditingController _jsonImportController = TextEditingController();
  final TextEditingController _connectionNameController = TextEditingController(text: 'My');
  final TextEditingController _classNicknameController = TextEditingController();
  final TextEditingController _authSchoolController = TextEditingController();
  final TextEditingController _authClassController = TextEditingController();
  final TextEditingController _authPasswordController = TextEditingController();
  
  // New Setup Wizard Integrated Auth controllers
  final TextEditingController _setupPasswordController = TextEditingController();
  final TextEditingController _setupPasswordConfirmController = TextEditingController();
  bool _isCheckingAccount = false;
  bool _accountExists = false;
  String? _authErrorMessage;
  bool _authCompleted = false;

  bool _isSignUpMode = false;
  String _authEmail = '';
  String _authPassword = '';
  bool _specialClassroomMode = false;
  final TextEditingController _specialTeacherController = TextEditingController();
  final TextEditingController _specialIdController = TextEditingController();
  List<School> _schoolSearchResults = [];
  bool _isSearchingSchool = false;
  String _selectedCafeteria = '1';
  AppSettings? _existingSettings;
  bool _isPasswordlessMode = true;

  // D-Day Event config variables
  List<DDayEvent> _ddayEvents = [];
  final TextEditingController _newDDayTitleController = TextEditingController();
  DateTime? _newDDayDate;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _showStepList = widget.startWithStepList;
    _loadExistingSettings();
  }

  Future<void> _loadExistingSettings() async {
    try {
      final settings = await _storageService.getSettings();
      setState(() {
        _existingSettings = settings;
        _selectedSchool = settings.selectedSchool;
        _selectedRegion = settings.selectedSchool?.region ?? '서울';
        _selectedGrade = settings.selectedGrade;
        _selectedClass = settings.selectedClass;
        _lessonDuration = settings.timeSettings.lessonDuration;
        _breakDuration = settings.timeSettings.breakDuration;
        _lunchDuration = settings.timeSettings.lunchDuration;
        _lunchAfterPeriod = settings.timeSettings.lunchAfterPeriod;
        _firstPeriodStart = settings.timeSettings.firstPeriodStart;
        _morningAssemblyStart = settings.timeSettings.morningAssemblyStart;
        _morningAssemblyEnd = settings.timeSettings.morningAssemblyEnd;
        _afternoonAssemblyStart = settings.timeSettings.afternoonAssemblyStart;
        _afternoonAssemblyEnd = settings.timeSettings.afternoonAssemblyEnd;
        _afternoonAssemblyAfterMinutes = settings.timeSettings.afternoonAssemblyAfterMinutes;
        _afternoonRelativeMode = settings.timeSettings.afternoonAssemblyAfterMinutes != null;
        _morningAssemblyBeforeMinutes = settings.timeSettings.morningAssemblyBeforeMinutes ?? 15;
        _morningRelativeMode = settings.timeSettings.morningAssemblyBeforeMinutes != null;
        if (_morningRelativeMode && _morningAssemblyEnd.contains(':')) {
          _morningAssemblyEnd = "15";
        }
        _textbookImages.addAll(settings.textbookImages);
        _connectionNameController.text = settings.connectionName;
        _classNicknameController.text = settings.classNickname;
        _authSchoolController.text = settings.connectionName;
        _authClassController.text = settings.classNickname;
        _specialClassroomMode = settings.specialClassroomMode;
        _specialTeacherController.text = settings.selectedTeacher;
        _specialIdController.text = settings.classNickname;
        _ddayEvents = List<DDayEvent>.from(settings.ddayEvents);
        
        var cafeteria = settings.cafeteriaNum;
        if (cafeteria.startsWith("급식실")) {
          cafeteria = cafeteria.replaceAll("급식실", "");
        }
        if (['1', '2', '3', '4', '5', '6', '7', '8', '9'].contains(cafeteria)) {
          _selectedCafeteria = cafeteria;
        } else {
          _selectedCafeteria = '1';
        }

        if (settings.selectedSystemApps.isNotEmpty) {
          _selectedSystemApps.clear();
          _selectedSystemApps.addAll(settings.selectedSystemApps);
        }
      });
      if (_selectedSchool != null) {
        final rawData = await _comciganService.fetchTimetableRaw(_selectedSchool!.code);
        final result = _comciganService.parseTimetable(rawData);
        setState(() {
          _timetableResult = result;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _schoolSearchController.dispose();
    _jsonImportController.dispose();
    _connectionNameController.dispose();
    _classNicknameController.dispose();
    _authSchoolController.dispose();
    _authClassController.dispose();
    _authPasswordController.dispose();
    _setupPasswordController.dispose();
    _setupPasswordConfirmController.dispose();
    _newDDayTitleController.dispose();
    _specialTeacherController.dispose();
    _specialIdController.dispose();
    for (var controller in _teacherControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }


  Future<void> _checkAndPrepareAuthStep() async {
    if (_selectedSchool == null) return;
    setState(() {
      _isCheckingAccount = true;
      _authErrorMessage = null;
      _setupPasswordController.clear();
      _setupPasswordConfirmController.clear();
    });
    
    final email = AuthService.buildClassEmail(
      school: _selectedSchool!.name,
      region: _selectedSchool!.region,
      grade: _selectedGrade,
      classNum: _selectedClass,
    );
    _authEmail = email;
    
    try {
      final exists = await _authService.checkAccountExists(email);
      setState(() {
        _accountExists = exists;
        _isCheckingAccount = false;
      });
    } catch (e) {
      setState(() {
        _accountExists = false;
        _isCheckingAccount = false;
        _authErrorMessage = '서버 연결에 실패했습니다: $e';
      });
    }
  }

  Future<bool> _handleAuthSubmit() async {
    final password = '!Flutter-app@Class#acc$_selectedGrade%$_selectedClass^${AuthService.koreanToEnglishKeyboard(_selectedSchool!.name)}';

    setState(() {
      _isLoading = true;
      _authErrorMessage = null;
    });

    try {
      if (!_accountExists) {
        // 회원가입 모드
        final err = await _authService.signupWithRawPassword(
          region: _selectedSchool!.region,
          school: _selectedSchool!.name,
          grade: _selectedGrade,
          classNum: _selectedClass,
          email: _authEmail,
          password: password,
        );

        if (err != null) {
          setState(() {
            _isLoading = false;
            _authErrorMessage = err;
          });
          return false;
        }
      } else {
        // 로그인 모드
        final err = await _authService.loginWithRawPassword(
          email: _authEmail,
          password: password,
        );

        if (err != null) {
          setState(() {
            _isLoading = false;
            _authErrorMessage = err;
          });
          return false;
        }
      }

      setState(() {
        _isLoading = false;
        _authCompleted = true;
      });
      return true;
    } catch (e) {
      setState(() {
        _isLoading = false;
        _authErrorMessage = '오류가 발생했습니다: $e';
      });
      return false;
    }
  }

  Future<void> _nextStep() async {
    // Step 0: 학교 정보 기입 validation 및 계정 준비
    if (_currentStep == 0) {
      if (_selectedSchool == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('학교를 먼저 검색하여 선택해 주세요.'),
            backgroundColor: Color(0xFFEF4565),
          ),
        );
        return;
      }
      
      // 계정 존재 여부 및 이메일 세팅
      await _checkAndPrepareAuthStep();
    }

    // Step 1: 계정 연결 및 로그인
    if (_currentStep == 1) {
      final success = await _handleAuthSubmit();
      if (!success) return; // 로그인 실패 시 stays on page 1
    }

    if (_currentStep < 4) {
      if (_pageController.hasClients) {
        await _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        setState(() {
          _currentStep++;
        });
      }
    } else {
      _finishSetup();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      if (_pageController.hasClients) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        setState(() {
          _currentStep--;
        });
      }
    }
  }

  // _firebaseAuthCall 제거됨: 새로운 AuthService 사용 (auth_view.dart 참조)

  Future<void> _pickAndImportJsonFile() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final fileContent = await File(path).readAsString();
        final decoded = json.decode(fileContent);

        int matchCount = 0;
        final teacherKeys = _getTeacherKeys();

        setState(() {
          for (final entry in teacherKeys) {
            final key = entry.key; // e.g. "수학홍길동"
            final rawTeacher = entry.value; // e.g. "홍길동"
            String? matchedName;

            if (decoded is Map) {
              // 1. Try subject+abbreviation key lookup
              if (decoded.containsKey(key)) {
                matchedName = decoded[key]?.toString().trim();
              }
              // 2. Try raw abbreviation key lookup (e.g. "홍길동" or "김현")
              else if (decoded.containsKey(rawTeacher)) {
                matchedName = decoded[rawTeacher]?.toString().trim();
              }
              // 3. Try searching for any key or value that contains rawTeacher
              else {
                for (final mapEntry in decoded.entries) {
                  final kStr = mapEntry.key.toString().trim();
                  final vStr = mapEntry.value.toString().trim();
                  if (kStr == rawTeacher || vStr == rawTeacher || kStr.startsWith(rawTeacher) || vStr.startsWith(rawTeacher)) {
                    matchedName = vStr.isNotEmpty ? vStr : kStr;
                    break;
                  }
                }
              }
            } else if (decoded is List) {
              // Try searching list for a name starting with rawTeacher
              for (final element in decoded) {
                final name = element.toString().trim();
                if (name.startsWith(rawTeacher) || name == rawTeacher) {
                  matchedName = name;
                  break;
                }
              }
            }

            if (matchedName != null && matchedName.isNotEmpty) {
              if (_teacherControllers.containsKey(key)) {
                _teacherControllers[key]!.text = matchedName;
              } else {
                _teacherControllers[key] = TextEditingController(text: matchedName);
              }
              _teacherFullNames[key] = matchedName;
              matchCount++;
            } else {
              if (_teacherControllers.containsKey(key)) {
                _teacherControllers[key]!.text = "";
              } else {
                _teacherControllers[key] = TextEditingController(text: "");
              }
              _teacherFullNames[key] = "";
            }
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('JSON 파일 매칭 완료: $matchCount개 과목 매칭 성공!'),
              backgroundColor: const Color(0xFF2CB67D),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('JSON 파일 파싱 중 오류 발생: $e'),
            backgroundColor: const Color(0xFFEF4565),
          ),
        );
      }
    }
  }

  // Fetch school info when selected in Step 1
  Future<void> _onSchoolSelected(School school) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final rawData = await _comciganService.fetchTimetableRaw(school.code);
      final result = _comciganService.parseTimetable(rawData);

      setState(() {
        _selectedSchool = school;
        _timetableResult = result;
        _selectedGrade = 1;
        _selectedClass = 1;
        _isLoading = false;
      });
      // stay on page 0 to select grade/class
    } catch (e) {
      debugPrint('[Boardest] School timetable load failed: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = '시간표 데이터를 불러오는 데 실패했습니다: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '학교 시간표 데이터를 불러오는 데 실패했습니다. ($e)',
              style: GoogleFonts.notoSansKr(color: Colors.white),
            ),
            backgroundColor: const Color(0xFFEF4565),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // Get unique subject keys from the school timetable (grade-prefixed for special rooms)
  List<String> _getUniqueSubjectKeys() {
    if (_timetableResult == null) return [];

    if (_specialClassroomMode) {
      final type = _existingSettings?.specialClassroomType ?? 0;
      if (type == 1) {
        // 전용 교사실: 이 교사가 가르치는 모든 학년과 과목
        final teacherName = _existingSettings?.selectedTeacher.replaceAll('*', '').trim() ?? '';
        if (teacherName.isEmpty) return [];

        final lessons = _timetableResult!.lessons
            .where((l) => l.teacher.replaceAll('*', '').trim() == teacherName)
            .toList();

        final keys = lessons
            .map((l) => '${l.grade}_${AppSettings.getSubjectStem(l.subject)}')
            .where((s) => !s.endsWith('_') && !s.contains('동아리') && !s.contains('자율'))
            .toSet()
            .toList();
        keys.sort();
        return keys;
      } else if (type == 2) {
        // 과목 특수실: 선택된 학년과 과목
        final subject = _existingSettings?.selectedSubject ?? '';
        final grade = _existingSettings?.selectedGrade ?? 1;
        if (subject.isEmpty) return [];
        final stem = AppSettings.getSubjectStem(subject);
        return ['${grade}_$stem'];
      } else {
        // 미교수 특수실
        return [];
      }
    } else {
      // 일반교실: 기존과 동일하지만 key 포맷을 simple subject stem으로 유지 (하위 호환성)
      final stems = _timetableResult!.lessons
          .where((l) => l.grade == _selectedGrade && l.classNum == _selectedClass)
          .map((l) => AppSettings.getSubjectStem(l.subject))
          .where((s) => s.isNotEmpty && !s.contains('동아리') && !s.contains('자율'))
          .toSet()
          .toList();
      stems.sort();
      return stems;
    }
  }

  String _displaySubjectName(String key) {
    if (key.contains('_')) {
      final parts = key.split('_');
      if (parts.length >= 2) {
        final grade = parts[0];
        final subject = parts.sublist(1).join('_');
        return '$grade학년 $subject';
      }
    }
    return key;
  }

  // Pick single image for a subject
  Future<void> _pickTextbookImage(String subjectStem) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final savedPath = await _saveImageLocally(path, subjectStem);
        setState(() {
          _textbookImages[subjectStem] = savedPath;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('이미지를 불러오지 못했습니다. $e')),
      );
    }
  }

  // Auto-match multiple picked images
  Future<void> _autoMatchImages() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );

      if (result != null) {
        final subjectStems = _getUniqueSubjectKeys();
        int matchCount = 0;

        for (final file in result.files) {
          if (file.path == null) continue;
          final fileName = p.basenameWithoutExtension(file.name);
          
          // Find matching subject stem
          for (final stem in subjectStems) {
            final display = _displaySubjectName(stem);
            final rawStem = stem.contains('_') ? stem.split('_').sublist(1).join('_') : stem;
            
            if (fileName.contains(display) || display.contains(fileName) ||
                fileName.contains(stem) || stem.contains(fileName) ||
                fileName.contains(rawStem) || rawStem.contains(fileName)) {
              final savedPath = await _saveImageLocally(file.path!, stem);
              _textbookImages[stem] = savedPath;
              matchCount++;
              break;
            }
          }
        }

        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('자동 매핑 완료: $matchCount개 과목 매칭')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('파일 매칭 중 오류 발생: $e')),
      );
    }
  }

  Future<String> _saveImageLocally(String srcPath, String subjectStem) async {
    final appDir = await getApplicationDocumentsDirectory();
    final textbookDir = Directory(p.join(appDir.path, 'textbooks'));
    if (!await textbookDir.exists()) {
      await textbookDir.create(recursive: true);
    }
    
    final fileExt = p.extension(srcPath);
    final destPath = p.join(textbookDir.path, '$subjectStem$fileExt');
    
    await File(srcPath).copy(destPath);
    return destPath;
  }

  // Unique teacher mappings for the selected grade and class
  List<MapEntry<String, String>> _getTeacherKeys() {
    return [];
  }

  // Auto-map teacher full names using parsed text/JSON
  void _importTeacherNames() {
    final input = _jsonImportController.text.trim();
    if (input.isEmpty) return;

    final teacherKeys = _getTeacherKeys();
    int matchCount = 0;
    
    dynamic decoded;
    bool isJsonParsed = false;
    try {
      decoded = json.decode(input);
      isJsonParsed = true;
    } catch (_) {
      // Treat as raw text
    }

    setState(() {
      for (final entry in teacherKeys) {
        final key = entry.key; // e.g. "수학홍길동"
        final rawTeacher = entry.value; // e.g. "홍길동"
        String? matchedName;

        if (isJsonParsed && decoded != null) {
          if (decoded is Map) {
            // 1. Try subject+abbreviation key lookup
            if (decoded.containsKey(key)) {
              matchedName = decoded[key]?.toString().trim();
            }
            // 2. Try raw abbreviation key lookup (e.g. "홍길동" or "김현")
            else if (decoded.containsKey(rawTeacher)) {
              matchedName = decoded[rawTeacher]?.toString().trim();
            }
            // 3. Try searching for any key or value that contains rawTeacher
            else {
              for (final mapEntry in decoded.entries) {
                final kStr = mapEntry.key.toString().trim();
                final vStr = mapEntry.value.toString().trim();
                if (kStr == rawTeacher || vStr == rawTeacher || kStr.startsWith(rawTeacher) || vStr.startsWith(rawTeacher)) {
                  matchedName = vStr.isNotEmpty ? vStr : kStr;
                  break;
                }
              }
            }
          } else if (decoded is List) {
            // Try searching list for a name starting with rawTeacher
            for (final element in decoded) {
              final name = element.toString().trim();
              if (name.startsWith(rawTeacher) || name == rawTeacher) {
                matchedName = name;
                break;
              }
            }
          }
        } else {
          // Non-JSON Fallback: split raw text by commas, newlines or spaces and find prefix match
          final rawParts = input.split(RegExp(r'[,\n\s]+'));
          for (final part in rawParts) {
            final name = part.trim();
            if (name.startsWith(rawTeacher) || name == rawTeacher) {
              matchedName = name;
              break;
            }
          }
        }

        if (matchedName != null && matchedName.isNotEmpty) {
          if (_teacherControllers.containsKey(key)) {
            _teacherControllers[key]!.text = matchedName;
          } else {
            _teacherControllers[key] = TextEditingController(text: matchedName);
          }
          _teacherFullNames[key] = matchedName;
          matchCount++;
        } else {
          if (isJsonParsed) {
            if (_teacherControllers.containsKey(key)) {
              _teacherControllers[key]!.text = "";
            } else {
              _teacherControllers[key] = TextEditingController(text: "");
            }
            _teacherFullNames[key] = "";
          }
        }
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('교사 실명 자동 매칭 완료: $matchCount명 매칭')),
    );
  }

  Future<void> _searchSchool() async {
    final query = _schoolSearchController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _isSearchingSchool = true;
    });
    try {
      final results = await _comciganService.searchSchool(query);
      setState(() {
        _schoolSearchResults = results;
        _isSearchingSchool = false;
      });
    } catch (e) {
      setState(() {
        _isSearchingSchool = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('학교 검색 중 오류가 발생했습니다: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = _existingSettings?.scaleFactor ?? 1.4;
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Stack(
        children: [
          // Aura Glowing Background
          Positioned(
            top: -100 * scale,
            left: -100 * scale,
            child: Container(
              width: 320 * scale,
              height: 320 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2EC4B6).withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            bottom: -80 * scale,
            right: -80 * scale,
            child: Container(
              width: 280 * scale,
              height: 280 * scale,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2CB67D).withValues(alpha: 0.08),
              ),
            ),
          ),
          IgnorePointer(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 80.0, sigmaY: 80.0),
              child: Container(color: Colors.transparent),
            ),
          ),
          
          SafeArea(
            child: Stack(
              children: [
                if (_existingSettings?.isSetupComplete == true && _showStepList)
                  _buildStepListScreen(scale)
                else
                  Column(
                    children: [
                      // Top Progress Indicator
                      Padding(
                        padding: EdgeInsets.all(20.0 * scale),
                        child: Row(
                          children: List.generate(6, (idx) {
                            final isActive = idx <= _currentStep;
                            return Expanded(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                height: 6 * scale,
                                margin: EdgeInsets.symmetric(horizontal: 4.0 * scale),
                                decoration: BoxDecoration(
                                  color: isActive
                                      ? const Color(0xFF2EC4B6)
                                      : const Color(0xFF16161A),
                                  borderRadius: BorderRadius.circular(4 * scale),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      
                      // Page Contents
                      Expanded(
                        child: PageView(
                          controller: _pageController,
                          physics: const NeverScrollableScrollPhysics(),
                          onPageChanged: (page) {
                            setState(() {
                              _currentStep = page;
                            });
                          },
                          children: [
                            _buildStep1SchoolAndGradeClass(), // Index 0 (Step 0)
                            _buildStep2AccountAuth(),          // Index 1 (Step 1)
                            _buildStep3TimeSettings(),         // Index 2 (Step 2)
                            _buildStep4Textbooks(),            // Index 3 (Step 3)
                            _buildStep6Done(),                 // Index 4 (Step 4)
                          ],
                        ),
                      ),


                      // Bottom Navigation
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24.0 * scale, vertical: 16.0 * scale),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (_currentStep > 0)
                              TextButton(
                                onPressed: _prevStep,
                                child: Text(
                                  '이전',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 16 * scale,
                                    color: const Color(0xFF94A1B2),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else
                              const SizedBox.shrink(),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2EC4B6),
                                padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 12 * scale),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * scale)),
                              ),
                              onPressed: _currentStep == 4 ? _finishSetup : _nextStep,
                              child: Text(
                                _currentStep == 4 ? '설정 완료' : '다음',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 16 * scale,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                
                // Glassmorphism Loading Overlay
                if (_isLoading)
                  Positioned.fill(
                    child: Container(
                      color: const Color(0xFF0F0E17).withValues(alpha: 0.7),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2EC4B6)),
                              ),
                              SizedBox(height: 20 * scale),
                              Text(
                                '학교 시간표 데이터를 가져오는 중...',
                                style: GoogleFonts.notoSansKr(
                                  color: Colors.white,
                                  fontSize: 15 * scale,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAutoSleepDialog(double scale) async {
    var enabled = _existingSettings?.autoSleepEnabled ?? false;
    await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            '자동 절전 모드',
            style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Platform.isWindows
                    ? '쉬는 시간·점심·하교 후 모니터를 끄고, 수업 교시가 시작되면 자동으로 켭니다. (Windows 전용)'
                    : '이 기능은 Windows PC에서만 사용할 수 있습니다.',
                style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12 * scale, height: 1.5),
              ),
              SizedBox(height: 12 * scale),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: enabled,
                activeThumbColor: const Color(0xFF2EC4B6),
                onChanged: (v) => setD(() => enabled = v),
                title: Text(
                  '자동 절전 사용',
                  style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * scale),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            TextButton(
              onPressed: () async {
                final updated = (_existingSettings ?? AppSettings()).copyWith(autoSleepEnabled: enabled);
                await _storageService.saveSettings(updated);
                if (mounted) setState(() => _existingSettings = updated);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: Text('저장', style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6))),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showMealCallConfigDialog(double scale) async {
    var connectionController = TextEditingController(text: _existingSettings?.connectionName ?? "My");
    var nicknameController = TextEditingController(text: _existingSettings?.classNickname ?? "");
    var cafeteria = _existingSettings?.cafeteriaNum ?? "1";
    if (cafeteria.startsWith("급식실")) {
      cafeteria = cafeteria.replaceAll("급식실", "");
    }
    if (!['1', '2', '3', '4', '5', '6', '7', '8', '9'].contains(cafeteria)) {
      cafeteria = "1";
    }
    var classOrder = _existingSettings?.mealCallClassOrder ?? "asc";
    
    await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            '급식 호출 설정',
            style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Firebase 연결 이름, 학급 닉네임 및 정렬 방식을 지정합니다.',
                style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12 * scale, height: 1.5),
              ),
              SizedBox(height: 16 * scale),
              Text(
                'Firebase 연결 이름',
                style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12 * scale, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8 * scale),
              TextField(
                controller: connectionController,
                style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13 * scale),
                decoration: InputDecoration(
                  hintText: '예: My, ClassA 등',
                  hintStyle: GoogleFonts.notoSansKr(color: Colors.white30, fontSize: 13 * scale),
                  filled: true,
                  fillColor: const Color(0xFF0F0E17),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
                ),
              ),
              SizedBox(height: 16 * scale),
              Text(
                '학급 닉네임',
                style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12 * scale, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8 * scale),
              TextField(
                controller: nicknameController,
                style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13 * scale),
                decoration: InputDecoration(
                  hintText: '예: 지후네반',
                  hintStyle: GoogleFonts.notoSansKr(color: Colors.white30, fontSize: 13 * scale),
                  filled: true,
                  fillColor: const Color(0xFF0F0E17),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
                ),
              ),
              SizedBox(height: 16 * scale),
              Text(
                '급식실 번호 (1~9)',
                style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12 * scale, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8 * scale),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12 * scale),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0E17),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: const Color(0xFF16161A),
                    value: ['1', '2', '3', '4', '5', '6', '7', '8', '9'].contains(cafeteria) ? cafeteria : '1',
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                    items: ['1', '2', '3', '4', '5', '6', '7', '8', '9']
                        .map((num) => DropdownMenuItem(
                              value: num,
                              child: Text('$num번 급식실', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * scale)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setD(() => cafeteria = v);
                    },
                  ),
                ),
              ),
              SizedBox(height: 16 * scale),
              Text(
                '호출 반 정렬 순서',
                style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12 * scale, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8 * scale),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: Center(child: Text('오름차순 (1>2>3)', style: GoogleFonts.notoSansKr(fontSize: 12 * scale, color: classOrder == 'asc' ? Colors.black : Colors.white70))),
                      selected: classOrder == 'asc',
                      selectedColor: const Color(0xFF2EC4B6),
                      backgroundColor: const Color(0xFF0F0E17),
                      onSelected: (val) {
                        if (val) setD(() => classOrder = 'asc');
                      },
                    ),
                  ),
                  SizedBox(width: 8 * scale),
                  Expanded(
                    child: ChoiceChip(
                      label: Center(child: Text('내림차순 (3>2>1)', style: GoogleFonts.notoSansKr(fontSize: 12 * scale, color: classOrder == 'desc' ? Colors.black : Colors.white70))),
                      selected: classOrder == 'desc',
                      selectedColor: const Color(0xFF2EC4B6),
                      backgroundColor: const Color(0xFF0F0E17),
                      onSelected: (val) {
                        if (val) setD(() => classOrder = 'desc');
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
            TextButton(
              onPressed: () async {
                final updated = (_existingSettings ?? AppSettings()).copyWith(
                  cafeteriaNum: cafeteria,
                  mealCallClassOrder: classOrder,
                  connectionName: connectionController.text.trim().isNotEmpty ? connectionController.text.trim() : 'My',
                  classNickname: nicknameController.text.trim(),
                );
                await _storageService.saveSettings(updated);
                if (mounted) setState(() => _existingSettings = updated);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: Text('저장', style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6))),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSpecialClassroomDialog(double scale) async {
    var enabled = _existingSettings?.specialClassroomMode ?? false;
    var teacherController = TextEditingController(text: _existingSettings?.selectedTeacher ?? "");
    
    await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: const Color(0xFF16161A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            '특수교실 전용 모드 설정',
            style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '특수교실 모드를 활성화하면 시간표와 급식 연동 기능이 화면에서 제거되고, 칠판과 수업 도구만 사용하는 심플한 런처로 바뀝니다.\n또한, PC에서 실행 시 화면 우측 40% 영역만 강제로 차지(최상위 고정)하여 좌측 60%의 바탕화면 및 인터넷 브라우저 등과 동시에 보며 수업할 수 있어 매우 유용합니다.',
                style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12 * scale, height: 1.6),
              ),
              SizedBox(height: 20 * scale),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '특수교실 모드 활성화',
                    style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13 * scale),
                  ),
                  Switch(
                    value: enabled,
                    activeColor: const Color(0xFF2EC4B6),
                    onChanged: (val) {
                      setD(() => enabled = val);
                    },
                  ),
                ],
              ),
              if (enabled) ...[
                SizedBox(height: 16 * scale),
                Text(
                  '담당 교사명/약칭 입력',
                  style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12 * scale, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8 * scale),
                TextField(
                  controller: teacherController,
                  style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 13 * scale),
                  decoration: InputDecoration(
                    hintText: '예: 홍길동 또는 홍길 (교과 시간표 매칭용)',
                    hintStyle: GoogleFonts.notoSansKr(color: Colors.white30, fontSize: 13 * scale),
                    filled: true,
                    fillColor: const Color(0xFF0F0E17),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white24),
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('취소', style: GoogleFonts.notoSansKr(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () async {
                final updated = (_existingSettings ?? AppSettings()).copyWith(
                  specialClassroomType: enabled ? 1 : 0,
                  selectedTeacher: teacherController.text.trim(),
                );
                await _storageService.saveSettings(updated);
                
                // Invoke Windows Native method channel to resize immediately!
                const channel = MethodChannel('com.boardest/launch_args');
                try {
                  await channel.invokeMethod('setSpecialClassroomMode', enabled ? 1 : 0);
                } catch (e) {
                  debugPrint('MethodChannel setSpecialClassroomMode failed: $e');
                }

                if (mounted) setState(() => _existingSettings = updated);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: Text('저장', style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setAndroidDefaultLauncher() async {
    const channel = MethodChannel('com.boardest/launch_args');
    try {
      await channel.invokeMethod('openHomeSettings');
    } catch (e) {
      debugPrint('Failed to open home settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('런처 설정 화면을 열 수 없습니다: $e')),
        );
      }
    }
  }

  // Step list screen: jumps to specific step from settings
  Widget _buildStepListScreen(double scale) {
    final steps = [
      (Icons.search_rounded, '학교 정보 기입', '학년, 반, 학교 정보 변경', true),
      (Icons.schedule_rounded, '급식실 및 일정 시간', '급식실 번호 및 조회·종례 시각', true),
      (Icons.menu_book_rounded, '교과서 이미지', '교과서 표지 사진 등록', true),
    ];
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 20 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.close_rounded, color: Colors.white54, size: 22 * scale),
                onPressed: () => Navigator.of(context).pop(true),
              ),
              SizedBox(width: 8 * scale),
              Text('어떤 항목을 수정할까요?', style: GoogleFonts.outfit(fontSize: 22 * scale, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          SizedBox(height: 8 * scale),
          Text('원하는 단계를 선택하면 바로 이동해요.', style: GoogleFonts.notoSansKr(fontSize: 12 * scale, color: Colors.white38)),
          SizedBox(height: 24 * scale),
          Expanded(
            child: ListView.separated(
              itemCount: steps.length,
              separatorBuilder: (_, __) => SizedBox(height: 10 * scale),
              itemBuilder: (context, index) {
                final step = steps[index];
                final goesToPage = step.$4;
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      int targetPage = 0;
                      if (step.$2 == '학교 정보 기입') targetPage = 0;
                      else if (step.$2 == '급식실 및 일정 시간') targetPage = 2;
                      else if (step.$2 == '교과서 이미지') targetPage = 3;

                      _pageController.dispose();
                      setState(() {
                        _showStepList = false;
                        _currentStep = targetPage;
                        _pageController = PageController(initialPage: targetPage);
                      });
                    },
                    borderRadius: BorderRadius.circular(14 * scale),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 16 * scale),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(14 * scale),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40 * scale,
                            height: 40 * scale,
                            decoration: BoxDecoration(
                              color: (goesToPage ? const Color(0xFF2EC4B6) : const Color(0xFF7B61FF)).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10 * scale),
                            ),
                            child: Icon(step.$1, color: goesToPage ? const Color(0xFF2EC4B6) : const Color(0xFF7B61FF), size: 20 * scale),
                          ),
                          SizedBox(width: 16 * scale),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(step.$2, style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 15 * scale, fontWeight: FontWeight.bold)),
                                Text(step.$3, style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 11 * scale)),
                              ],
                            ),
                          ),
                          Icon(goesToPage ? Icons.chevron_right_rounded : Icons.open_in_new_rounded, color: Colors.white24, size: 20 * scale),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep0SpecialClassroom() {
    final scale = _existingSettings?.scaleFactor ?? 1.4;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.0 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 20 * scale),
          Text(
            '특별실 전용 모드 설정',
            style: GoogleFonts.outfit(
              fontSize: 28 * scale,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 8 * scale),
          Text(
            '시간표와 급식 연동 기능 없이 칠판과 수업 도구만 사용하는 심플한 런처로 설정합니다.',
            style: GoogleFonts.notoSansKr(
              fontSize: 13 * scale,
              color: const Color(0xFF94A1B2),
            ),
          ),
          SizedBox(height: 24 * scale),
          Container(
            padding: EdgeInsets.all(16 * scale),
            decoration: BoxDecoration(
              color: const Color(0xFF16161A).withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16 * scale),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '특별실 모드 활성화',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 16 * scale,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 4 * scale),
                          Text(
                            '활성화 시 학교 검색, 시간 설정 등의 복잡한 단계가 생략되고 즉시 완료할 수 있습니다.',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12 * scale,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _specialClassroomMode,
                      activeColor: const Color(0xFF2EC4B6),
                      onChanged: (val) {
                        setState(() {
                          _specialClassroomMode = val;
                        });
                      },
                    ),
                  ],
                ),
                if (_specialClassroomMode) ...[
                  SizedBox(height: 16 * scale),
                  Text(
                    '특별실 영문 ID (교실 로그인 및 Firebase 식별용)',
                    style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13 * scale, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8 * scale),
                  TextField(
                    controller: _specialIdController,
                    style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * scale),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                    ],
                    decoration: InputDecoration(
                      hintText: '예: science, english, art (영문/숫자만)',
                      hintStyle: GoogleFonts.notoSansKr(color: Colors.white30, fontSize: 14 * scale),
                      filled: true,
                      fillColor: const Color(0xFF0F0E17),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
                    ),
                  ),
                  SizedBox(height: 16 * scale),
                  Text(
                    '담당 교사 약칭 입력 (컴시간 기준 이름 앞 2글자)',
                    style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13 * scale, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8 * scale),
                  TextField(
                    controller: _specialTeacherController,
                    style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * scale),
                    decoration: InputDecoration(
                      hintText: '예: 홍길, 김철 등 (실명 시간표 대조용)',
                      hintStyle: GoogleFonts.notoSansKr(color: Colors.white30, fontSize: 14 * scale),
                      filled: true,
                      fillColor: const Color(0xFF0F0E17),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
                    ),
                  ),
                  SizedBox(height: 16 * scale),
                  Container(
                    padding: EdgeInsets.all(12 * scale),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0E17),
                      borderRadius: BorderRadius.circular(8 * scale),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Color(0xFF2EC4B6)),
                        SizedBox(width: 8 * scale),
                        Expanded(
                          child: Text(
                            'PC 실행 시 화면 우측 40% 영역만 차지하도록 고정됩니다.\n바탕화면 및 다른 프로그램과 분할하여 편리하게 이용 가능합니다.',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 11 * scale,
                              color: const Color(0xFF2EC4B6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 24 * scale),
          Container(
            padding: EdgeInsets.all(16 * scale),
            decoration: BoxDecoration(
              color: const Color(0xFF16161A).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16 * scale),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '💡 특별실 모드 주요 기능',
                  style: GoogleFonts.notoSansKr(fontSize: 14 * scale, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                SizedBox(height: 8 * scale),
                _buildBulletPoint('시간표 및 급식실 안내 제거로 복잡하지 않은 구성', scale),
                _buildBulletPoint('언제나 즉시 사용 가능한 전자 칠판 및 판서 도구', scale),
                _buildBulletPoint('수업 중 영상 플레이어 및 PPT 파일 제어 연동 기능', scale),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulletPoint(String text, double scale) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.0 * scale),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6), fontSize: 13 * scale)),
          Expanded(child: Text(text, style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12 * scale))),
        ],
      ),
    );
  }

  Widget _buildStep1SchoolAndGradeClass() {
    final scale = _existingSettings?.scaleFactor ?? 1.4;
    final int classCount = _timetableResult?.classCounts[_selectedGrade] ?? 15; // 디폴트 15개 반

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.0 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 20 * scale),
          Text(
            '학교 정보 기입',
            style: GoogleFonts.outfit(
              fontSize: 28 * scale,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 8 * scale),
          Text(
            '학교명을 입력해 검색한 후, 학년과 반을 기입하세요.',
            style: GoogleFonts.notoSansKr(
              fontSize: 13 * scale,
              color: const Color(0xFF94A1B2),
            ),
          ),
          SizedBox(height: 16 * scale),

          if (_selectedSchool == null) ...[
            // 학교 검색 창
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 48 * scale,
                    child: TextField(
                      controller: _schoolSearchController,
                      style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * scale),
                      decoration: InputDecoration(
                        hintText: '학교명을 입력하세요 (예: 양동중학교)',
                        hintStyle: GoogleFonts.notoSansKr(color: const Color(0xFF72757E), fontSize: 14 * scale),
                        filled: true,
                        fillColor: const Color(0xFF16161A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12 * scale), borderSide: BorderSide.none),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
                      ),
                      onSubmitted: (_) => _searchSchool(),
                    ),
                  ),
                ),
                SizedBox(width: 12 * scale),
                Container(
                  height: 48 * scale,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2EC4B6),
                      padding: EdgeInsets.symmetric(horizontal: 20 * scale),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12 * scale)),
                    ),
                    onPressed: _searchSchool,
                    child: Icon(Icons.search, color: Colors.white, size: 20 * scale),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12 * scale),
            Expanded(
              child: _isSearchingSchool
                  ? const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2EC4B6))))
                  : _schoolSearchResults.isEmpty
                      ? Center(child: Text('검색 결과가 없습니다.', style: GoogleFonts.notoSansKr(color: const Color(0xFF72757E), fontSize: 14 * scale)))
                      : ListView.builder(
                          itemCount: _schoolSearchResults.length,
                          itemBuilder: (context, index) {
                            final school = _schoolSearchResults[index];
                            return Container(
                              margin: EdgeInsets.only(bottom: 8 * scale),
                              decoration: BoxDecoration(
                                color: const Color(0xFF16161A).withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(12 * scale),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                              ),
                              child: ListTile(
                                title: Text(school.name, style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15 * scale)),
                                subtitle: Text('${school.region} | 코드: ${school.code}', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11 * scale)),
                                trailing: Icon(Icons.check_circle_outline, color: const Color(0xFF2EC4B6), size: 20 * scale),
                                onTap: () => _onSchoolSelected(school),
                              ),
                            );
                          },
                        ),
            ),
          ] else ...[
            // 이미 학교가 선택된 상태
            Container(
              padding: EdgeInsets.all(12 * scale),
              decoration: BoxDecoration(
                color: const Color(0xFF2EC4B6).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12 * scale),
                border: Border.all(color: const Color(0xFF2EC4B6).withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_selectedSchool!.name, style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16 * scale)),
                        SizedBox(height: 2 * scale),
                        Text('${_selectedSchool!.region} | 코드: ${_selectedSchool!.code}', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 12 * scale)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedSchool = null;
                        _schoolSearchResults.clear();
                      });
                    },
                    child: Text('변경', style: GoogleFonts.notoSansKr(color: const Color(0xFFEF4565), fontWeight: FontWeight.bold, fontSize: 14 * scale)),
                  ),
                ],
              ),
            ),
            if (!_specialClassroomMode) ...[
              SizedBox(height: 20 * scale),
              Text('학년 선택', style: GoogleFonts.notoSansKr(fontSize: 15 * scale, fontWeight: FontWeight.bold, color: Colors.white70)),
              SizedBox(height: 8 * scale),
              Row(
                children: List.generate(3, (index) {
                  final grade = index + 1;
                  final isSelected = _selectedGrade == grade;
                  return Padding(
                    padding: EdgeInsets.only(right: 12.0 * scale),
                    child: ChoiceChip(
                      label: Text('$grade학년', style: GoogleFonts.notoSansKr(color: isSelected ? Colors.black : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13 * scale)),
                      selected: isSelected,
                      selectedColor: const Color(0xFF2EC4B6),
                      backgroundColor: const Color(0xFF16161A),
                      checkmarkColor: Colors.black,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedGrade = grade;
                            _selectedClass = 1;
                          });
                        }
                      },
                    ),
                  );
                }),
              ),
              SizedBox(height: 20 * scale),
              Text('반 기입', style: GoogleFonts.notoSansKr(fontSize: 15 * scale, fontWeight: FontWeight.bold, color: Colors.white70)),
              SizedBox(height: 8 * scale),
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    crossAxisSpacing: 8 * scale,
                    mainAxisSpacing: 8 * scale,
                    childAspectRatio: 1.3,
                  ),
                  itemCount: classCount > 0 ? classCount : 15,
                  itemBuilder: (context, index) {
                    final classNum = index + 1;
                    final isSelected = _selectedClass == classNum;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedClass = classNum;
                        });
                      },
                      borderRadius: BorderRadius.circular(10 * scale),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF2EC4B6) : const Color(0xFF16161A),
                          borderRadius: BorderRadius.circular(10 * scale),
                          border: Border.all(color: isSelected ? const Color(0xFF00F5D4) : Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: Text(
                          '$classNum반',
                          style: GoogleFonts.notoSansKr(fontSize: 14 * scale, fontWeight: FontWeight.bold, color: isSelected ? Colors.black : Colors.white70),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ] else ...[
              const Spacer(),
              Center(
                child: Text(
                  '특별실 모드가 활성화되어 학년/반 선택 단계를 생략합니다.\n상단 학교 정보만 확인하고 다음 단계로 진행하세요.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6), fontSize: 13 * scale, height: 1.6),
                ),
              ),
              const Spacer(),
            ]
          ]
        ],
      ),
    );
  }

  Widget _buildStep2AccountAuth() {
    final scale = _existingSettings?.scaleFactor ?? 1.4;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.0 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 20 * scale),
          Text(
            '임시 계정 연결 (비밀번호 없음)',
            style: GoogleFonts.outfit(
              fontSize: 28 * scale,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 8 * scale),
          Text(
            '전자칠판용 임시 계정을 수립하여 복잡한 로그인 없이 즉시 연결합니다.',
            style: GoogleFonts.notoSansKr(fontSize: 13 * scale, color: const Color(0xFF94A1B2)),
          ),
          SizedBox(height: 20 * scale),

          // 이메일 주소 카드
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16 * scale),
            decoration: BoxDecoration(
              color: const Color(0xFF16161A).withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16 * scale),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('자동 생성된 임시 계정 ID', style: GoogleFonts.notoSansKr(fontSize: 11 * scale, color: Colors.white38)),
                SizedBox(height: 6 * scale),
                SelectableText(
                  _authEmail.isNotEmpty ? _authEmail : 'Class.${_selectedGrade}${_selectedClass.toString().padLeft(2, '0')}@${_selectedSchool?.name ?? "학교"}.${_selectedSchool?.region ?? "지역"}.nopw.bst',
                  style: GoogleFonts.outfit(color: const Color(0xFF00F5D4), fontSize: 18 * scale, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          SizedBox(height: 20 * scale),

          if (_isCheckingAccount) ...[
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2EC4B6))),
                    SizedBox(height: 16),
                    Text('임시 계정 유무를 조회하고 있습니다...', style: TextStyle(color: Colors.white60)),
                  ],
                ),
              ),
            )
          ] else ...[
            // 계정 확인 완료
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
              decoration: BoxDecoration(
                color: _accountExists 
                    ? const Color(0xFF2EC4B6).withValues(alpha: 0.1) 
                    : const Color(0xFF7F5AF0).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10 * scale),
              ),
              child: Row(
                children: [
                  Icon(
                    _accountExists ? Icons.login : Icons.person_add_alt_1,
                    color: _accountExists ? const Color(0xFF2EC4B6) : const Color(0xFF7F5AF0),
                    size: 20 * scale,
                  ),
                  SizedBox(width: 8 * scale),
                  Expanded(
                     child: Text(
                       _accountExists 
                           ? '등록된 임시 계정이 확인되었습니다.' 
                           : '신규 임시 계정입니다! 다음을 누르면 연결됩니다.',
                       style: GoogleFonts.notoSansKr(
                         color: _accountExists ? const Color(0xFF2EC4B6) : const Color(0xFF7F5AF0),
                         fontWeight: FontWeight.bold,
                         fontSize: 12 * scale,
                       ),
                     ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 20 * scale),

            if (_authErrorMessage != null) ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12 * scale),
                margin: EdgeInsets.only(bottom: 16 * scale),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4565).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10 * scale),
                  border: Border.all(color: const Color(0xFFEF4565).withValues(alpha: 0.4)),
                ),
                child: Text(
                  _authErrorMessage!,
                  style: GoogleFonts.notoSansKr(color: const Color(0xFFEF4565), fontSize: 13 * scale, fontWeight: FontWeight.bold),
                ),
              ),
            ],

            Container(
              width: double.infinity,
              padding: EdgeInsets.all(16 * scale),
              decoration: BoxDecoration(
                color: const Color(0xFF2EC4B6).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12 * scale),
                border: Border.all(color: const Color(0xFF2EC4B6).withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.offline_bolt, color: const Color(0xFF2EC4B6), size: 24 * scale),
                  SizedBox(width: 12 * scale),
                  Expanded(
                    child: Text(
                      '이 계정은 임시 계정(nopw.bst)이며 비밀번호가 없습니다.\n교사 본계정은 이 화면을 통해 로그인할 수 없으며,\n"다음" 버튼 클릭 시 안전하게 즉시 자동 임시 연결됩니다.',
                      style: GoogleFonts.notoSansKr(color: const Color(0xFF2EC4B6), fontSize: 13 * scale, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep3TimeSettings() {
    final scale = _existingSettings?.scaleFactor ?? 1.4;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.0 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 20 * scale),
          Text(
            '급식실 및 하루 일정 시간 설정',
            style: GoogleFonts.outfit(
              fontSize: 28 * scale,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 8 * scale),
          Text(
            '학급 급식 호출 연동과 수업 시간표 운영에 필요한 기준 시간들을 설정합니다.',
            style: GoogleFonts.notoSansKr(
              fontSize: 13 * scale,
              color: const Color(0xFF94A1B2),
            ),
          ),
          SizedBox(height: 16 * scale),
          Expanded(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // 1. 급식실 번호 선택
                Text('급식실 번호 선택', style: GoogleFonts.notoSansKr(fontSize: 15 * scale, fontWeight: FontWeight.bold, color: Colors.white70)),
                SizedBox(height: 8 * scale),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16 * scale),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A),
                    borderRadius: BorderRadius.circular(12 * scale),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      dropdownColor: const Color(0xFF16161A),
                      value: ['1', '2', '3', '4', '5', '6', '7', '8', '9'].contains(_selectedCafeteria) ? _selectedCafeteria : '1',
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
                      items: ['1', '2', '3', '4', '5', '6', '7', '8', '9']
                          .map((num) => DropdownMenuItem(
                                value: num,
                                child: Text('$num번 급식실', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * scale)),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _selectedCafeteria = v;
                          });
                        }
                      },
                    ),
                  ),
                ),
                SizedBox(height: 24 * scale),

                // 2. 수업 및 휴식 시간 설정
                Text('수업 및 휴식 시간 설정', style: GoogleFonts.notoSansKr(fontSize: 15 * scale, fontWeight: FontWeight.bold, color: Colors.white70)),
                SizedBox(height: 12 * scale),
                _buildDurationCard('수업 시간', _lessonDuration, (val) => setState(() => _lessonDuration = val), scale),
                SizedBox(height: 12 * scale),
                _buildDurationCard('쉬는 시간', _breakDuration, (val) => setState(() => _breakDuration = val), scale),
                SizedBox(height: 12 * scale),
                _buildDurationCard('점심 시간', _lunchDuration, (val) => setState(() => _lunchDuration = val), scale),
                SizedBox(height: 12 * scale),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12 * scale),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '점심시간 시작 교시',
                        style: GoogleFonts.notoSansKr(
                          color: Colors.white,
                          fontSize: 14 * scale,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: Icon(Icons.remove_circle_outline, color: const Color(0xFF2EC4B6), size: 22 * scale),
                            onPressed: () => setState(() => _lunchAfterPeriod = _lunchAfterPeriod > 1 ? _lunchAfterPeriod - 1 : 1),
                          ),
                          Container(
                            width: 60 * scale,
                            alignment: Alignment.center,
                            child: Text(
                              '$_lunchAfterPeriod교시 후',
                              style: GoogleFonts.notoSansKr(
                                color: Colors.white,
                                fontSize: 14 * scale,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.add_circle_outline, color: const Color(0xFF2EC4B6), size: 22 * scale),
                            onPressed: () => setState(() => _lunchAfterPeriod = _lunchAfterPeriod < 7 ? _lunchAfterPeriod + 1 : 7),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24 * scale),

                // 3. 하루 일정 시작 시각 설정
                Text('기준 시각 설정', style: GoogleFonts.notoSansKr(fontSize: 15 * scale, fontWeight: FontWeight.bold, color: Colors.white70)),
                SizedBox(height: 12 * scale),
                _buildTimePickerCard('1교시 시작 시각', _firstPeriodStart, (val) => setState(() => _firstPeriodStart = val), scale),
                SizedBox(height: 12 * scale),

                // 4. 아침 조회 시각 설정
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 14 * scale),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12 * scale),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('조회 시각 설정', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * scale, fontWeight: FontWeight.w500)),
                          Row(
                            children: [
                              Text('수업 시작 N분 전', style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12 * scale)),
                              SizedBox(width: 8 * scale),
                              Switch(
                                value: _morningRelativeMode,
                                activeColor: const Color(0xFF2EC4B6),
                                onChanged: (v) => setState(() => _morningRelativeMode = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 12 * scale),
                      if (_morningRelativeMode) ...[
                        Text('1교시 수업 시작 몇 분 전에 조회를 시작할까요?', style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12 * scale)),
                        SizedBox(height: 10 * scale),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.remove_circle_outline, color: const Color(0xFF2EC4B6), size: 22 * scale),
                              onPressed: () => setState(() => _morningAssemblyBeforeMinutes = ((_morningAssemblyBeforeMinutes ?? 15) - 5).clamp(5, 60)),
                            ),
                            Container(
                              width: 80 * scale,
                              alignment: Alignment.center,
                              child: Text(
                                '${_morningAssemblyBeforeMinutes ?? 15}분 전',
                                style: GoogleFonts.outfit(color: Colors.white, fontSize: 16 * scale, fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.add_circle_outline, color: const Color(0xFF2EC4B6), size: 22 * scale),
                              onPressed: () => setState(() => _morningAssemblyBeforeMinutes = ((_morningAssemblyBeforeMinutes ?? 15) + 5).clamp(5, 60)),
                            ),
                            Text('(조회 진행)', style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 11 * scale)),
                            SizedBox(width: 8 * scale),
                            IconButton(
                              icon: Icon(Icons.remove_circle_outline, color: const Color(0xFF2CB67D), size: 22 * scale),
                              onPressed: () => setState(() {
                                final dur = int.tryParse(_morningAssemblyEnd) ?? 15;
                                final newDur = (dur - 5).clamp(5, 60);
                                _morningAssemblyEnd = newDur.toString();
                              }),
                            ),
                            Text(_morningAssemblyEnd.contains(':') ? '15분' : '${_morningAssemblyEnd}분',
                                style: GoogleFonts.outfit(color: const Color(0xFF2CB67D), fontSize: 14 * scale, fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: Icon(Icons.add_circle_outline, color: const Color(0xFF2CB67D), size: 22 * scale),
                              onPressed: () => setState(() {
                                final dur = int.tryParse(_morningAssemblyEnd) ?? 15;
                                final newDur = (dur + 5).clamp(5, 60);
                                _morningAssemblyEnd = newDur.toString();
                              }),
                            ),
                          ],
                        ),
                      ] else ...[
                        _buildTimePickerCard('아침 조회 시작 시각', _morningAssemblyStart, (val) => setState(() => _morningAssemblyStart = val), scale),
                        SizedBox(height: 8 * scale),
                        _buildTimePickerCard('아침 조회 종료 시각', _morningAssemblyEnd, (val) => setState(() => _morningAssemblyEnd = val), scale),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 12 * scale),

                // 5. 종례 시각 설정
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 14 * scale),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161A).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12 * scale),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('종례 시각 설정', style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * scale, fontWeight: FontWeight.w500)),
                          Row(
                            children: [
                              Text('수업 종료 N분 전', style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12 * scale)),
                              SizedBox(width: 8 * scale),
                              Switch(
                                value: _afternoonRelativeMode,
                                activeColor: const Color(0xFF2EC4B6),
                                onChanged: (v) => setState(() => _afternoonRelativeMode = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 12 * scale),
                      if (_afternoonRelativeMode) ...[
                        Text('마지막 수업 종료 몇 분 전에 종례를 시작할까요?', style: GoogleFonts.notoSansKr(color: Colors.white54, fontSize: 12 * scale)),
                        SizedBox(height: 10 * scale),
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.remove_circle_outline, color: const Color(0xFF2EC4B6), size: 22 * scale),
                              onPressed: () => setState(() => _afternoonAssemblyAfterMinutes = ((_afternoonAssemblyAfterMinutes ?? 10) - 5).clamp(0, 60)),
                            ),
                            Container(
                              width: 80 * scale,
                              alignment: Alignment.center,
                              child: Text(
                                '${_afternoonAssemblyAfterMinutes ?? 10}분 전',
                                style: GoogleFonts.outfit(color: Colors.white, fontSize: 16 * scale, fontWeight: FontWeight.bold),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.add_circle_outline, color: const Color(0xFF2EC4B6), size: 22 * scale),
                              onPressed: () => setState(() => _afternoonAssemblyAfterMinutes = ((_afternoonAssemblyAfterMinutes ?? 10) + 5).clamp(0, 60)),
                            ),
                            Text('(종례 길이)', style: GoogleFonts.notoSansKr(color: Colors.white38, fontSize: 11 * scale)),
                            SizedBox(width: 8 * scale),
                            IconButton(
                              icon: Icon(Icons.remove_circle_outline, color: const Color(0xFF2CB67D), size: 22 * scale),
                              onPressed: () => setState(() {
                                final dur = int.tryParse(_afternoonAssemblyEnd) ?? 20;
                                final newDur = (dur - 5).clamp(5, 60);
                                _afternoonAssemblyEnd = newDur.toString();
                              }),
                            ),
                            Text(_afternoonAssemblyEnd.contains(':') ? _afternoonAssemblyEnd : '${_afternoonAssemblyEnd}분',
                                style: GoogleFonts.outfit(color: const Color(0xFF2CB67D), fontSize: 14 * scale, fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: Icon(Icons.add_circle_outline, color: const Color(0xFF2CB67D), size: 22 * scale),
                              onPressed: () => setState(() {
                                final dur = int.tryParse(_afternoonAssemblyEnd) ?? 20;
                                final newDur = (dur + 5).clamp(5, 60);
                                _afternoonAssemblyEnd = newDur.toString();
                              }),
                            ),
                          ],
                        ),
                      ] else ...[
                        _buildTimePickerCard('종례 시작 시각', _afternoonAssemblyStart, (val) => setState(() => _afternoonAssemblyStart = val), scale),
                        SizedBox(height: 8 * scale),
                        _buildTimePickerCard('종례 종료 시각', _afternoonAssemblyEnd, (val) => setState(() => _afternoonAssemblyEnd = val), scale),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 24 * scale),
                _buildDDayConfigSection(scale),
                SizedBox(height: 20 * scale),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDDayConfigSection(double scale) {
    return Container(
      padding: EdgeInsets.all(16 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A).withOpacity(0.4),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.flag_rounded, color: const Color(0xFF2EC4B6), size: 18 * scale),
              SizedBox(width: 8 * scale),
              Text(
                'D-Day 이벤트 설정',
                style: GoogleFonts.notoSansKr(
                  color: Colors.white,
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: 6 * scale),
          Text(
            '런처 메인 화면에 표시할 중요한 학급 D-Day 일정을 등록 및 관리합니다.',
            style: GoogleFonts.notoSansKr(
              color: Colors.white54,
              fontSize: 11 * scale,
            ),
          ),
          SizedBox(height: 16 * scale),

          // D-Day List
          if (_ddayEvents.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12 * scale),
              child: Center(
                child: Text(
                  '등록된 D-Day 이벤트가 없습니다.',
                  style: GoogleFonts.notoSansKr(color: Colors.white30, fontSize: 13 * scale),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _ddayEvents.length,
              itemBuilder: (context, index) {
                final event = _ddayEvents[index];
                final dateStr = '${event.date.year}-${event.date.month.toString().padLeft(2, '0')}-${event.date.day.toString().padLeft(2, '0')}';
                final daysLeft = event.date.difference(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)).inDays;
                final ddayStr = daysLeft == 0
                    ? 'D-Day'
                    : (daysLeft > 0 ? 'D-$daysLeft' : 'D+${-daysLeft}');

                return Container(
                  margin: EdgeInsets.only(bottom: 8 * scale),
                  padding: EdgeInsets.symmetric(horizontal: 12 * scale, vertical: 8 * scale),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.02),
                    borderRadius: BorderRadius.circular(8 * scale),
                    border: Border.all(color: Colors.white.withOpacity(0.04)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2EC4B6).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6 * scale),
                        ),
                        child: Text(
                          ddayStr,
                          style: GoogleFonts.outfit(
                            color: const Color(0xFF2EC4B6),
                            fontSize: 12 * scale,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      SizedBox(width: 12 * scale),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              style: GoogleFonts.notoSansKr(
                                color: Colors.white,
                                fontSize: 13 * scale,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              dateStr,
                              style: GoogleFonts.outfit(
                                color: Colors.white38,
                                fontSize: 11 * scale,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline_rounded, color: const Color(0xFFEF4565), size: 18 * scale),
                        onPressed: () {
                          setState(() {
                            _ddayEvents.removeAt(index);
                          });
                        },
                      ),
                    ],
                  ),
                );
              },
            ),

          SizedBox(height: 16 * scale),
          const Divider(color: Colors.white10),
          SizedBox(height: 8 * scale),

          // Add New D-Day Form
          Text(
            '새 D-Day 추가',
            style: GoogleFonts.notoSansKr(
              color: Colors.white70,
              fontSize: 13 * scale,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 10 * scale),
          Row(
            children: [
              Expanded(
                flex: 4,
                child: Container(
                  height: 38 * scale,
                  padding: EdgeInsets.symmetric(horizontal: 10 * scale),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F0E17),
                    borderRadius: BorderRadius.circular(8 * scale),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: TextField(
                    controller: _newDDayTitleController,
                    style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 12 * scale),
                    decoration: InputDecoration(
                      hintText: '이벤트 제목 (예: 지필평가)',
                      hintStyle: GoogleFonts.notoSansKr(color: Colors.white24, fontSize: 12 * scale),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 10 * scale),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8 * scale),
              Expanded(
                flex: 3,
                child: InkWell(
                  onTap: () async {
                    final today = DateTime.now();
                    final selectedDate = await showDatePicker(
                      context: context,
                      initialDate: _newDDayDate ?? today,
                      firstDate: today.subtract(const Duration(days: 365)),
                      lastDate: today.add(const Duration(days: 365 * 5)),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: Color(0xFF2EC4B6),
                              onPrimary: Colors.black,
                              surface: Color(0xFF16161A),
                              onSurface: Colors.white,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (selectedDate != null) {
                      setState(() {
                        _newDDayDate = selectedDate;
                      });
                    }
                  },
                  child: Container(
                    height: 38 * scale,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0E17),
                      borderRadius: BorderRadius.circular(8 * scale),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Text(
                      _newDDayDate == null
                          ? '날짜 선택'
                          : '${_newDDayDate!.year}-${_newDDayDate!.month.toString().padLeft(2, '0')}-${_newDDayDate!.day.toString().padLeft(2, '0')}',
                      style: GoogleFonts.notoSansKr(
                        color: _newDDayDate == null ? Colors.white38 : Colors.white70,
                        fontSize: 12 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8 * scale),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2EC4B6),
                  foregroundColor: Colors.black,
                  padding: EdgeInsets.symmetric(horizontal: 16 * scale),
                  minimumSize: Size(0, 38 * scale),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * scale)),
                ),
                onPressed: () {
                  final title = _newDDayTitleController.text.trim();
                  final date = _newDDayDate;
                  if (title.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('제목을 입력하세요.')),
                    );
                    return;
                  }
                  if (date == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('날짜를 선택하세요.')),
                    );
                    return;
                  }
                  setState(() {
                    _ddayEvents.add(DDayEvent(title: title, date: date));
                    _newDDayTitleController.clear();
                    _newDDayDate = null;
                  });
                },
                child: Text(
                  '추가',
                  style: GoogleFonts.notoSansKr(fontSize: 12 * scale, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDurationCard(String label, int value, Function(int) onChanged, double scale) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.notoSansKr(
              color: Colors.white,
              fontSize: 14 * scale,
              fontWeight: FontWeight.w500,
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.remove_circle_outline, color: const Color(0xFF2EC4B6), size: 22 * scale),
                onPressed: () => onChanged(value > 5 ? value - 5 : value),
              ),
              Container(
                width: 50 * scale,
                alignment: Alignment.center,
                child: Text(
                  '$value분',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 15 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.add_circle_outline, color: const Color(0xFF2EC4B6), size: 22 * scale),
                onPressed: () => onChanged(value + 5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimePickerCard(String label, String timeStr, Function(String) onTimeSelected, double scale) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 12 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFF16161A).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.notoSansKr(
              color: Colors.white,
              fontSize: 14 * scale,
              fontWeight: FontWeight.w500,
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF2EC4B6).withValues(alpha: 0.1),
              padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 8 * scale),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * scale)),
            ),
            onPressed: () {
              _showCustomTimePickerDialog(
                context: context,
                title: '$label 선택',
                initialTimeStr: timeStr,
                onTimeSelected: onTimeSelected,
                scale: scale,
              );
            },
            child: Text(
              timeStr,
              style: GoogleFonts.outfit(
                color: const Color(0xFF2EC4B6),
                fontSize: 15 * scale,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCustomTimePickerDialog({
    required BuildContext context,
    required String title,
    required String initialTimeStr,
    required ValueChanged<String> onTimeSelected,
    required double scale,
  }) async {
    final parts = initialTimeStr.split(':');
    int hour = int.parse(parts[0]);
    int minute = int.parse(parts[1]);
    bool isPm = hour >= 12;
    int displayHour = hour % 12;
    if (displayHour == 0) displayHour = 12;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDState) {
            return Dialog(
              backgroundColor: const Color(0xFF16161A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20 * scale)),
              child: Container(
                padding: EdgeInsets.all(24 * scale),
                width: 340 * scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.notoSansKr(
                        color: Colors.white,
                        fontSize: 18 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 20 * scale),
                    Row(
                      children: [
                        // AM/PM Toggle
                        GestureDetector(
                          onTap: () {
                            setDState(() {
                              isPm = !isPm;
                            });
                          },
                          child: Container(
                            height: 60 * scale,
                            padding: EdgeInsets.symmetric(horizontal: 16 * scale),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFF24242B),
                              borderRadius: BorderRadius.circular(12 * scale),
                              border: Border.all(color: const Color(0xFF2EC4B6), width: 1.5 * scale),
                            ),
                            child: Text(
                              isPm ? 'PM' : 'AM',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16 * scale,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12 * scale),
                        Expanded(
                          child: _buildTimeNumberAdjuster(
                            label: '시',
                            value: displayHour,
                            min: 1,
                            max: 12,
                            scale: scale,
                            onChanged: (val) => setDState(() => displayHour = val),
                          ),
                        ),
                        SizedBox(width: 8 * scale),
                        Expanded(
                          child: _buildTimeNumberAdjuster(
                            label: '분',
                            value: minute,
                            min: 0,
                            max: 59,
                            scale: scale,
                            onChanged: (val) => setDState(() => minute = val),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 24 * scale),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          child: Text('취소', style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 14 * scale)),
                        ),
                        SizedBox(width: 12 * scale),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2EC4B6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * scale)),
                            padding: EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 12 * scale),
                          ),
                          onPressed: () {
                            int finalHour = displayHour % 12;
                            if (isPm) finalHour += 12;
                            final formatted = '${finalHour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
                            onTimeSelected(formatted);
                            Navigator.pop(dialogCtx);
                          },
                          child: Text('확인', style: GoogleFonts.notoSansKr(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14 * scale)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTimeNumberAdjuster({
    required String label,
    required int value,
    required int min,
    required int max,
    required double scale,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFF24242B),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Text(label, style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 11 * scale)),
          SizedBox(height: 4 * scale),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.remove_rounded, color: Colors.white70, size: 16 * scale),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  int newVal = value - 1;
                  if (newVal < min) newVal = max;
                  onChanged(newVal);
                },
              ),
              SizedBox(width: 8 * scale),
              Text(
                value.toString().padLeft(2, '0'),
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 18 * scale,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(width: 8 * scale),
              IconButton(
                icon: Icon(Icons.add_rounded, color: Colors.white70, size: 16 * scale),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  int newVal = value + 1;
                  if (newVal > max) newVal = min;
                  onChanged(newVal);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 4단계: 교과서 표지 설정
  Widget _buildStep4Textbooks() {
    final scale = _existingSettings?.scaleFactor ?? 1.4;
    final subjectStems = _getUniqueSubjectKeys();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.0 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 20 * scale),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '교과서 이미지 설정',
                style: GoogleFonts.outfit(
                  fontSize: 28 * scale,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2EC4B6),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 10 * scale),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10 * scale)),
                ),
                icon: Icon(Icons.auto_awesome, size: 16 * scale),
                label: Text(
                  '자동 매칭',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: _autoMatchImages,
              ),
            ],
          ),
          SizedBox(height: 8 * scale),
          Text(
            '각 과목별 교과서의 표지 이미지를 설정하세요. 파일명이 과목명을 포함하는 경우 \'자동 매칭\'을 통해 한 번에 등록할 수 있습니다.',
            style: GoogleFonts.notoSansKr(
              fontSize: 13 * scale,
              color: const Color(0xFF94A1B2),
            ),
          ),
          SizedBox(height: 20 * scale),
          Expanded(
            child: subjectStems.isEmpty
                ? Center(
                    child: Text(
                      '등록된 과목이 없습니다.',
                      style: GoogleFonts.notoSansKr(
                        color: const Color(0xFF72757E),
                        fontSize: 14 * scale,
                      ),
                    ),
                  )
                : GridView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 4,
                      crossAxisSpacing: 16 * scale,
                      mainAxisSpacing: 16 * scale,
                      childAspectRatio: 0.75,
                    ),
                    itemCount: subjectStems.length,
                    itemBuilder: (context, index) {
                      final stem = subjectStems[index];
                      final imagePath = _textbookImages[stem];
                      final hasImage = imagePath != null && imagePath.isNotEmpty;

                      return GestureDetector(
                        onTap: () => _pickTextbookImage(stem),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF16161A).withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(16 * scale),
                            border: Border.all(
                              color: hasImage ? const Color(0xFF2EC4B6) : Colors.white.withValues(alpha: 0.06),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16 * scale),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (hasImage)
                                  Image.file(
                                    File(imagePath),
                                    fit: BoxFit.cover,
                                  )
                                else
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.add_photo_alternate_outlined,
                                        color: const Color(0xFF2EC4B6),
                                        size: 32 * scale,
                                      ),
                                      SizedBox(height: 8 * scale),
                                      Text(
                                        '이미지 등록',
                                        style: GoogleFonts.notoSansKr(
                                          color: const Color(0xFF72757E),
                                          fontSize: 12 * scale,
                                        ),
                                      ),
                                    ],
                                  ),
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(vertical: 8 * scale),
                                    color: Colors.black.withValues(alpha: 0.6),
                                    alignment: Alignment.center,
                                    child: Text(
                                      _displaySubjectName(stem),
                                      style: GoogleFonts.notoSansKr(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13 * scale,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // 5단계: 교사 실명 매핑
  Widget _buildStep5Teachers() {
    final scale = _existingSettings?.scaleFactor ?? 1.4;
    final teacherKeys = _getTeacherKeys();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.0 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 20 * scale),
          Text(
            '교사 이름 매핑',
            style: GoogleFonts.outfit(
              fontSize: 28 * scale,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 8 * scale),
          Text(
            '교과 교사의 실명 매핑을 입력하거나,\n실명 리스트(JSON 또는 줄바꿈 구분)를 붙여넣어 자동 매핑하세요.',
            style: GoogleFonts.notoSansKr(
              fontSize: 13 * scale,
              color: const Color(0xFF94A1B2),
            ),
          ),
          SizedBox(height: 16 * scale),
          // JSON Import box
          Container(
            padding: EdgeInsets.all(12.0 * scale),
            decoration: BoxDecoration(
              color: const Color(0xFF16161A).withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12 * scale),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                TextField(
                  controller: _jsonImportController,
                  maxLines: 2,
                  style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 12 * scale),
                  decoration: InputDecoration(
                    hintText: '실명 명단 예시: ["홍길동", "김철수"] 또는 {"수학홍길동": "홍길동선생님", ...}',
                    hintStyle: GoogleFonts.notoSansKr(color: const Color(0xFF72757E), fontSize: 12 * scale),
                    border: InputBorder.none,
                  ),
                ),
                SizedBox(height: 8 * scale),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF2EC4B6),
                        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
                      ),
                      onPressed: () async {
                        try {
                          final value = await Clipboard.getData(Clipboard.kTextPlain);
                          if (value?.text != null) {
                            setState(() {
                              _jsonImportController.text = value!.text!;
                            });
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('클립보드에서 텍스트를 가져오지 못했습니다. $e')),
                            );
                          }
                        }
                      },
                      icon: Icon(Icons.paste_rounded, size: 14 * scale),
                      label: Text('클립보드 붙여넣기', style: GoogleFonts.notoSansKr(fontSize: 11 * scale)),
                    ),
                    SizedBox(width: 8 * scale),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF00F5D4),
                        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
                      ),
                      onPressed: () {
                        final exampleMap = <String, String>{};
                        for (final entry in teacherKeys) {
                          exampleMap[entry.key] = '${entry.value}선생님';
                        }
                        setState(() {
                          _jsonImportController.text = const JsonEncoder.withIndent('  ').convert(exampleMap);
                        });
                      },
                      icon: Icon(Icons.code_rounded, size: 14 * scale),
                      label: Text('JSON 템플릿 삽입', style: GoogleFonts.notoSansKr(fontSize: 11 * scale)),
                    ),
                    SizedBox(width: 8 * scale),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFFD166),
                        padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale),
                      ),
                      onPressed: _pickAndImportJsonFile,
                      icon: Icon(Icons.file_open_rounded, size: 14 * scale),
                      label: Text('JSON 파일 등록', style: GoogleFonts.notoSansKr(fontSize: 11 * scale)),
                    ),
                    const Spacer(),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2EC4B6),
                        padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 8 * scale),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8 * scale)),
                        elevation: 0,
                      ),
                      onPressed: _importTeacherNames,
                      child: Text(
                        '명단 매칭',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12 * scale,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 16 * scale),
          // List of teacher mappings
          Expanded(
            child: teacherKeys.isEmpty
                ? Center(
                    child: Text(
                      '등록된 교사 정보가 없습니다.',
                      style: GoogleFonts.notoSansKr(color: const Color(0xFF94A1B2), fontSize: 14 * scale),
                    ),
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: teacherKeys.length,
                    itemBuilder: (context, index) {
                      final entry = teacherKeys[index];
                      final key = entry.key;
                      final rawName = entry.value;

                      // Extract stem for readability
                      final String stem = key.endsWith(rawName)
                          ? key.substring(0, key.length - rawName.length)
                          : AppSettings.getSubjectStem(key);

                      final controller = _teacherControllers.putIfAbsent(
                        key,
                        () => TextEditingController(text: _teacherFullNames[key]),
                      );

                      return Container(
                        margin: EdgeInsets.only(bottom: 12.0 * scale),
                        padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 8 * scale),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16161A).withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12 * scale),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    rawName,
                                    style: GoogleFonts.notoSansKr(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15 * scale,
                                    ),
                                  ),
                                  Text(
                                    stem,
                                    style: GoogleFonts.notoSansKr(
                                      color: const Color(0xFF2CB67D),
                                      fontSize: 12 * scale,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_right_alt, color: const Color(0xFF72757E), size: 20 * scale),
                            SizedBox(width: 12 * scale),
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: controller,
                                style: GoogleFonts.notoSansKr(color: Colors.white, fontSize: 14 * scale),
                                decoration: InputDecoration(
                                  hintText: '실명 입력',
                                  hintStyle: GoogleFonts.notoSansKr(color: const Color(0xFF72757E), fontSize: 13 * scale),
                                  border: UnderlineInputBorder(
                                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                                  ),
                                  focusedBorder: const UnderlineInputBorder(
                                    borderSide: BorderSide(color: Color(0xFF2EC4B6)),
                                  ),
                                ),
                                onChanged: (val) {
                                  _teacherFullNames[key] = val.trim();
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep6Done() {
    final scale = _existingSettings?.scaleFactor ?? 1.4;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.0 * scale),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24 * scale),
              decoration: BoxDecoration(
                color: const Color(0xFF2EC4B6).withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF2EC4B6).withValues(alpha: 0.3), width: 2 * scale),
              ),
              child: Icon(Icons.check_circle_outline, color: const Color(0xFF2EC4B6), size: 80 * scale),
            ),
            SizedBox(height: 24 * scale),
            Text(
              '설정 완료!',
              style: GoogleFonts.outfit(
                fontSize: 32 * scale,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 12 * scale),
            Text(
              '모든 학급 설정이 성공적으로 마쳐졌습니다.\n이제 이 스마트 칠판 런처를 본격적으로 시작해 보세요.',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 14 * scale,
                color: const Color(0xFF94A1B2),
                height: 1.6,
              ),
            ),
            if (Platform.isAndroid) ...[
              SizedBox(height: 28 * scale),
              ElevatedButton.icon(
                onPressed: _setAndroidDefaultLauncher,
                icon: Icon(Icons.home_rounded, size: 20 * scale),
                label: Text(
                  '기본 홈 앱으로 설정',
                  style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2EC4B6),
                  foregroundColor: const Color(0xFF0F0E17),
                  padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 14 * scale),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }


  void _showAppSelectionDialog(int index) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AppSelectionDialog(
              onAppSelected: (name, appId) {
                setState(() {
                  if (index < _selectedSystemApps.length) {
                    _selectedSystemApps[index] = SystemApp(name: name, appId: appId);
                  } else {
                    _selectedSystemApps.add(SystemApp(name: name, appId: appId));
                  }
                });
              },
              initialName: index < _selectedSystemApps.length ? _selectedSystemApps[index].name : '',
              initialAppId: index < _selectedSystemApps.length ? _selectedSystemApps[index].appId : '',
            );
          },
        );
      },
    );
  }

  Future<void> _finishSetup() async {
    if (_selectedSchool == null) return;
    if (_isLoading) return; // 중복 호출 방지
    for (final entry in _teacherControllers.entries) {
      if (entry.value.text.trim().isNotEmpty) {
        _teacherFullNames[entry.key] = entry.value.text.trim();
      }
    }
    final settings = AppSettings(
      selectedSchool: _selectedSchool,
      selectedGrade: _selectedGrade,
      selectedClass: _selectedClass,
      timeSettings: TimeSettings(
        lessonDuration: _lessonDuration,
        breakDuration: _breakDuration,
        lunchDuration: _lunchDuration,
        lunchAfterPeriod: _lunchAfterPeriod,
        firstPeriodStart: _firstPeriodStart,
        morningAssemblyStart: _morningAssemblyStart,
        morningAssemblyEnd: _morningRelativeMode ? (_morningAssemblyEnd.contains(':') ? "15" : _morningAssemblyEnd) : _morningAssemblyEnd,
        afternoonAssemblyStart: _afternoonAssemblyStart,
        afternoonAssemblyEnd: _afternoonRelativeMode ? (_afternoonAssemblyEnd.contains(':') ? "20" : _afternoonAssemblyEnd) : _afternoonAssemblyEnd,
        afternoonAssemblyAfterMinutes: _afternoonRelativeMode ? (_afternoonAssemblyAfterMinutes ?? 0) : null,
        morningAssemblyBeforeMinutes: _morningRelativeMode ? (_morningAssemblyBeforeMinutes ?? 15) : null,
      ),
      textbookImages: _textbookImages,
      isSetupComplete: true,
      ddayEvents: _ddayEvents,
      pinnedDday: _existingSettings?.pinnedDday,
      scaleFactor: _existingSettings?.scaleFactor ?? 1.4,
      selectedSystemApps: _selectedSystemApps,
      launcherSlots: _existingSettings?.launcherSlots,
      autoSleepEnabled: _existingSettings?.autoSleepEnabled ?? false,
      cafeteriaNum: _selectedCafeteria,
      mealCallClassOrder: _existingSettings?.mealCallClassOrder ?? 'asc',
      specialClassroomType: _specialClassroomMode ? 1 : 0,
      connectionName: _authSchoolController.text.trim().isNotEmpty 
          ? _authSchoolController.text.trim() 
          : (_connectionNameController.text.trim().isNotEmpty ? _connectionNameController.text.trim() : 'My'),
      classNickname: _specialClassroomMode 
          ? _specialIdController.text.trim() 
          : (_authClassController.text.trim().isNotEmpty 
              ? _authClassController.text.trim() 
              : _classNicknameController.text.trim()),
      selectedTeacher: _specialClassroomMode ? _specialTeacherController.text.trim() : '',
    );
    if (!mounted) return;
    setState(() { _isLoading = true; });
    try {
      await _storageService.saveSettings(settings);
      
      // 특별실 모드 및 일반 교실 모두 Firebase 자동 로그인/가입 수행
      final authService = AuthService();
      await authService.loginOrSignupClass(
        region: settings.selectedSchool?.region ?? '서울',
        school: settings.selectedSchool?.name ?? '',
        grade: settings.selectedGrade,
        classNum: settings.selectedClass,
        isSpecial: settings.specialClassroomMode,
        specialId: settings.classNickname,
      );
    } catch (e) {
      debugPrint('설정 저장 및 로그인 오류: $e');
      if (mounted) setState(() { _isLoading = false; });
      return;
    }
    if (!mounted) return;
    setState(() { _isLoading = false; });

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DashboardView()),
      (_) => false,
    );
  }
}

class AppSelectionDialog extends StatefulWidget {
  final Function(String name, String appId) onAppSelected;
  final String initialName;
  final String initialAppId;
  final String initialTab;

  const AppSelectionDialog({
    super.key,
    required this.onAppSelected,
    required this.initialName,
    required this.initialAppId,
    this.initialTab = 'scanned',
  });

  @override
  State<AppSelectionDialog> createState() => _AppSelectionDialogState();
}

class _AppSelectionDialogState extends State<AppSelectionDialog> {
  final TextEditingController _customNameController = TextEditingController();
  final TextEditingController _customUrlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  List<ScannedApp> _allScannedApps = [];
  List<ScannedApp> _filteredScannedApps = [];
  bool _isLoadingApps = false;
  late String _activeTab; // 'scanned' or 'custom'

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    _customNameController.text = widget.initialName;
    _customUrlController.text = widget.initialAppId;
    _loadInstalledApps();
    _searchController.addListener(_filterApps);
  }

  @override
  void dispose() {
    _customNameController.dispose();
    _customUrlController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInstalledApps() async {
    if (!mounted) return;
    setState(() {
      _isLoadingApps = true;
    });
    try {
      final apps = await SystemAppScanner.scanInstalledApps();
      if (mounted) {
        setState(() {
          _allScannedApps = apps;
          _filteredScannedApps = apps;
        });
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isLoadingApps = false;
      });
    }
  }

  void _filterApps() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredScannedApps = _allScannedApps;
      } else {
        _filteredScannedApps = _allScannedApps
            .where((app) => app.name.toLowerCase().contains(query) || app.appId.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  Future<void> _pickCustomExecutable() async {
    try {
      FilePickerResult? result;
      if (Platform.isWindows) {
        result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['exe', 'lnk', 'bat', 'cmd'],
          allowMultiple: false,
        );
      } else if (Platform.isAndroid) {
        result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['apk'],
          allowMultiple: false,
        );
      } else {
        result = await FilePicker.pickFiles(
          type: FileType.any,
          allowMultiple: false,
        );
      }
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final fileName = result.files.single.name;
        // Auto-fill name from filename (without extension)
        final nameWithoutExt = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
        setState(() {
          _customUrlController.text = path;
          if (_customNameController.text.trim().isEmpty) {
            _customNameController.text = nameWithoutExt;
          }
        });
      }
    } catch (e) {
      debugPrint('File picker error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF0F0E17),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '시스템 앱 선택',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _buildScannedAppsTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannedAppsTab() {
    if (_isLoadingApps) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2EC4B6)),
        ),
      );
    }

    return Column(
      children: [
        // Search bar
        TextField(
          controller: _searchController,
          style: GoogleFonts.notoSansKr(color: Colors.white),
          decoration: InputDecoration(
            hintText: '앱 검색..',
            hintStyle: GoogleFonts.notoSansKr(color: Colors.white38),
            prefixIcon: const Icon(Icons.search, color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF16161A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _filteredScannedApps.isEmpty
              ? Center(
                  child: Text(
                    '설치된 앱을 찾을 수 없습니다.',
                    style: GoogleFonts.notoSansKr(color: Colors.white38),
                  ),
                )
              : ListView.builder(
                  itemCount: _filteredScannedApps.length,
                  itemBuilder: (context, index) {
                    final app = _filteredScannedApps[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      leading: Builder(builder: (_) {
                        final hasIcon = app.iconPath != null && app.iconPath!.isNotEmpty && File(app.iconPath!).existsSync();
                        if (hasIcon) {
                          return Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.file(
                                File(app.iconPath!),
                                fit: BoxFit.contain,
                              ),
                            ),
                          );
                        }
                        final name = app.name;
                        final avatar = name.length >= 2 ? name.substring(0, 2) : name;
                        const colors = [
                          Color(0xFF2EC4B6), Color(0xFF00F5D4), Color(0xFF2CB67D),
                          Color(0xFF7B61FF), Color(0xFFF4A261),
                        ];
                        final color = colors[name.codeUnits.first % colors.length];
                        return Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
                          ),
                          alignment: Alignment.center,
                          child: Text(avatar, style: GoogleFonts.notoSansKr(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                        );
                      }),
                      title: Text(
                        app.name,
                        style: GoogleFonts.notoSansKr(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        app.appId,
                        style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        widget.onAppSelected(app.name, app.appId);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCustomUrlTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('앱/링크 이름', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          TextField(
            controller: _customNameController,
            style: GoogleFonts.notoSansKr(color: Colors.white),
            decoration: InputDecoration(
              hintText: '예: EBSi 또는 계산기',
              hintStyle: GoogleFonts.notoSansKr(color: Colors.white38),
              filled: true,
              fillColor: const Color(0xFF16161A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('웹 주소 또는 실행 파일 경로', style: GoogleFonts.notoSansKr(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customUrlController,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '예: https://... 또는 C:\\Program Files\\앱.exe',
                    hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF16161A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2CB67D).withValues(alpha: 0.15),
                  foregroundColor: const Color(0xFF2CB67D),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFF2CB67D), width: 1),
                  ),
                ),
                onPressed: _pickCustomExecutable,
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: Text(
                  '찾기',
                  style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            Platform.isWindows
                ? '※ .exe, .lnk, .bat 파일 또는 https:// URL을 등록하세요'
                : '※ .apk 파일 경로 또는 패키지명/URL을 등록하세요',
            style: GoogleFonts.notoSansKr(
              color: Colors.white24,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2EC4B6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                final name = _customNameController.text.trim();
                final path = _customUrlController.text.trim();
                if (name.isNotEmpty && path.isNotEmpty) {
                  widget.onAppSelected(name, path);
                  Navigator.of(context).pop();
                }
              },
              child: Text(
                '등록하기',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// LauncherCustomDialog begins below


/// Dialog for customizing the 3x3 launcher grid
class LauncherCustomDialog extends StatefulWidget {
  final List<LauncherSlot> initialSlots;
  final List<SystemApp> systemApps;
  final Future<void> Function(List<LauncherSlot>) onSave;

  const LauncherCustomDialog({
    super.key,
    required this.initialSlots,
    required this.systemApps,
    required this.onSave,
  });

  @override
  State<LauncherCustomDialog> createState() => _LauncherCustomDialogState();
}

class DraggedItem {
  final LauncherSlot slot;
  final int? fromIndex;
  DraggedItem({required this.slot, this.fromIndex});
}

class _LauncherCustomDialogState extends State<LauncherCustomDialog> {
  late List<LauncherSlot?> _slots; // 12 slots, nullable for empty
  bool _isSaving = false;
  List<LauncherSlot> _scannedSystemApps = [];
  List<LauncherSlot> _customAddedApps = [];
  bool _isLoadingApps = false;

  List<LauncherSlot> get _allAvailable {
    final result = <LauncherSlot>[];
    // System apps
    for (final app in widget.systemApps) {
      result.add(LauncherSlot(type: LauncherSlotType.systemApp, name: app.name, id: app.appId, iconPath: app.iconPath));
    }
    // Boardest tools
    result.addAll(LauncherSlot.allBoardestTools);
    return result;
  }

  @override
  void initState() {
    super.initState();
    _slots = List<LauncherSlot?>.filled(12, null);
    for (int i = 0; i < widget.initialSlots.length && i < 12; i++) {
      final slot = widget.initialSlots[i];
      if (slot.type != LauncherSlotType.empty) {
        _slots[i] = slot;
      }
    }
    _loadInstalledApps();
  }

  Future<void> _loadInstalledApps() async {
    if (!mounted) return;
    setState(() {
      _isLoadingApps = true;
    });
    try {
      final apps = await SystemAppScanner.scanInstalledApps();
      if (mounted) {
        setState(() {
          _scannedSystemApps = apps
              .map((app) => LauncherSlot(
                    type: LauncherSlotType.systemApp,
                    name: app.name,
                    id: app.appId,
                    iconPath: app.iconPath,
                  ))
              .toList();
        });
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isLoadingApps = false;
      });
    }
  }

  void _assignSlot(int slotIndex, LauncherSlot slot) {
    setState(() {
      _slots[slotIndex] = slot;
    });
  }

  void _clearSlot(int slotIndex) {
    setState(() {
      _slots[slotIndex] = null;
    });
  }

  void _autoAssign(LauncherSlot slot) {
    var targetSlot = slot;
    if (targetSlot.type == LauncherSlotType.systemApp &&
        (targetSlot.name.contains('Boardest') ||
            targetSlot.id.startsWith('boardest://') ||
            targetSlot.id.toLowerCase().contains('boardest.lnk'))) {
      String toolId = 'whiteboard';
      if (targetSlot.name.contains('타이머') || targetSlot.id.contains('timer')) {
        toolId = 'timer';
      } else if (targetSlot.name.contains('발표자') || targetSlot.id.contains('picker')) {
        toolId = 'picker';
      } else if (targetSlot.name.contains('주사위') || targetSlot.id.contains('dice')) {
        toolId = 'dice';
      } else if (targetSlot.name.contains('시간표') || targetSlot.id.contains('timetable')) {
        toolId = 'timetable';
      } else if (targetSlot.name.contains('소음') || targetSlot.id.contains('noise')) {
        toolId = 'noise';
      } else if (targetSlot.name.contains('출석') || targetSlot.id.contains('attendance')) {
        toolId = 'attendance';
      } else if (targetSlot.name.contains('설정') || targetSlot.id.contains('settings')) {
        toolId = 'settings';
      } else if (targetSlot.name.contains('전체앱') || targetSlot.id.contains('app_drawer')) {
        toolId = 'app_drawer';
      }

      final cleanName = targetSlot.name.split(' (')[0];
      targetSlot = LauncherSlot(
        type: LauncherSlotType.boardestTool,
        name: cleanName,
        id: toolId,
      );
    }

    for (int i = 0; i < 12; i++) {
      if (_slots[i] == null) {
        setState(() {
          _slots[i] = targetSlot;
        });
        break;
      }
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final List<LauncherSlot> slots = List<LauncherSlot>.generate(12, (i) {
      return _slots[i] ?? LauncherSlot(type: LauncherSlotType.empty, name: '', id: 'empty');
    });
    await widget.onSave(slots);
    if (mounted) Navigator.of(context).pop();
  }



  IconData _getToolIcon(String id) {
    switch (id) {
      // 단순 도구 (Simple Tools)
      case 'timer': return Icons.timer_rounded;
      case 'noise': return Icons.graphic_eq_rounded;
      case 'calculator': return Icons.calculate_rounded;
      case 'notepad': return Icons.note_alt_rounded;
      case 'dice': return Icons.casino_rounded;
      case 'picker': return Icons.person_search_rounded;

      // 판서 관련 (Annotation Tools)
      case 'whiteboard': return Icons.draw_rounded;
      case 'ppt_board': return Icons.slideshow_rounded;
      case 'screen_capture_board': return Icons.screenshot_rounded;
      case 'split_screen_board': return Icons.grid_view_rounded;
      case 'worksheet_board': return Icons.description_rounded;
      case 'textbook_lens_board': return Icons.zoom_in_rounded;

      // 학생 연결 (Student Connection)
      case 'student_cast': return Icons.cast_connected_rounded;
      case 'class_quiz': return Icons.quiz_rounded;
      case 'attendance_safety': return Icons.how_to_reg_rounded;
      case 'response_feed': return Icons.forum_rounded;
      case 'group_work_share': return Icons.share_rounded;
      case 'engagement_tracker': return Icons.analytics_rounded;

      // 기타/유틸리티
      case 'file_explorer': return Icons.folder_open_rounded;
      case 'timetable': return Icons.calendar_month_rounded;
      case 'settings': return Icons.tune_rounded;
      case 'app_drawer': return Icons.apps_rounded;
      default: return Icons.apps_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = 1.3; // Dialog-level scale factor for layout consistency

    final bstTools = LauncherSlot.allBoardestTools;
    final sysApps = widget.systemApps.map((e) => LauncherSlot(type: LauncherSlotType.systemApp, name: e.name, id: e.appId, iconPath: e.iconPath)).toList();

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(horizontal: 40 * scale, vertical: 30 * scale),
        child: Container(
          width: 860 * scale,
          height: 560 * scale,
          decoration: BoxDecoration(
            color: const Color(0xFF0F0E17),
            borderRadius: BorderRadius.circular(16 * scale),
            border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 20 * scale,
                spreadRadius: 5 * scale,
              )
            ],
          ),
          padding: EdgeInsets.all(24 * scale),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '런처 커스텀 설정',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 20 * scale,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '자주 사용하는 도구나 앱을 3x4 그리드에 드래그하여 배치해보세요. 클릭 시 자동 배치됩니다.',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 11 * scale,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: Colors.white54, size: 22 * scale),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              SizedBox(height: 20 * scale),
              
              // Main Split Content
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left Side: 3x4 Grid
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '런처 배치 (3x4)',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13 * scale,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF2EC4B6),
                            ),
                          ),
                          SizedBox(height: 12 * scale),
                          Expanded(
                            child: Container(
                              padding: EdgeInsets.all(12 * scale),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.01),
                                borderRadius: BorderRadius.circular(12 * scale),
                                border: Border.all(color: Colors.white.withOpacity(0.04)),
                              ),
                              child: GridView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 8 * scale,
                                  mainAxisSpacing: 8 * scale,
                                  childAspectRatio: 1.45,
                                ),
                                itemCount: 12,
                                itemBuilder: (context, index) {
                                  final slot = _slots[index];
                                  
                                  return DragTarget<DraggedItem>(
                                    onWillAccept: (data) => true,
                                    onAccept: (data) {
                                      setState(() {
                                        var slot = data.slot;
                                        if (slot.type == LauncherSlotType.systemApp &&
                                            (slot.name.contains('Boardest') ||
                                                slot.id.startsWith('boardest://') ||
                                                slot.id.toLowerCase().contains('boardest.lnk'))) {
                                          String toolId = 'whiteboard';
                                          if (slot.name.contains('타이머') || slot.id.contains('timer')) {
                                            toolId = 'timer';
                                          } else if (slot.name.contains('발표자') || slot.id.contains('picker')) {
                                            toolId = 'picker';
                                          } else if (slot.name.contains('주사위') || slot.id.contains('dice')) {
                                            toolId = 'dice';
                                          } else if (slot.name.contains('시간표') || slot.id.contains('timetable')) {
                                            toolId = 'timetable';
                                          } else if (slot.name.contains('소음') || slot.id.contains('noise')) {
                                            toolId = 'noise';
                                          } else if (slot.name.contains('출석') || slot.id.contains('attendance')) {
                                            toolId = 'attendance';
                                          } else if (slot.name.contains('설정') || slot.id.contains('settings')) {
                                            toolId = 'settings';
                                          } else if (slot.name.contains('전체앱') || slot.id.contains('app_drawer')) {
                                            toolId = 'app_drawer';
                                          }

                                          final cleanName = slot.name.split(' (')[0];
                                          slot = LauncherSlot(
                                            type: LauncherSlotType.boardestTool,
                                            name: cleanName,
                                            id: toolId,
                                          );
                                        }

                                        if (data.fromIndex != null) {
                                          final old = _slots[index];
                                          _slots[index] = slot;
                                          _slots[data.fromIndex!] = old;
                                        } else {
                                          _slots[index] = slot;
                                        }
                                      });
                                    },
                                    builder: (context, candidateData, rejectedData) {
                                      final isOver = candidateData.isNotEmpty;
                                      
                                      if (slot == null) {
                                        return Container(
                                          decoration: BoxDecoration(
                                            color: isOver ? const Color(0xFF2EC4B6).withOpacity(0.1) : Colors.white.withOpacity(0.02),
                                            borderRadius: BorderRadius.circular(10 * scale),
                                            border: Border.all(
                                              color: isOver ? const Color(0xFF2EC4B6) : Colors.white.withOpacity(0.1),
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.add_rounded, color: Colors.white24, size: 20 * scale),
                                                SizedBox(height: 4 * scale),
                                                Text(
                                                  '슬롯 ${index + 1}',
                                                  style: GoogleFonts.notoSansKr(
                                                    fontSize: 10 * scale,
                                                    color: Colors.white24,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }
                                      
                                      final colors = [
                                        const Color(0xFF2EC4B6),
                                        const Color(0xFF00F5D4),
                                        const Color(0xFF2CB67D),
                                      ];
                                      Color accentColor;
                                      Widget iconWidget;
                                      
                                      if (slot.type == LauncherSlotType.systemApp) {
                                        final hasIcon = slot.iconPath != null && slot.iconPath!.isNotEmpty && File(slot.iconPath!).existsSync();
                                        accentColor = colors[slot.name.codeUnits.first % colors.length];
                                        if (hasIcon) {
                                           iconWidget = Container(
                                             width: 34 * scale, height: 34 * scale,
                                             padding: EdgeInsets.all(1 * scale),
                                             child: ClipRRect(borderRadius: BorderRadius.circular(6 * scale), child: Image.file(
                                               File(slot.iconPath!),
                                               fit: BoxFit.contain,
                                               width: 34 * scale,
                                               height: 34 * scale,
                                             )),
                                           );
                                         } else {
                                          final avatar = slot.name.length >= 2 ? slot.name.substring(0, 2) : slot.name;
                                          iconWidget = Container(
                                            width: 28 * scale, height: 28 * scale,
                                            decoration: BoxDecoration(
                                              color: accentColor.withOpacity(0.18),
                                              borderRadius: BorderRadius.circular(6 * scale),
                                              border: Border.all(color: accentColor.withOpacity(0.5)),
                                            ),
                                            child: Center(
                                              child: Text(
                                                avatar,
                                                style: GoogleFonts.notoSansKr(
                                                  fontSize: 9 * scale,
                                                  fontWeight: FontWeight.bold,
                                                  color: accentColor,
                                                ),
                                              ),
                                            ),
                                          );
                                        }
                                      } else {
                                        accentColor = colors[slot.id.hashCode.abs() % colors.length];
                                        iconWidget = Container(
                                          width: 28 * scale, height: 28 * scale,
                                          decoration: BoxDecoration(
                                            color: accentColor.withOpacity(0.18),
                                            borderRadius: BorderRadius.circular(6 * scale),
                                            border: Border.all(color: accentColor.withOpacity(0.5)),
                                          ),
                                          child: Center(
                                            child: Icon(
                                              _getToolIcon(slot.id),
                                              color: accentColor,
                                              size: 15 * scale,
                                            ),
                                          ),
                                        );
                                      }
                                      
                                      final slotContent = Container(
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.04),
                                          borderRadius: BorderRadius.circular(10 * scale),
                                          border: Border.all(color: isOver ? const Color(0xFF2EC4B6) : Colors.white.withOpacity(0.08)),
                                        ),
                                        child: Stack(
                                          children: [
                                            Center(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  iconWidget,
                                                  SizedBox(height: 5 * scale),
                                                  Padding(
                                                    padding: EdgeInsets.symmetric(horizontal: 4 * scale),
                                                    child: Text(
                                                      slot.name,
                                                      style: GoogleFonts.notoSansKr(
                                                        fontSize: 10 * scale,
                                                        fontWeight: FontWeight.w600,
                                                        color: Colors.white70,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      textAlign: TextAlign.center,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Positioned(
                                              top: 4 * scale, right: 4 * scale,
                                              child: InkWell(
                                                onTap: () => _clearSlot(index),
                                                borderRadius: BorderRadius.circular(8),
                                                child: Container(
                                                  padding: EdgeInsets.all(2 * scale),
                                                  decoration: const BoxDecoration(
                                                    color: Colors.black45,
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: Icon(Icons.close_rounded, size: 11 * scale, color: Colors.white70),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                      
                                      return Draggable<DraggedItem>(
                                        data: DraggedItem(slot: slot, fromIndex: index),
                                        feedback: Material(
                                          color: Colors.transparent,
                                          child: Container(
                                            width: 80 * scale, height: 80 * scale,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF16161A).withOpacity(0.9),
                                              borderRadius: BorderRadius.circular(10 * scale),
                                              border: Border.all(color: const Color(0xFF2EC4B6)),
                                            ),
                                            child: Center(
                                              child: Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: [
                                                  iconWidget,
                                                  SizedBox(height: 4 * scale),
                                                  Text(
                                                    slot.name,
                                                    style: GoogleFonts.notoSansKr(
                                                      fontSize: 9 * scale,
                                                      color: Colors.white70,
                                                      decoration: TextDecoration.none,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        childWhenDragging: Opacity(
                                          opacity: 0.3,
                                          child: slotContent,
                                        ),
                                        child: slotContent,
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    SizedBox(width: 20 * scale),
                    VerticalDivider(color: Colors.white.withOpacity(0.08), width: 1.5),
                    SizedBox(width: 20 * scale),
                    
                    // Right Side: Available Pool
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 8 * scale),
                            child: Text(
                              '선택 가능한 도구 및 앱',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 13 * scale,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF2EC4B6),
                              ),
                            ),
                          ),
                          SizedBox(height: 12 * scale),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.01),
                                borderRadius: BorderRadius.circular(12 * scale),
                                border: Border.all(color: Colors.white.withOpacity(0.04)),
                              ),
                              child: _isLoadingApps
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2EC4B6)),
                                      ),
                                    )
                                  : Builder(builder: (context) {
                                      final scannedIconMap = <String, String>{};
                                      for (final app in _scannedSystemApps) {
                                        if (app.iconPath != null) {
                                          scannedIconMap[app.id] = app.iconPath!;
                                        }
                                      }

                                      final manualApps = widget.systemApps
                                          .map((e) {
                                            final iconPath = e.iconPath ?? scannedIconMap[e.appId];
                                            return LauncherSlot(
                                              type: LauncherSlotType.systemApp,
                                              name: e.name,
                                              id: e.appId,
                                              iconPath: iconPath,
                                            );
                                          })
                                          .toList();

                                      final combinedSystem = <LauncherSlot>[...manualApps];
                                      final seenIds = manualApps.map((e) => e.id).toSet();
                                      for (final app in _customAddedApps) {
                                        if (!seenIds.contains(app.id)) {
                                          combinedSystem.add(app);
                                          seenIds.add(app.id);
                                        }
                                      }
                                      for (final app in _scannedSystemApps) {
                                        if (!seenIds.contains(app.id)) {
                                          combinedSystem.add(app);
                                          seenIds.add(app.id);
                                        }
                                      }

                                      // Filter out any system app whose name contains "Boardest" or appId contains "boardest" or is empty
                                      final filteredSystem = combinedSystem.where((slot) {
                                        final nameLower = slot.name.toLowerCase();
                                        final idLower = slot.id.toLowerCase();
                                        if (nameLower.contains('boardest') ||
                                            idLower.contains('boardest') ||
                                            idLower.startsWith('boardest://') ||
                                            slot.type == LauncherSlotType.empty) {
                                          return false;
                                        }
                                        return true;
                                      }).toList();

                                      // Combine: BST Tools at the top, then filtered system apps
                                      final allPoolItems = [...bstTools, ...filteredSystem];
                                      return _buildPoolGrid(allPoolItems, scale);
                                    }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 20 * scale),
              
              // Bottom Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white54,
                      padding: EdgeInsets.symmetric(horizontal: 20 * scale, vertical: 12 * scale),
                    ),
                    child: Text('취소', style: GoogleFonts.notoSansKr(fontSize: 12 * scale)),
                  ),
                  SizedBox(width: 10 * scale),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2EC4B6),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 12 * scale),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8 * scale),
                      ),
                    ),
                    child: _isSaving
                        ? SizedBox(
                            width: 16 * scale,
                            height: 16 * scale,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Text('저장 및 완료', style: GoogleFonts.notoSansKr(fontSize: 12 * scale, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPoolGrid(List<LauncherSlot> items, double scale) {
    return GridView.builder(
      padding: EdgeInsets.all(10 * scale),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8 * scale,
        mainAxisSpacing: 8 * scale,
        childAspectRatio: 1.1,
      ),
      itemCount: items.length,
      itemBuilder: (context, idx) {
        final item = items[idx];
        
        Color accentColor;
        Widget iconWidget;
        final colors = [
          const Color(0xFF2EC4B6),
          const Color(0xFF00F5D4),
          const Color(0xFF2CB67D),
        ];
        
        if (item.type == LauncherSlotType.systemApp) {
          final hasIcon = item.iconPath != null && item.iconPath!.isNotEmpty && File(item.iconPath!).existsSync();
          accentColor = colors[item.name.codeUnits.first % colors.length];
          if (hasIcon) {
            iconWidget = Container(
              width: 32 * scale, height: 32 * scale,
              padding: EdgeInsets.all(1 * scale),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6 * scale),
                child: Image.file(
                  File(item.iconPath!),
                  fit: BoxFit.contain,
                  width: 32 * scale,
                  height: 32 * scale,
                ),
              ),
            );
          } else {
            final avatar = item.name.length >= 2 ? item.name.substring(0, 2) : item.name;
            iconWidget = Container(
              width: 26 * scale, height: 26 * scale,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.18),
                borderRadius: BorderRadius.circular(6 * scale),
                border: Border.all(color: accentColor.withOpacity(0.5)),
              ),
              child: Center(
                child: Text(
                  avatar,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 9 * scale,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
              ),
            );
          }
        } else {
          accentColor = colors[item.id.hashCode.abs() % colors.length];
          iconWidget = Container(
            width: 26 * scale, height: 26 * scale,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.18),
              borderRadius: BorderRadius.circular(6 * scale),
              border: Border.all(color: accentColor.withOpacity(0.5)),
            ),
            child: Center(
              child: Icon(
                _getToolIcon(item.id),
                color: accentColor,
                size: 14 * scale,
              ),
            ),
          );
        }
        
        final itemCard = Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(8 * scale),
            border: Border.all(color: Colors.white.withOpacity(0.04)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _autoAssign(item),
              borderRadius: BorderRadius.circular(8 * scale),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  iconWidget,
                  SizedBox(height: 4 * scale),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4 * scale),
                    child: Text(
                      item.name,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 9 * scale,
                        color: Colors.white70,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        
        return Draggable<DraggedItem>(
          data: DraggedItem(slot: item, fromIndex: null),
          feedback: Material(
            color: Colors.transparent,
            child: Container(
              width: 70 * scale, height: 70 * scale,
              decoration: BoxDecoration(
                color: const Color(0xFF16161A).withOpacity(0.9),
                borderRadius: BorderRadius.circular(8 * scale),
                border: Border.all(color: const Color(0xFF2EC4B6)),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    iconWidget,
                    SizedBox(height: 4 * scale),
                    Text(
                      item.name,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 8 * scale,
                        color: Colors.white70,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.4,
            child: itemCard,
          ),
          child: itemCard,
        );
      },
    );
  }
}
