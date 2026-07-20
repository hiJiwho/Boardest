import 'package:flutter/foundation.dart';

class BstCloudService {
  static final BstCloudService instance = BstCloudService._();
  BstCloudService._();

  final Map<String, dynamic> _syncStateStore = {};
  final Map<String, ValueNotifier<dynamic>> _syncStateNotifiers = {};

  void saveSyncState(String key, dynamic value) {
    _syncStateStore[key] = value;
    if (!_syncStateNotifiers.containsKey(key)) {
      _syncStateNotifiers[key] = ValueNotifier(value);
    } else {
      _syncStateNotifiers[key]!.value = value;
    }
  }

  void listenSyncState(String key, void Function(dynamic value) callback) {
    if (!_syncStateNotifiers.containsKey(key)) {
      _syncStateNotifiers[key] = ValueNotifier(_syncStateStore[key]);
    }
    _syncStateNotifiers[key]!.addListener(() {
      callback(_syncStateNotifiers[key]!.value);
    });
  }
}
