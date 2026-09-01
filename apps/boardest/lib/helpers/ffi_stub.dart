// ffi_stub.dart
// Web 및 Android 환경에서 ffi 패키지 및 dart:ffi 에러를 회피하기 위한 스텁 파일입니다.

class Pointer<T> {
  void free(Pointer<T> ptr) {}
}
class NativeType {}
class Void extends NativeType {}
class Uint8 extends NativeType {}
class Uint16 extends NativeType {}
class Uint32 extends NativeType {}
class IntPtr extends NativeType {}
class NativeFunction<T> extends NativeType {}
class Utf8 extends NativeType {}
class Utf16 extends NativeType {}

class _NativeFunctionStub {
  dynamic asFunction<T>() => (dynamic a, [dynamic b, dynamic c, dynamic d]) {};
}

class DynamicLibrary {
  static DynamicLibrary open(String path) => DynamicLibrary();
  _NativeFunctionStub lookup<T>(String symbolName) => _NativeFunctionStub();
}

final malloc = _AllocatorStub();
final calloc = _AllocatorStub();

class _AllocatorStub {
  Pointer<T> call<T extends NativeType>(int byteCount, {int? alignment}) {
    return Pointer<T>();
  }
  void free(Pointer ptr) {}
}

extension StringUtf16Pointer on String {
  Pointer<Utf16> toNativeUtf16() => Pointer<Utf16>();
}

int GetDriveType(Pointer<Utf16> lpRootPathName) => 0;
const int DRIVE_REMOVABLE = 2;
