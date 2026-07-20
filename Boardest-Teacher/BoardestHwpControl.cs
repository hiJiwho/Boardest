using System;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Reflection;

namespace BoardestHwpControl
{
    /// <summary>
    /// Boardest HWP Controller DLL Library
    /// Provides ActiveX COM automation and process fallback for Hancom Office HWP files.
    /// </summary>
    public class HwpController
    {
        private dynamic _hwpApp;
        private IntPtr _hwpHwnd = IntPtr.Zero;
        private string _openedPath;

        public bool IsOpened { get { return _hwpApp != null; } }
        public IntPtr MainWindowHandle { get { return _hwpHwnd; } }
        public string OpenedFilePath { get { return _openedPath; } }

        /// <summary>
        /// Check if Hancom Office HWP ActiveX COM object is registered on the system
        /// </summary>
        public static bool IsHwpInstalled()
        {
            Type t = Type.GetTypeFromProgID("HWPFrame.HwpObject");
            if (t == null) t = Type.GetTypeFromProgID("HwpObject");
            return t != null;
        }

        /// <summary>
        /// Open an HWP file using COM Automation or system default executable fallback
        /// </summary>
        public bool OpenDocument(string filePath)
        {
            try
            {
                if (!File.Exists(filePath)) return false;
                _openedPath = Path.GetFullPath(filePath);

                Type hwpType = Type.GetTypeFromProgID("HWPFrame.HwpObject");
                if (hwpType == null) hwpType = Type.GetTypeFromProgID("HwpObject");

                if (hwpType != null)
                {
                    _hwpApp = Activator.CreateInstance(hwpType);
                    try { _hwpApp.RegisterModule("FilePathCheckDLL", "FilePathCheckerModule"); } catch {}
                    _hwpApp.Open(_openedPath, "HWP", "");
                    try { _hwpApp.EditMode = 1; } catch {}
                    try { _hwpApp.Run("ViewZoomWidthFit"); } catch {}
                    
                    foreach (var proc in Process.GetProcessesByName("Hwp"))
                    {
                        if (proc.MainWindowHandle != IntPtr.Zero)
                        {
                            _hwpHwnd = proc.MainWindowHandle;
                            break;
                        }
                    }
                    return true;
                }
                else
                {
                    // Fallback process launch
                    Process.Start(_openedPath);
                    return true;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("[BoardestHwpControl] Open error: " + ex.Message);
                try
                {
                    Process.Start(filePath);
                    return true;
                }
                catch {}
            }
            return false;
        }

        /// <summary>
        /// Get total page count of opened HWP document
        /// </summary>
        public int GetPageCount()
        {
            if (_hwpApp == null) return 1;
            try { return (int)_hwpApp.PageCount; } catch { return 1; }
        }

        /// <summary>
        /// Get current active page index (1-based)
        /// </summary>
        public int GetCurrentPage()
        {
            if (_hwpApp == null) return 1;
            try { return (int)_hwpApp.KeyIndicator.Page; } catch { return 1; }
        }

        /// <summary>
        /// Trigger ViewZoomWidthFit command in Hancom Office
        /// </summary>
        public void ZoomWidthFit()
        {
            if (_hwpApp == null) return;
            try { _hwpApp.Run("ViewZoomWidthFit"); } catch {}
        }

        /// <summary>
        /// Close active HWP application instance
        /// </summary>
        public void Close()
        {
            if (_hwpApp != null)
            {
                try { _hwpApp.Quit(); } catch {}
                _hwpApp = null;
            }
        }
    }
}
