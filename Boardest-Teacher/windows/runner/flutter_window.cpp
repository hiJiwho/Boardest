#include "flutter_window.h"

#include <optional>
#include <fstream>
#include <string>
#include <winbase.h>

#include "flutter/generated_plugin_registrant.h"

#include <dwmapi.h>
#pragma comment(lib, "dwmapi.lib")
#include <uxtheme.h>
#pragma comment(lib, "uxtheme.lib")

struct EnumChildData {
  HWND flutterViewHwnd;
  bool clickThrough;
};

BOOL CALLBACK EnumChildProc(HWND hwnd, LPARAM lParam) {
  EnumChildData* data = reinterpret_cast<EnumChildData*>(lParam);
  if (hwnd != data->flutterViewHwnd) {
    // Disable native window to prevent it from intercepting mouse clicks
    // When disabled, mouse clicks fall through to the parent window (the Flutter view)
    EnableWindow(hwnd, data->clickThrough ? FALSE : TRUE);
    
    // Toggle WS_EX_TRANSPARENT extended style so mouse clicks pass through
    LONG exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
    if (data->clickThrough) {
      SetWindowLong(hwnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED | WS_EX_TRANSPARENT);
    } else {
      SetWindowLong(hwnd, GWL_EXSTYLE, exStyle & ~(WS_EX_LAYERED | WS_EX_TRANSPARENT));
    }
    
    // Force redraw to apply changes
    SetWindowPos(hwnd, NULL, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  }
  return TRUE;
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Initialize the method channel for communicating with Dart
  method_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "com.boardest/launch_args",
      &flutter::StandardMethodCodec::GetInstance());

  method_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        HWND hwnd = this->GetHandle();
        
        // Capture initial window style if not saved yet
        if (original_style_ == 0) {
          original_style_ = GetWindowLong(hwnd, GWL_STYLE);
          if (original_style_ == 0) {
            original_style_ = WS_OVERLAPPEDWINDOW;
          }
        }

        if (call.method_name() == "triggerSleep") {
          SendMessage(HWND_BROADCAST, WM_SYSCOMMAND, SC_MONITORPOWER, (LPARAM)2);
          result->Success();
        } else if (call.method_name() == "wakeFromSleep") {
          SetThreadExecutionState(ES_DISPLAY_REQUIRED | ES_SYSTEM_REQUIRED);
          SendMessage(HWND_BROADCAST, WM_SYSCOMMAND, SC_MONITORPOWER, (LPARAM)-1);
          if (hwnd != nullptr) {
            SetForegroundWindow(hwnd);
          }
          result->Success();
        } else if (call.method_name() == "minimizeWindow") {
          if (hwnd != nullptr) {
            ShowWindow(hwnd, SW_MINIMIZE);
          }
          result->Success();
        } else if (call.method_name() == "restoreWindow") {
          if (hwnd != nullptr) {
            ShowWindow(hwnd, SW_RESTORE);
            BringWindowToTop(hwnd);
            SetForegroundWindow(hwnd);
          }
          result->Success();
        } else if (call.method_name() == "setSpecialClassroomMode") {
          int mode_type = 0;
          if (call.arguments()) {
            if (auto p_int = std::get_if<int>(call.arguments())) {
              mode_type = *p_int;
            } else if (auto p_bool = std::get_if<bool>(call.arguments())) {
              mode_type = *p_bool ? 3 : 0;
            }
          }
          
          special_classroom_type_ = mode_type;
          
          LONG style = original_style_;
          style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU);
          SetWindowLong(hwnd, GWL_STYLE, style);

          HMONITOR hmon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
          MONITORINFO mi = { sizeof(MONITORINFO) };
          if (GetMonitorInfo(hmon, &mi)) {
            if (special_classroom_type_ == 3) {
              int screenWidth = mi.rcWork.right - mi.rcWork.left;
              int screenHeight = mi.rcWork.bottom - mi.rcWork.top;
              int targetWidth = static_cast<int>(screenWidth * 0.40);
              int targetLeft = mi.rcWork.right - targetWidth;

              SetWindowPos(hwnd, HWND_NOTOPMOST,
                           targetLeft,
                           mi.rcWork.top,
                           targetWidth,
                           screenHeight,
                           SWP_FRAMECHANGED | SWP_NOACTIVATE);
            } else {
              SetWindowPos(hwnd, HWND_NOTOPMOST,
                           mi.rcWork.left,
                           mi.rcWork.top,
                           mi.rcWork.right - mi.rcWork.left,
                           mi.rcWork.bottom - mi.rcWork.top,
                           SWP_FRAMECHANGED | SWP_NOACTIVATE);
            }
          }
          result->Success();
        } else if (call.method_name() == "setWindowTransparency") {
          int mode = 0; // 0 = Solid, 1 = Clickable Pen, 2 = Click-Through Mouse
          if (call.arguments()) {
            if (auto p_val = std::get_if<int>(call.arguments())) {
              mode = *p_val;
            } else if (auto p_bool = std::get_if<bool>(call.arguments())) {
              mode = *p_bool ? 1 : 0;
            }
          }
          
          OutputDebugStringW((L"[FlutterWindow] setWindowTransparency called with mode=" + std::to_wstring(mode) + L"\n").c_str());
          
          if (mode == 1 || mode == 2) {
            OutputDebugStringW(L"[FlutterWindow] Applying transparency mode (Layered + TopMost)\n");
            
            // Apply Near-Black Color Key (RGB 1,1,1) instead of pure black to avoid HitTest issues
            // Near-black is visually indistinguishable but prevents Windows from excluding pixels during HitTest
            SetWindowLong(hwnd, GWL_EXSTYLE, GetWindowLong(hwnd, GWL_EXSTYLE) | WS_EX_LAYERED);
            SetLayeredWindowAttributes(hwnd, RGB(1, 1, 1), 0, LWA_COLORKEY);
            
            // Go full-screen borderless topmost for transparent drawing overlay!
            LONG style = original_style_;
            style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU);
            SetWindowLong(hwnd, GWL_STYLE, style);

            HMONITOR hmon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
            MONITORINFO mi = { sizeof(MONITORINFO) };
            if (GetMonitorInfo(hmon, &mi)) {
              SetWindowPos(hwnd, HWND_TOPMOST,
                           mi.rcMonitor.left,
                           mi.rcMonitor.top,
                           mi.rcMonitor.right - mi.rcMonitor.left,
                           mi.rcMonitor.bottom - mi.rcMonitor.top,
                           SWP_FRAMECHANGED | SWP_SHOWWINDOW);
              BringWindowToTop(hwnd);
              SetForegroundWindow(hwnd);
              OutputDebugStringW(L"[FlutterWindow] Window set to TOPMOST and activated with full-screen layered transparency\n");
            }
          } else {
            OutputDebugStringW(L"[FlutterWindow] Removing transparency mode (Solid)\n");
            
            // Remove layered style to restore original solid appearance
            SetWindowLong(hwnd, GWL_EXSTYLE, GetWindowLong(hwnd, GWL_EXSTYLE) & ~WS_EX_LAYERED);
            RedrawWindow(hwnd, NULL, NULL, RDW_INVALIDATE | RDW_UPDATENOW);
            
            if (special_classroom_type_ == 3) {
              // Stay in Special Classroom Mode (right 40% NOTOPMOST)
              LONG style = original_style_;
              style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU);
              SetWindowLong(hwnd, GWL_STYLE, style);

              HMONITOR hmon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
              MONITORINFO mi = { sizeof(MONITORINFO) };
              if (GetMonitorInfo(hmon, &mi)) {
                int screenWidth = mi.rcWork.right - mi.rcWork.left;
                int screenHeight = mi.rcWork.bottom - mi.rcWork.top;
                int targetWidth = static_cast<int>(screenWidth * 0.40);
                int targetLeft = mi.rcWork.right - targetWidth;

                SetWindowPos(hwnd, HWND_NOTOPMOST,
                             targetLeft,
                             mi.rcWork.top,
                             targetWidth,
                             screenHeight,
                             SWP_FRAMECHANGED | SWP_NOACTIVATE);
              }
            } else {
              // Restore solid borderless maximized to rcWork (shows taskbar, non-topmost)
              LONG style = original_style_;
              style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU);
              SetWindowLong(hwnd, GWL_STYLE, style);

              HMONITOR hmon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
              MONITORINFO mi = { sizeof(MONITORINFO) };
              if (GetMonitorInfo(hmon, &mi)) {
                SetWindowPos(hwnd, HWND_NOTOPMOST,
                             mi.rcWork.left,
                             mi.rcWork.top,
                             mi.rcWork.right - mi.rcWork.left,
                             mi.rcWork.bottom - mi.rcWork.top,
                             SWP_FRAMECHANGED | SWP_NOACTIVATE);
              }
            }
          }
          result->Success();
        } else if (call.method_name() == "setWebviewClickThrough") {
          bool clickThrough = false;
          if (call.arguments()) {
            if (auto p_bool = std::get_if<bool>(call.arguments())) {
              clickThrough = *p_bool;
            }
          }
          
          // Use the outer-scope hwnd (already declared above: HWND hwnd = this->GetHandle())
          HWND flutterViewHwnd = nullptr;
          if (flutter_controller_ && flutter_controller_->view()) {
            flutterViewHwnd = flutter_controller_->view()->GetNativeWindow();
          }
          
          EnumChildData enumData = { flutterViewHwnd, clickThrough };
          EnumChildWindows(hwnd, EnumChildProc, reinterpret_cast<LPARAM>(&enumData));
          
          result->Success();
        } else if (call.method_name() == "setWindowFrameStyle") {
          std::string style = "mac";
          if (call.arguments()) {
            if (auto p_str = std::get_if<std::string>(call.arguments())) {
              style = *p_str;
            }
          }
          window_frame_style_ = style;
          
          #ifndef DWMWA_WINDOW_CORNER_PREFERENCE
          #define DWMWA_WINDOW_CORNER_PREFERENCE 33
          #endif
          enum DWM_WINDOW_CORNER_PREFERENCE {
            DWMWCP_DEFAULT = 0,
            DWMWCP_DONOTROUND = 1,
            DWMWCP_ROUND = 2,
            DWMWCP_ROUNDSMALL = 3
          };
          
          DWM_WINDOW_CORNER_PREFERENCE corner = (window_frame_style_ == "win7") ? DWMWCP_DONOTROUND : DWMWCP_ROUND;
          DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &corner, sizeof(corner));

          SetWindowTheme(hwnd, nullptr, nullptr);
          LONG current_style = GetWindowLong(hwnd, GWL_STYLE);
          current_style &= ~(WS_CAPTION | WS_SYSMENU);
          current_style |= (WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX);
          SetWindowLong(hwnd, GWL_STYLE, current_style);
          SetWindowPos(hwnd, NULL, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);

          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    HWND hwnd = this->GetHandle();
    
    // Save original styles
    original_style_ = GetWindowLong(hwnd, GWL_STYLE);
    if (original_style_ == 0) {
      original_style_ = WS_OVERLAPPEDWINDOW;
    }

    // Check special classroom mode startup file
    int start_special = 0;
    wchar_t exe_path[MAX_PATH];
    if (GetModuleFileName(NULL, exe_path, MAX_PATH)) {
      std::wstring path(exe_path);
      size_t last_slash = path.find_last_of(L"\\/");
      if (last_slash != std::wstring::npos) {
        std::wstring txt_path = path.substr(0, last_slash + 1) + L"special_classroom.txt";
        std::ifstream file(txt_path);
        if (file.is_open()) {
          std::string content;
          file >> content;
          if (content == "true") {
            start_special = 3;
          } else if (content == "false") {
            start_special = 0;
          } else {
            try {
              start_special = std::stoi(content);
            } catch (...) {
              start_special = 0;
            }
          }
        }
      }
    }

    special_classroom_type_ = start_special;

    LONG style = original_style_;
    SetWindowTheme(hwnd, nullptr, nullptr);
    style &= ~(WS_CAPTION | WS_SYSMENU);
    style |= (WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX);

    #ifndef DWMWA_WINDOW_CORNER_PREFERENCE
    #define DWMWA_WINDOW_CORNER_PREFERENCE 33
    #endif
    enum DWM_WINDOW_CORNER_PREFERENCE {
      DWMWCP_DEFAULT = 0,
      DWMWCP_DONOTROUND = 1,
      DWMWCP_ROUND = 2,
      DWMWCP_ROUNDSMALL = 3
    };
    DWM_WINDOW_CORNER_PREFERENCE corner = (window_frame_style_ == "win7") ? DWMWCP_DONOTROUND : DWMWCP_ROUND;
    DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &corner, sizeof(corner));
    SetWindowLong(hwnd, GWL_STYLE, style);

    HMONITOR hmon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFO mi = { sizeof(MONITORINFO) };
    if (GetMonitorInfo(hmon, &mi)) {
      if (special_classroom_type_ == 3) {
        int screenWidth = mi.rcWork.right - mi.rcWork.left;
        int screenHeight = mi.rcWork.bottom - mi.rcWork.top;
        int targetWidth = static_cast<int>(screenWidth * 0.40);
        int targetLeft = mi.rcWork.right - targetWidth;

        SetWindowPos(hwnd, HWND_NOTOPMOST,
                     targetLeft,
                     mi.rcWork.top,
                     targetWidth,
                     screenHeight,
                     SWP_FRAMECHANGED | SWP_SHOWWINDOW);
      } else {
        SetWindowPos(hwnd, HWND_NOTOPMOST,
                     mi.rcWork.left,
                     mi.rcWork.top,
                     mi.rcWork.right - mi.rcWork.left,
                     mi.rcWork.bottom - mi.rcWork.top,
                     SWP_FRAMECHANGED | SWP_SHOWWINDOW);
      }
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (method_channel_) {
    method_channel_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_NCHITTEST) {
    if (!IsZoomed(hwnd)) {
      POINT pt = { LOWORD(lparam), HIWORD(lparam) };
      ScreenToClient(hwnd, &pt);
      RECT rc;
      GetClientRect(hwnd, &rc);
      int borderWidth = 8;

      if (pt.y < borderWidth) {
        if (pt.x < borderWidth) return HTTOPLEFT;
        if (pt.x >= rc.right - borderWidth) return HTTOPRIGHT;
        return HTTOP;
      } else if (pt.y >= rc.bottom - borderWidth) {
        if (pt.x < borderWidth) return HTBOTTOMLEFT;
        if (pt.x >= rc.right - borderWidth) return HTBOTTOMRIGHT;
        return HTBOTTOM;
      } else if (pt.x < borderWidth) {
        return HTLEFT;
      } else if (pt.x >= rc.right - borderWidth) {
        return HTRIGHT;
      }
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_COPYDATA: {
      PCOPYDATASTRUCT pcds = reinterpret_cast<PCOPYDATASTRUCT>(lparam);
      if (pcds != nullptr && pcds->lpData != nullptr) {
        std::string arg(reinterpret_cast<char*>(pcds->lpData), pcds->cbData - 1);
        
        // Send this arg to Dart side using MethodChannel!
        if (method_channel_) {
          method_channel_->InvokeMethod(
              "onNewLaunchArgs",
              std::make_unique<flutter::EncodableValue>(arg));
        }
      }
      return 1; // Handled
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
