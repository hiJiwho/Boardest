import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

void main() async {
  const String _projectId = 'jiwhosboardest';
  const String _apiKey = 'AIzaSyBMoJZHMBN4eYJtiZR2iGePcmIB7bg8wGo';
  const String _firestoreBase = 'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents';

  final region = 'seoul';
  final school = 'yangdong';
  final grade = 2;
  final classNum = 1;
  final email = 'G${grade}C$classNum@$school.$region.bst';
  final password = '123456';
  
  final url = '$_firestoreBase/users/${Uri.encodeComponent(email)}?key=$_apiKey';

  final bytes = utf8.encode(password);
  final hash = sha256.convert(bytes).toString();

  // Let's do a GET first
  print('GET request to $url');
  final getRes = await http.get(Uri.parse(url));
  print('GET status: ${getRes.statusCode}');
  print('GET body: ${getRes.body}');

  final body = {
    'fields': {
      'region': {'stringValue': region},
      'school': {'stringValue': school},
      'grade': {'integerValue': '$grade'},
      'class': {'integerValue': '$classNum'},
      'email': {'stringValue': email},
      'passwordHash': {'stringValue': hash},
      'createdAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
    }
  };

  print('PATCH request to $url');
  final patchRes = await http.patch(
    Uri.parse(url),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(body),
  );
  print('PATCH status: ${patchRes.statusCode}');
  print('PATCH body: ${patchRes.body}');
}
