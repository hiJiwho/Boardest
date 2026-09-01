import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bst_cloud/bst_cloud.dart';

void main() {
  group('CloudFile Model Tests', () {
    test('CloudFile serialization and deserialization', () {
      final now = DateTime.utc(2026, 8, 21, 12, 0, 0);
      final file = CloudFile(
        id: 'file_123',
        name: 'Lesson1.tbp',
        mimeType: 'application/octet-stream',
        size: 10240,
        modifiedTime: now,
        downloadUrl: 'https://drive.google.com/download/file_123',
        thumbnailUrl: 'https://drive.google.com/thumbnail/file_123',
      );

      expect(file.isTbp, isTrue);
      expect(file.isPdf, isFalse);
      expect(file.isFolder, isFalse);

      final json = file.toJson();
      expect(json['id'], 'file_123');
      expect(json['name'], 'Lesson1.tbp');
      expect(json['size'], 10240);

      final restored = CloudFile.fromJson(json);
      expect(restored.id, 'file_123');
      expect(restored.name, 'Lesson1.tbp');
      expect(restored.size, 10240);
      expect(restored.modifiedTime, now);
      expect(restored.downloadUrl, contains('file_123'));
      expect(restored.thumbnailUrl, contains('file_123'));
    });

    test('CloudFile mime type detection for PDF and Folder', () {
      final pdfFile = CloudFile(
        id: 'pdf_1',
        name: 'syllabus.pdf',
        mimeType: 'application/pdf',
        size: 500,
        modifiedTime: DateTime.now(),
      );
      expect(pdfFile.isPdf, isTrue);
      expect(pdfFile.isTbp, isFalse);

      final folder = CloudFile(
        id: 'folder_1',
        name: 'Curriculum',
        mimeType: 'application/vnd.google-apps.folder',
        size: 0,
        modifiedTime: DateTime.now(),
      );
      expect(folder.isFolder, isTrue);
    });
  });

  group('CloudDriveService Tests', () {
    test('CloudDriveService manages cached files and sync status lifecycle', () async {
      final service = CloudDriveService();
      expect(service.status, equals(CloudSyncStatus.idle));
      expect(service.cachedFiles, isEmpty);

      final file1 = CloudFile(
        id: '1',
        name: 'math.tbp',
        mimeType: 'application/octet-stream',
        size: 200,
        modifiedTime: DateTime.now(),
      );
      final file2 = CloudFile(
        id: '2',
        name: 'science.tbp',
        mimeType: 'application/octet-stream',
        size: 400,
        modifiedTime: DateTime.now(),
      );

      service.setFiles([file1]);
      expect(service.cachedFiles.length, 1);

      service.addFile(file2);
      expect(service.cachedFiles.length, 2);

      service.removeFile('1');
      expect(service.cachedFiles.length, 1);
      expect(service.cachedFiles.first.id, '2');

      final statuses = <CloudSyncStatus>[];
      final sub = service.statusStream.listen(statuses.add);

      await service.syncFiles();
      await Future.delayed(const Duration(milliseconds: 20));
      expect(service.status, equals(CloudSyncStatus.completed));
      expect(statuses, containsAll([CloudSyncStatus.syncing, CloudSyncStatus.completed]));

      await sub.cancel();
      service.dispose();
    });
  });

  group('DriveCastViewer Widget Test', () {
    testWidgets('DriveCastViewer renders correctly', (tester) async {
      await tester.pumpWidget(
        const TestAppWrapper(child: DriveCastViewer()),
      );
      expect(find.text('DriveCast Viewer'), findsOneWidget);
    });
  });
}

class TestAppWrapper extends StatelessWidget {
  final Widget child;
  const TestAppWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: child,
    );
  }
}
