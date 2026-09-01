import 'dart:typed_data';

class WebFolderFile {
  final String relativePath;
  final String name;
  final Uint8List bytes;

  WebFolderFile({required this.relativePath, required this.name, required this.bytes});
}

Future<List<WebFolderFile>> pickFolderFilesWeb() async {
  return [];
}
