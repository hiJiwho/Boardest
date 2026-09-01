import 'sub_apis/bst_ui_api.dart';
import 'sub_apis/bst_session_api.dart';
import 'sub_apis/bst_storage_api.dart';
import 'sub_apis/bst_events_api.dart';
import 'sub_apis/bst_cloud_api.dart';
import 'sub_apis/bst_cast_api.dart';

/// Boardest Core API Facade (플러그인이 호스트와 통신하는 메인 진입점)
class BstApi {
  final BstUiApi ui;
  final BstSessionApi session;
  final BstStorageApi storage;
  final BstEventsApi events;
  final BstCloudApi cloud;
  final BstCastApi cast;

  const BstApi({
    required this.ui,
    required this.session,
    required this.storage,
    required this.events,
    required this.cloud,
    required this.cast,
  });

  static BstApi? _instance;
  static BstApi get instance {
    if (_instance == null) {
      throw StateError('BstApi has not been initialized by the host application.');
    }
    return _instance!;
  }

  /// 호스트 애플리케이션에서 BstApi 구현체를 전역 등록할 때 호출
  static void registerHostApi(BstApi api) {
    _instance = api;
  }
}
