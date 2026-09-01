// win32_stub.dart
// Web 및 Android 환경에서 컴파일 에러를 회피하기 위한 스텁 파일입니다.
// 윈도우 전용 코드를 깡통으로 처리합니다.

class HWND {}
class Struct {}
class Pointer<T> {}

const int NULL = 0;
const int FALSE = 0;
const int TRUE = 1;

void SetForegroundWindow(int hwnd) {}
void ShowWindow(int hwnd, int nCmdShow) {}
int FindWindow(String? className, String? windowName) => 0;

dynamic TEXT(String s) => null;
int GetDriveType(dynamic ptr) => 0;
const int DRIVE_REMOVABLE = 2;
void free(dynamic ptr) {}
