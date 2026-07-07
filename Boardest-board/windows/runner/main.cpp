#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Single Instance Check: Find existing window with Flutter class and title L"boardest"
  HWND existing_hwnd = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"boardest");
  if (existing_hwnd != nullptr) {
    std::vector<std::string> args = GetCommandLineArguments();
    std::string arg_to_send = "";
    // Grab the first custom argument if present (skip exe path at args[0])
    for (size_t i = 1; i < args.size(); ++i) {
      if (args[i][0] == '-') {
        arg_to_send = args[i];
        break;
      }
    }

    if (!arg_to_send.empty()) {
      COPYDATASTRUCT cds;
      cds.dwData = 1;
      cds.cbData = static_cast<DWORD>(arg_to_send.size() + 1);
      cds.lpData = const_cast<char*>(arg_to_send.c_str());
      ::SendMessageA(existing_hwnd, WM_COPYDATA, (WPARAM)nullptr, (LPARAM)&cds);
    }

    // Activate the existing instance
    ::ShowWindow(existing_hwnd, SW_RESTORE);
    ::SetForegroundWindow(existing_hwnd);

    return EXIT_SUCCESS;
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
  if (!window.Create(L"boardest", origin, size)) {
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
