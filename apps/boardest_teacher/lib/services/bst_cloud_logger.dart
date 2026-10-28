import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BstAuditLog {
  final String id;
  final String action;
  final String teacherName;
  final String classroomName;
  final String details;
  final DateTime timestamp;

  BstAuditLog({
    required this.id,
    required this.action,
    required this.teacherName,
    required this.classroomName,
    required this.details,
    required this.timestamp,
  });

  factory BstAuditLog.fromJson(Map<String, dynamic> map) {
    return BstAuditLog(
      id: map['id']?.toString() ?? '',
      action: map['action']?.toString() ?? '',
      teacherName: map['teacherName']?.toString() ?? '',
      classroomName: map['classroomName']?.toString() ?? '',
      details: map['details']?.toString() ?? '',
      timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'action': action,
      'teacherName': teacherName,
      'classroomName': classroomName,
      'details': details,
      'timestamp': timestamp.toUtc().toIso8601String(),
    };
  }
}

class BstCloudLogger {
  static final BstCloudLogger instance = BstCloudLogger._();
  BstCloudLogger._();

  static const String _localLogsKey = 'bst_teacher_local_audit_logs_v2';

  /// 로컬 기기(SharedPreferences)에 보안 이벤트 로깅 (Firestore 쓰기 할당량 0회 소모)
  Future<bool> logEvent({
    required String action,
    required String teacherName,
    required String classroomName,
    required String details,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_localLogsKey) ?? [];
      final log = BstAuditLog(
        id: 'log_${DateTime.now().millisecondsSinceEpoch}',
        action: action,
        teacherName: teacherName,
        classroomName: classroomName,
        details: details,
        timestamp: DateTime.now(),
      );
      existing.insert(0, json.encode(log.toJson()));
      if (existing.length > 50) {
        existing.removeRange(50, existing.length);
      }
      await prefs.setStringList(_localLogsKey, existing);
      return true;
    } catch (e) {
      debugPrint('[BstCloudLogger] logEvent error: $e');
      return false;
    }
  }

  /// 최근 감사 로그 조회 (로컬 SharedPreferences 기반, Firestore 읽기 0회)
  Future<List<BstAuditLog>> fetchAuditLogs({int limit = 50}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_localLogsKey) ?? [];
      return existing.take(limit).map((raw) {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        return BstAuditLog.fromJson(decoded);
      }).toList();
    } catch (e) {
      debugPrint('[BstCloudLogger] fetchAuditLogs error: $e');
      return [];
    }
  }
}
