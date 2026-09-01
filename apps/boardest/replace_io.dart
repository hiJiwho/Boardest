import 'dart:io';

void main() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    print('lib directory not found');
    return;
  }

  int count = 0;
  final files = libDir.listSync(recursive: true);
  for (final file in files) {
    if (file is File && file.path.endsWith('.dart')) {
      final content = file.readAsStringSync();
      if (content.contains("import 'dart:io';")) {
        final newContent = content.replaceAll("import 'dart:io';", "import 'package:universal_io/io.dart';");
        file.writeAsStringSync(newContent);
        count++;
        print('Replaced in ${file.path}');
      }
    }
  }
  print('Total $count files updated.');
}
