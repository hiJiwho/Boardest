using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Win32;

namespace Boardest.Uninstaller {
    public static class Program {
        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool SetDllDirectory(string lpPathName);

        [STAThread]
        public static void Main(string[] args) {
            string tempDir = Path.Combine(Path.GetTempPath(), "BoardestInstallerLib");
            try {
                Directory.CreateDirectory(tempDir);
                ExtractResourceToFile("WebView2Loader.dll", Path.Combine(tempDir, "WebView2Loader.dll"));
                ExtractResourceToFile("Microsoft.Web.WebView2.Core.dll", Path.Combine(tempDir, "Microsoft.Web.WebView2.Core.dll"));
                ExtractResourceToFile("Microsoft.Web.WebView2.WinForms.dll", Path.Combine(tempDir, "Microsoft.Web.WebView2.WinForms.dll"));
                SetDllDirectory(tempDir);
            } catch (Exception ex) {
                Debug.WriteLine("Native loader extract warning: " + ex.Message);
            }

            AppDomain.CurrentDomain.AssemblyResolve += (sender, resolveArgs) => {
                try {
                    if (resolveArgs.Name.StartsWith("Microsoft.Web.WebView2.Core")) {
                        string p = Path.Combine(tempDir, "Microsoft.Web.WebView2.Core.dll");
                        if (File.Exists(p)) return Assembly.LoadFrom(p);
                    } else if (resolveArgs.Name.StartsWith("Microsoft.Web.WebView2.WinForms")) {
                        string p = Path.Combine(tempDir, "Microsoft.Web.WebView2.WinForms.dll");
                        if (File.Exists(p)) return Assembly.LoadFrom(p);
                    }
                } catch { }
                return null;
            };

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new UninstallerForm());
        }

        private static void ExtractResourceToFile(string resName, string destPath) {
            if (File.Exists(destPath)) {
                try { File.Delete(destPath); } catch { return; }
            }
            using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream(resName)) {
                if (s != null) {
                    using (var fs = new FileStream(destPath, FileMode.Create, FileAccess.Write)) {
                        s.CopyTo(fs);
                    }
                }
            }
        }
    }

    public class UninstallerForm : Form {
        [DllImport("user32.dll")]
        public static extern bool ReleaseCapture();
        [DllImport("user32.dll")]
        public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);
        [DllImport("shell32.dll")]
        private static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);

        private WebView2 _webView;
        private string _installDir;

        public UninstallerForm() {
            InitializeComponent();
        }

        private void InitializeComponent() {
            this.Text = "Boardest Teacher 제거 마법사";
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.Size = new Size(680, 520);
            this.BackColor = Color.FromArgb(11, 12, 16);
            this.ShowIcon = false;

            _webView = new WebView2 { Dock = DockStyle.Fill };
            this.Controls.Add(_webView);

            _installDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Programs", "BoardestTeacher"
            );

            InitWebView();
        }

        private async void InitWebView() {
            try {
                var userDataFolder = Path.Combine(Path.GetTempPath(), "BoardestInstaller_wv2");
                var env = await CoreWebView2Environment.CreateAsync(null, userDataFolder);
                await _webView.EnsureCoreWebView2Async(env);

                _webView.CoreWebView2.Settings.IsStatusBarEnabled = false;
                _webView.CoreWebView2.Settings.AreDevToolsEnabled = false;
                _webView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;

                _webView.CoreWebView2.WebMessageReceived += OnWebMessageReceived;

                string html = LoadHtml();
                _webView.CoreWebView2.NavigateToString(html);
            } catch (Exception ex) {
                MessageBox.Show("제거 도구 초기화 실패: " + ex.Message, "오류", MessageBoxButtons.OK, MessageBoxIcon.Error);
                Application.Exit();
            }
        }

        private string LoadHtml() {
            using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("installer.html")) {
                if (stream != null) {
                    using (var reader = new StreamReader(stream, Encoding.UTF8)) {
                        return reader.ReadToEnd();
                    }
                }
            }
            return "<html><body><h3>Boardest Uninstaller</h3></body></html>";
        }

        private void OnWebMessageReceived(object sender, CoreWebView2WebMessageReceivedEventArgs e) {
            try {
                string json = e.TryGetWebMessageAsString();
                if (string.IsNullOrEmpty(json)) return;

                if (json.Contains("\"action\":\"close\"")) {
                    this.Close();
                } else if (json.Contains("\"action\":\"minimize\"")) {
                    this.WindowState = FormWindowState.Minimized;
                } else if (json.Contains("\"action\":\"drag\"")) {
                    ReleaseCapture();
                    SendMessage(this.Handle, 0xA1, 2, 0);
                } else if (json.Contains("\"action\":\"uiReady\"")) {
                    SendInitDataToUI();
                } else if (json.Contains("\"action\":\"startUninstall\"")) {
                    bool purgeData = json.Contains("\"purgeData\":true");
                    Task.Run(() => PerformUninstall(purgeData));
                }
            } catch (Exception ex) {
                Debug.WriteLine("OnWebMessageReceived error: " + ex);
            }
        }

        private void SendInitDataToUI() {
            string logoB64 = "";
            using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("app_logo.png")) {
                if (s != null) {
                    byte[] b = new byte[s.Length];
                    s.Read(b, 0, b.Length);
                    logoB64 = Convert.ToBase64String(b);
                }
            }

            string json = string.Format(
                "{{\"productName\":\"Boardest Teacher\",\"productType\":\"Teacher\",\"productVersion\":\"5.5.3.1\",\"productDesc\":\"선생님 교무실 PC 전용 수업 관리자 프로그램 제거\",\"heroIcon\":\"🎓\",\"installDir\":\"{0}\",\"hideDirField\":true,\"isUninstall\":true,\"logoBase64\":\"{1}\"}}",
                EscapeJson(_installDir),
                logoB64
            );
            RunScript(string.Format("if(window.receiveInitData) window.receiveInitData({0});", json));
        }

        private void PerformUninstall(bool purgeData) {
            try {
                NotifyProgress(15, "실행 중인 프로그램을 종료하는 중...", "프로세스 정리 중...");
                KillProcesses();

                NotifyProgress(40, "바로가기를 제거하는 중...", "바탕화면 및 시작 메뉴 바로가기 삭제 중...");
                RemoveShortcuts();

                NotifyProgress(65, "시스템 등록 정보를 제거하는 중...", "Windows 프로그램 추가/제거 레지스트리 정리 중...");
                RemoveRegistryEntries();

                if (purgeData) {
                    NotifyProgress(80, "사용자 캐시 및 설정을 제거하는 중...", "개인 설정 및 로컬 데이터 정리 중...");
                    try {
                        string userDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Boardest");
                        if (Directory.Exists(userDir)) Directory.Delete(userDir, true);
                    } catch { }
                }

                NotifyProgress(95, "프로그램 파일 제거를 예약하는 중...", "설치 디렉토리 파일 소거 중...");
                ScheduleSelfDeletion();

                NotifyProgress(100, "삭제가 완료되었습니다.", "Boardest Teacher 제거 완료!");
            } catch (Exception ex) {
                NotifyProgress(100, "제거 중 일부 항목 오류: " + ex.Message, "제거 완료");
            }
        }

        private void KillProcesses() {
            string[] names = { "boardest_teacher", "bst-teacher", "BoardestTeacher", "watchdog" };
            foreach (var name in names) {
                try {
                    foreach (var p in Process.GetProcessesByName(name)) {
                        p.Kill();
                        p.WaitForExit(2000);
                    }
                } catch { }
            }
        }

        private void RemoveShortcuts() {
            try {
                string[] shortcutNames = new string[] {
                    "Boardest Teacher.lnk",
                    "Boardest Teacher 제거.lnk"
                };
                string[] shortcutPatterns = new string[] {
                    "Boardest Teacher*.lnk",
                    "Boardest Teacher 제거*.lnk"
                };

                // 1. 바탕화면 바로가기 삭제 (User 및 Common)
                string[] desktopDirs = new string[] {
                    Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                    Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory)
                };
                foreach (string dir in desktopDirs) {
                    if (string.IsNullOrEmpty(dir) || !Directory.Exists(dir)) continue;
                    foreach (string name in shortcutNames) {
                        try {
                            string p = Path.Combine(dir, name);
                            if (File.Exists(p)) File.Delete(p);
                        } catch { }
                    }
                    foreach (string pattern in shortcutPatterns) {
                        try {
                            foreach (string lnk in Directory.GetFiles(dir, pattern)) {
                                try { File.Delete(lnk); } catch { }
                            }
                        } catch { }
                    }
                }

                // 2. 시작 메뉴 루트 및 시작프로그램 바로가기 삭제 (Programs 및 CommonPrograms)
                string[] startRoots = new string[] {
                    Environment.GetFolderPath(Environment.SpecialFolder.Programs),
                    Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms),
                    Environment.GetFolderPath(Environment.SpecialFolder.Startup),
                    Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup)
                };
                foreach (string root in startRoots) {
                    if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) continue;
                    foreach (string name in shortcutNames) {
                        try {
                            string p = Path.Combine(root, name);
                            if (File.Exists(p)) File.Delete(p);
                        } catch { }
                    }
                    foreach (string pattern in shortcutPatterns) {
                        try {
                            foreach (string lnk in Directory.GetFiles(root, pattern)) {
                                try { File.Delete(lnk); } catch { }
                            }
                        } catch { }
                    }
                }

                // 3. 시작 메뉴 프로그램 하위 폴더 삭제 (User 및 Common)
                string[] startDirs = new string[] {
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Boardest"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms), "Boardest"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Boardest Teacher"),
                    Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms), "Boardest Teacher")
                };
                foreach (string sDir in startDirs) {
                    try {
                        if (!string.IsNullOrEmpty(sDir) && Directory.Exists(sDir)) {
                            Directory.Delete(sDir, true);
                        }
                    } catch { }
                }

                // 4. 작업표시줄 고정 바로가기 정리 (선택적)
                try {
                    string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                    string taskbarPinned = Path.Combine(appData, @"Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar");
                    if (Directory.Exists(taskbarPinned)) {
                        foreach (string pattern in shortcutPatterns) {
                            foreach (string lnk in Directory.GetFiles(taskbarPinned, pattern)) {
                                try { File.Delete(lnk); } catch { }
                            }
                        }
                    }
                } catch { }

                // 5. Windows 쉘 캐시 즉시 갱신 (SHCNE_ASSOCCHANGED = 0x08000000, SHCNF_IDLIST = 0x0000)
                try {
                    SHChangeNotify(0x08000000, 0x0000, IntPtr.Zero, IntPtr.Zero);
                } catch { }
            } catch { }
        }

        private void RemoveRegistryEntries() {
            try {
                using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall", true)) {
                    if (key != null) {
                        key.DeleteSubKeyTree("BoardestTeacher", false);
                    }
                }
            } catch { }
        }

        private void ScheduleSelfDeletion() {
            try {
                // Run background batch script to delete install directory after this process exits
                string batPath = Path.Combine(Path.GetTempPath(), "boardest_uninst_cleanup.bat");
                string batContent = string.Format(
                    "@echo off\r\n" +
                    "timeout /t 2 /nobreak >nul\r\n" +
                    "rmdir /s /q \"{0}\"\r\n" +
                    "del \"%~f0\"\r\n",
                    _installDir
                );
                File.WriteAllText(batPath, batContent);
                var psi = new ProcessStartInfo {
                    FileName = "cmd.exe",
                    Arguments = "/c \"" + batPath + "\"",
                    CreateNoWindow = true,
                    UseShellExecute = false,
                    WindowStyle = ProcessWindowStyle.Hidden
                };
                Process.Start(psi);
            } catch { }
        }

        private void NotifyProgress(int pct, string status, string log) {
            string script = string.Format(
                "if(window.updateUninstallProgress) window.updateUninstallProgress({0}, '{1}', '{2}');",
                pct, EscapeJs(status), EscapeJs(log)
            );
            RunScript(script);
        }

        private void RunScript(string script) {
            if (_webView != null && _webView.CoreWebView2 != null) {
                this.BeginInvoke(new Action(() => {
                    try { _webView.CoreWebView2.ExecuteScriptAsync(script); } catch { }
                }));
            }
        }

        private string EscapeJson(string s) {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "").Replace("\n", "");
        }

        private string EscapeJs(string s) {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("\\", "\\\\").Replace("'", "\\'").Replace("\r", "").Replace("\n", " ");
        }
    }
}
