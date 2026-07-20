#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

void RegisterBsttProtocol() {
  wchar_t exePath[MAX_PATH];
  GetModuleFileNameW(NULL, exePath, MAX_PATH);

  HKEY hKey;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Classes\\Bst-t", 0, NULL,
                      0, KEY_WRITE, NULL, &hKey, NULL) == ERROR_SUCCESS) {
    RegSetValueExW(hKey, NULL, 0, REG_SZ, (const BYTE*)L"URL:Bst-t Protocol", sizeof(L"URL:Bst-t Protocol"));
    RegSetValueExW(hKey, L"URL Protocol", 0, REG_SZ, (const BYTE*)L"", sizeof(L""));
    
    HKEY hCommandKey;
    std::wstring cmd = std::wstring(L"\"") + exePath + L"\" \"%1\"";
    if (RegCreateKeyExW(hKey, L"shell\\open\\command", 0, NULL, 0,
                        KEY_WRITE, NULL, &hCommandKey, NULL) == ERROR_SUCCESS) {
      RegSetValueExW(hCommandKey, NULL, 0, REG_SZ, (const BYTE*)cmd.c_str(),
                     (DWORD)((cmd.length() + 1) * sizeof(wchar_t)));
      RegCloseKey(hCommandKey);
    }
    RegCloseKey(hKey);
  }
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  RegisterBsttProtocol();
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS)) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"boardest_teacher", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
