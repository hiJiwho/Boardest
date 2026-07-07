import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

/// 현재 로그인된 사용자 정보
class BoardestUser {
  final String region;
  final String school;
  final int grade;
  final int classNum;
  final String email; // G{grade}C{class}@{school}.{region}.bst

  const BoardestUser({
    required this.region,
    required this.school,
    required this.grade,
    required this.classNum,
    required this.email,
  });

  factory BoardestUser.fromPrefs(SharedPreferences prefs) {
    return BoardestUser(
      region: prefs.getString('auth_region') ?? '',
      school: prefs.getString('auth_school') ?? '',
      grade: prefs.getInt('auth_grade') ?? 1,
      classNum: prefs.getInt('auth_class') ?? 1,
      email: prefs.getString('auth_email') ?? '',
    );
  }
}

/// 같은 학교의 반 정보 (급식 호출 등에서 사용)
class ClassInfo {
  final int grade;
  final int classNum;
  final String email;

  const ClassInfo({
    required this.grade,
    required this.classNum,
    required this.email,
  });
}

class AuthService {
  static String get _apiKey => AppConfig.firebaseApiKey;
  static String get _firestoreBase => AppConfig.firestoreBase;

  // SharedPreferences keys
  static const String _keyEmail = 'auth_email';
  static const String _keyRegion = 'auth_region';
  static const String _keySchool = 'auth_school';
  static const String _keyGrade = 'auth_grade';
  static const String _keyClass = 'auth_class';
  static const String _keyLoggedIn = 'auth_logged_in';

  /// 한글 자소를 두벌식 키보드 기준으로 영문으로 1:1 매핑 변환
  static String koreanToEnglishKeyboard(String text) {
    const cho = ['r', 'R', 's', 'e', 'E', 'f', 'a', 'q', 'Q', 't', 'T', 'd', 'w', 'W', 'c', 'z', 'x', 'v', 'g'];
    const jung = ['k', 'o', 'i', 'O', 'j', 'p', 'u', 'P', 'h', 'hk', 'ho', 'hl', 'y', 'n', 'nj', 'np', 'nl', 'b', 'm', 'ml', 'l'];
    const jong = ['', 'r', 'R', 'rt', 's', 'sw', 'sg', 'e', 'f', 'fr', 'fa', 'fq', 'ft', 'fx', 'fv', 'fg', 'a', 'q', 'qt', 't', 'T', 'd', 'w', 'c', 'z', 'x', 'v', 'g'];

    final result = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code >= 0xAC00 && code <= 0xD7A3) {
        final base = code - 0xAC00;
        final c = base ~/ (21 * 28);
        final ju = (base % (21 * 28)) ~/ 28;
        final jo = base % 28;
        result.write(cho[c]);
        result.write(jung[ju]);
        if (jo != 0) {
          result.write(jong[jo]);
        }
      } else {
        if (code >= 0x3131 && code <= 0x314E) {
          const jamoCho = {
            0x3131: 'r', 0x3132: 'R', 0x3134: 's', 0x3137: 'e', 0x3138: 'E',
            0x3139: 'f', 0x3141: 'a', 0x3142: 'q', 0x3143: 'Q', 0x3145: 't',
            0x3146: 'T', 0x3147: 'd', 0x3148: 'w', 0x3149: 'W', 0x314A: 'c',
            0x314B: 'z', 0x314C: 'x', 0x314D: 'v', 0x314E: 'g'
          };
          result.write(jamoCho[code] ?? String.fromCharCode(code));
        } else if (code >= 0x314F && code <= 0x3163) {
          const jamoJung = {
            0x314F: 'k', 0x3150: 'o', 0x3151: 'i', 0x3152: 'O', 0x3153: 'j',
            0x3154: 'p', 0x3155: 'u', 0x3156: 'P', 0x3157: 'h', 0x3158: 'hk',
            0x3159: 'ho', 0x315A: 'hl', 0x315B: 'y', 0x315C: 'n', 0x315D: 'nj',
            0x315E: 'np', 0x315F: 'nl', 0x3160: 'b', 0x3161: 'm', 0x3162: 'ml',
            0x3163: 'l'
          };
          result.write(jamoJung[code] ?? String.fromCharCode(code));
        } else {
          result.write(String.fromCharCode(code));
        }
      }
    }
    return result.toString();
  }

  /// 이메일 포맷 생성: Class.{학년}{반}@{학교명}.{지역명}.bst
  static String buildEmail({
    required String school,
    required String region,
    required int grade,
    required int classNum,
  }) {
    final classStr = '${grade}${classNum.toString().padLeft(2, '0')}';
    return 'Class.$classStr@$school.$region.bst';
  }

  /// 교실 계정 이메일 생성: Class.{학년}{반}@{학교명}.{지역명}.nopw.bst
  static String buildClassEmail({
    required String school,
    required String region,
    required int grade,
    required int classNum,
    bool isSpecial = false,
    String specialId = '',
  }) {
    if (isSpecial && specialId.trim().isNotEmpty) {
      final cleanId = specialId.trim().replaceAll(' ', '');
      return 'Class.$cleanId@$school.$region.nopw.bst';
    }
    final classStr = '${grade}${classNum.toString().padLeft(2, '0')}';
    return 'Class.$classStr@$school.$region.nopw.bst';
  }

  /// SHA-256 비밀번호 해싱
  static String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  /// Firestore 문서 ID 인코딩 (슬래시만 인코딩, 한글 허용)
  static String _encodeDocId(String email) {
    return Uri.encodeComponent(email);
  }

  /// Firestore 문서 URL 생성
  static String _userDocUrl(String email) {
    return '$_firestoreBase/users/${_encodeDocId(email)}?key=$_apiKey';
  }

  /// 특정 이메일(계정)이 이미 존재하는지 백그라운드 체크
  Future<bool> checkAccountExists(String email) async {
    final url = _userDocUrl(email);
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// 현재 로그인된 사용자 반환 (null이면 미로그인)
  Future<BoardestUser?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final loggedIn = prefs.getBool(_keyLoggedIn) ?? false;
    if (!loggedIn) return null;
    final email = prefs.getString(_keyEmail);
    if (email == null || email.isEmpty) return null;
    return BoardestUser.fromPrefs(prefs);
  }

  /// 회원가입
  /// 반환: null이면 성공, String이면 오류 메시지
  Future<String?> signup({
    required String region,
    required String school,
    required int grade,
    required int classNum,
    required String password,
  }) async {
    if (password.length < 6) {
      return '비밀번호는 최소 6자 이상이어야 합니다.';
    }

    final email = buildEmail(
      school: school,
      region: region,
      grade: grade,
      classNum: classNum,
    );
    final url = _userDocUrl(email);

    try {
      // 중복 확인
      final checkRes = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));

      if (checkRes.statusCode == 200) {
        return '이미 등록된 계정입니다. 로그인으로 시도해 주세요.\n($email)';
      }

      // 문서 생성
      final body = {
        'fields': {
          'region': {'stringValue': region},
          'school': {'stringValue': school},
          'grade': {'integerValue': '$grade'},
          'class': {'integerValue': '$classNum'},
          'email': {'stringValue': email},
          'passwordHash': {'stringValue': _hashPassword(password)},
          'createdAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        }
      };

      final createRes = await http
          .patch(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 8));

      if (createRes.statusCode == 200) {
        await _saveSession(
          region: region,
          school: school,
          grade: grade,
          classNum: classNum,
          email: email,
        );
        return null; // 성공
      } else {
        debugPrint('[AuthService] signup error: ${createRes.body}');
        return '회원가입 중 오류가 발생했습니다. (${createRes.statusCode})';
      }
    } catch (e) {
      return '서버와 연결할 수 없습니다. 인터넷 연결을 확인해 주세요.\n($e)';
    }
  }

  /// 로그인
  /// 반환: null이면 성공, String이면 오류 메시지
  Future<String?> login({
    required String region,
    required String school,
    required int grade,
    required int classNum,
    required String password,
  }) async {
    final email = buildEmail(
      school: school,
      region: region,
      grade: grade,
      classNum: classNum,
    );
    final url = _userDocUrl(email);

    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 404) {
        return '등록되지 않은 계정입니다. 회원가입 후 이용해 주세요.';
      }

      if (res.statusCode != 200) {
        return '서버 오류가 발생했습니다. (${res.statusCode})';
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final fields = data['fields'] as Map<String, dynamic>?;
      if (fields == null) {
        return '사용자 데이터가 손상되었습니다.';
      }

      final storedHash =
          (fields['passwordHash'] as Map?)?['stringValue'] as String?;
      if (storedHash == null || storedHash != _hashPassword(password)) {
        return '비밀번호가 올바르지 않습니다.';
      }

      await _saveSession(
        region: region,
        school: school,
        grade: grade,
        classNum: classNum,
        email: email,
      );
      debugPrint('[AuthService] 회원가입 성공: $email (학년: $grade, 반: $classNum)');
      return null; // 성공
    } catch (e) {
      return '서버와 연결할 수 없습니다. 인터넷 연결을 확인해 주세요.\n($e)';
    }
  }

  /// 로그아웃 (로컬 세션만 삭제)
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyRegion);
    await prefs.remove(_keySchool);
    await prefs.remove(_keyGrade);
    await prefs.remove(_keyClass);
    await prefs.remove(_keyLoggedIn);
  }

  /// 회원 탈퇴 (비번 확인 후 Firestore 문서 삭제)
  /// 반환: null이면 성공, String이면 오류 메시지
  Future<String?> deleteAccount({required String password}) async {
    final user = await getCurrentUser();
    if (user == null) return '로그인 상태가 아닙니다.';

    String activePassword = password;
    if (user.email.startsWith('Class.')) {
      activePassword = '!Flutter-app@Class#acc${user.grade}%${user.classNum}^${koreanToEnglishKeyboard(user.school)}';
    } else if (user.email.startsWith('Teacher.')) {
      final emailPart = user.email.split('@')[0];
      final teacherName = emailPart.length > 8 ? emailPart.substring(8) : '';
      activePassword = '!Temp@Teacher#acc\$${koreanToEnglishKeyboard(teacherName)}%${koreanToEnglishKeyboard(user.school)}';
    }

    // 비밀번호 재확인 (임시/교실 계정 포함 지원하기 위해 loginWithRawPassword 사용)
    final loginErr = await loginWithRawPassword(
      email: user.email,
      password: activePassword,
    );
    if (loginErr != null) return loginErr;

    final url = _userDocUrl(user.email);
    try {
      final res = await http
          .delete(Uri.parse(url))
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200 || res.statusCode == 204) {
        await logout();
        return null; // 성공
      } else {
        return '탈퇴 처리 중 오류가 발생했습니다. (${res.statusCode})';
      }
    } catch (e) {
      return '서버와 연결할 수 없습니다.\n($e)';
    }
  }

  /// 같은 학교의 모든 반 조회 (급식 호출 등)
  Future<List<ClassInfo>> getSchoolClassmates({
    required String school,
    required String region,
  }) async {
    final queryUrl = '$_firestoreBase:runQuery?key=$_apiKey';
    final body = {
      'structuredQuery': {
        'from': [
          {'collectionId': 'users'}
        ],
        'where': {
          'compositeFilter': {
            'op': 'AND',
            'filters': [
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'school'},
                  'op': 'EQUAL',
                  'value': {'stringValue': school},
                }
              },
              {
                'fieldFilter': {
                  'field': {'fieldPath': 'region'},
                  'op': 'EQUAL',
                  'value': {'stringValue': region},
                }
              },
            ]
          }
        },
        'orderBy': [
          {
            'field': {'fieldPath': 'grade'},
            'direction': 'ASCENDING'
          },
          {
            'field': {'fieldPath': 'class'},
            'direction': 'ASCENDING'
          },
        ],
      }
    };

    try {
      final res = await http
          .post(
            Uri.parse(queryUrl),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return [];

      final results = json.decode(res.body) as List<dynamic>;
      final classes = <ClassInfo>[];

      for (final item in results) {
        final doc = (item as Map<String, dynamic>)['document'];
        if (doc == null) continue;
        final fields = doc['fields'] as Map<String, dynamic>?;
        if (fields == null) continue;

        final grade =
            int.tryParse((fields['grade'] as Map?)?['integerValue'] ?? '0') ??
                0;
        final classNum =
            int.tryParse((fields['class'] as Map?)?['integerValue'] ?? '0') ??
                0;
        final email =
            (fields['email'] as Map?)?['stringValue'] as String? ?? '';

        if (grade > 0 && classNum > 0) {
          classes.add(ClassInfo(grade: grade, classNum: classNum, email: email));
        }
      }

      return classes;
    } catch (e) {
      debugPrint('[AuthService] getSchoolClassmates error: $e');
      return [];
    }
  }

  /// 교실(Class) 계정 자동 로그인 / 회원가입 통합 처리
  /// 비밀번호 입력 없이, 내부 규칙에 의해 자동 생성 및 로그인
  Future<String?> loginOrSignupClass({
    required String region,
    required String school,
    required int grade,
    required int classNum,
    bool isSpecial = false,
    String specialId = '',
  }) async {
    final email = buildClassEmail(
      school: school,
      region: region,
      grade: grade,
      classNum: classNum,
      isSpecial: isSpecial,
      specialId: specialId,
    );
    final password = isSpecial
        ? '!Flutter-app@Class#special\$${specialId.trim()}^${koreanToEnglishKeyboard(school)}'
        : '!Flutter-app@Class#acc$grade%$classNum^${koreanToEnglishKeyboard(school)}';
    
    final exists = await checkAccountExists(email);
    if (exists) {
      // 로그인 시도
      return await loginWithRawPassword(email: email, password: password);
    } else {
      // 회원가입 시도
      return await signupWithRawPassword(
        region: region,
        school: school,
        grade: grade,
        classNum: classNum,
        email: email,
        password: password,
      );
    }
  }

  /// 커스텀 이메일 및 로 패스워드를 사용하는 회원가입
  Future<String?> signupWithRawPassword({
    required String region,
    required String school,
    required int grade,
    required int classNum,
    required String email,
    required String password,
  }) async {
    final url = _userDocUrl(email);
    try {
      final checkRes = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (checkRes.statusCode == 200) {
        return '이미 등록된 계정입니다. 로그인으로 시도해 주세요.';
      }

      final body = {
        'fields': {
          'region': {'stringValue': region},
          'school': {'stringValue': school},
          'grade': {'integerValue': '$grade'},
          'class': {'integerValue': '$classNum'},
          'email': {'stringValue': email},
          'passwordHash': {'stringValue': _hashPassword(password)},
          'createdAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        }
      };

      final createRes = await http
          .patch(
            Uri.parse(url),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(body),
          )
          .timeout(const Duration(seconds: 8));

      if (createRes.statusCode == 200) {
        await _saveSession(
          region: region,
          school: school,
          grade: grade,
          classNum: classNum,
          email: email,
        );
        return null; // 성공
      } else {
        return '회원가입 중 오류가 발생했습니다. (${createRes.statusCode})';
      }
    } catch (e) {
      return '서버와 연결할 수 없습니다.\n($e)';
    }
  }

  /// 커스텀 이메일 및 로 패스워드를 사용하는 로그인
  Future<String?> loginWithRawPassword({
    required String email,
    required String password,
  }) async {
    final url = _userDocUrl(email);
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (res.statusCode == 404) {
        return '등록되지 않은 계정입니다.';
      }
      if (res.statusCode != 200) {
        return '서버 오류가 발생했습니다. (${res.statusCode})';
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final fields = data['fields'] as Map<String, dynamic>?;
      if (fields == null) return '사용자 데이터가 손상되었습니다.';

      final storedHash = (fields['passwordHash'] as Map?)?['stringValue'] as String?;
      if (storedHash == null || storedHash != _hashPassword(password)) {
        return '비밀번호가 올바르지 않습니다.';
      }

      final region = (fields['region'] as Map?)?['stringValue'] as String? ?? '';
      final school = (fields['school'] as Map?)?['stringValue'] as String? ?? '';
      final grade = int.tryParse((fields['grade'] as Map?)?['integerValue'] ?? '0') ?? 0;
      final classNum = int.tryParse((fields['class'] as Map?)?['integerValue'] ?? '0') ?? 0;

      await _saveSession(
        region: region,
        school: school,
        grade: grade,
        classNum: classNum,
        email: email,
      );
      return null; // 성공
    } catch (e) {
      return '서버와 연결할 수 없습니다.\n($e)';
    }
  }

  /// Firestore에 사용자의 lastActive 시간만 업데이트 (온라인 상태 알림용)
  Future<void> updateOnlineStatus(String email) async {
    final url = '$_firestoreBase/users/${_encodeDocId(email)}?updateMask.fieldPaths=lastActive&key=$_apiKey';
    try {
      final body = {
        'fields': {
          'lastActive': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        }
      };
      
      final res = await http.patch(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      ).timeout(const Duration(seconds: 5));
      
      if (res.statusCode == 200) {
        debugPrint('[AuthService] Successfully updated online status for $email');
      } else {
        debugPrint('[AuthService] Failed to update online status: ${res.body}');
      }
    } catch (e) {
      debugPrint('[AuthService] updateOnlineStatus network error: $e');
    }
  }

  /// 세션 저장
  Future<void> _saveSession({
    required String region,
    required String school,
    required int grade,
    required int classNum,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyRegion, region);
    await prefs.setString(_keySchool, school);
    await prefs.setInt(_keyGrade, grade);
    await prefs.setInt(_keyClass, classNum);
    await prefs.setBool(_keyLoggedIn, true);
  }
}
