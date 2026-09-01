import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class WebFolderFile {
  final String relativePath;
  final String name;
  final Uint8List bytes;

  WebFolderFile({required this.relativePath, required this.name, required this.bytes});
}

Future<List<WebFolderFile>> pickFolderFilesWeb() async {
  final completer = Completer<List<WebFolderFile>>();
  final uploadInput = html.FileUploadInputElement();
  uploadInput.setAttribute('webkitdirectory', '');
  uploadInput.setAttribute('directory', '');
  uploadInput.multiple = true;
  uploadInput.style.display = 'none';
  html.document.body?.append(uploadInput);

  uploadInput.onChange.listen((e) async {
    final files = uploadInput.files;
    if (files == null || files.isEmpty) {
      if (!completer.isCompleted) completer.complete([]);
      uploadInput.remove();
      return;
    }

    final List<WebFolderFile> result = [];
    int remaining = files.length;

    for (final file in files) {
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      reader.onLoadEnd.listen((_) {
        final res = reader.result;
        Uint8List? bytes;
        if (res is Uint8List) {
          bytes = res;
        } else if (res is ByteBuffer) {
          bytes = Uint8List.view(res);
        } else if (res is List<int>) {
          bytes = Uint8List.fromList(res);
        }

        if (bytes != null) {
          final relPath = (file as dynamic).webkitRelativePath as String? ?? file.name;
          result.add(WebFolderFile(relativePath: relPath, name: file.name, bytes: bytes));
        }
        remaining--;
        if (remaining <= 0 && !completer.isCompleted) {
          completer.complete(result);
          uploadInput.remove();
        }
      });
      reader.onError.listen((_) {
        remaining--;
        if (remaining <= 0 && !completer.isCompleted) {
          completer.complete(result);
          uploadInput.remove();
        }
      });
    }
  });

  uploadInput.click();
  return completer.future;
}
