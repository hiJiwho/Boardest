import 'package:universal_io/io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

Future<void> downloadFileImpl(List<int> bytes, String fileName) async {
  try {
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes);
  } catch (_) {}
}
