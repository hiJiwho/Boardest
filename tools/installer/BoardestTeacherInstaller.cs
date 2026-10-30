using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Win32;

namespace Boardest.TeacherInstaller {
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
            Application.Run(new TeacherInstallerForm(args));
        }

        public static void ExtractResourceToFile(string resName, string destPath) {
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

    public class TeacherInstallerForm : Form {
        [DllImport("user32.dll")]
        public static extern bool ReleaseCapture();
        [DllImport("user32.dll")]
        public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);

        private readonly string[] _args;
        private readonly bool _isUpdate;
        private WebView2 _webView;
        private bool _isInstalling = false;
        private string _targetInstallDir;
        private string _mainExePath;

        public TeacherInstallerForm(string[] args) {
            _args = args;
            _isUpdate = args != null && Array.Exists(args, a => a.Equals("--update", StringComparison.OrdinalIgnoreCase));
            InitializeComponent();
        }

        private void InitializeComponent() {
            this.Text = "Boardest Teacher 온라인 설치 마법사";
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.Size = new Size(680, 520);
            this.BackColor = Color.FromArgb(11, 12, 16);
            this.ShowIcon = false;

            _webView = new WebView2 { Dock = DockStyle.Fill };
            this.Controls.Add(_webView);

            _targetInstallDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Programs", "BoardestTeacher"
            );
            _mainExePath = Path.Combine(_targetInstallDir, "boardest_teacher.exe");

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
                MessageBox.Show("설치 마법사 초기화 실패: " + ex.Message, "오류", MessageBoxButtons.OK, MessageBoxIcon.Error);
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
            return "<html><body><h3>Boardest Teacher Installer</h3></body></html>";
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
                    if (_isUpdate) {
                        _isInstalling = true;
                        Task.Run(() => PerformInstallation(true, true));
                    }
                } else if (json.Contains("\"action\":\"startInstall\"")) {
                    if (!_isInstalling) {
                        _isInstalling = true;
                        bool createDesktop = json.Contains("\"createDesktop\":true");
                        bool createStartMenu = json.Contains("\"createStartMenu\":true");
                        Task.Run(() => PerformInstallation(createDesktop, createStartMenu));
                    }
                } else if (json.Contains("\"action\":\"launchApp\"")) {
                    LaunchApp();
                    this.Close();
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
                "{{\"productName\":\"Boardest Teacher\",\"productType\":\"Teacher\",\"productVersion\":\"5.3.7\",\"productDesc\":\"교사용 스마트 전자칠판 & 수업 관리 솔루션 온라인 설치\",\"heroIcon\":\"🎓\",\"installDir\":\"{0}\",\"hideDirField\":false,\"isUninstall\":false,\"logoBase64\":\"{1}\"}}",
                EscapeJson(_targetInstallDir),
                logoB64
            );
            RunScript(string.Format("if(window.receiveInitData) window.receiveInitData({0});", json));
        }

        private void PerformInstallation(bool createDesktop, bool createStartMenu) {
            try {
                NotifyProgress(10, "실행 중인 기존 앱 종료 중...", "0.0 MB", "", "기존 프로세스 확인 중...");
                KillRunningProcesses();

                string zipPath = AcquireZipPackage();

                NotifyProgress(70, "패키지 압축 해제 및 프로그램 설치 중...", "", "", "목적지: " + _targetInstallDir);
                ExtractZipPackage(zipPath);

                NotifyProgress(85, "삭제 도구(Uninstaller) 등록 중...", "", "", "uninstall.exe 배포 중...");
                DeployUninstaller();

                NotifyProgress(90, "바로가기 생성 중...", "", "", "바탕화면 및 시작 메뉴 바로가기 등록");
                CreateShortcuts(createDesktop, createStartMenu);

                NotifyProgress(95, "시스템 앱 레지스트리 등록 중...", "", "", "Windows 프로그램 추가/제거에 Boardest Teacher 등록");
                RegisterInWindowsUninstall();

                NotifyProgress(100, "설치 완료!", "", "", "Boardest Teacher 설치가 성공적으로 완료되었습니다!");
            } catch (Exception ex) {
                NotifyProgress(100, "설치 오류: " + ex.Message, "", "", "오류 발생: " + ex.ToString());
            }
        }

        private void KillRunningProcesses() {
            string[] names = { "boardest_teacher", "bst-teacher", "BoardestTeacher", "watchdog" };
            foreach (var name in names) {
                try {
                    foreach (var p in Process.GetProcessesByName(name)) {
                        p.Kill();
                        p.WaitForExit(3000);
                    }
                } catch { }
            }
        }

        private string AcquireZipPackage() {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string localZip = Path.Combine(baseDir, "bst-teacher-windows.zip");
            if (!File.Exists(localZip)) localZip = Path.Combine(baseDir, "boardest-teacher-windows.zip");

            if (File.Exists(localZip)) {
                NotifyProgress(50, "로컬 패키지 확인 완료", "100%", "", "로컬 패키지 사용: " + Path.GetFileName(localZip));
                return localZip;
            }

            string downloadDest = Path.Combine(Path.GetTempPath(), "bst_teacher_" + Guid.NewGuid().ToString("N").Substring(0, 8) + ".zip");
            string downloadUrl = "https://github.com/hiJiwho/Boardest/releases/latest/download/bst-teacher-windows.zip";

            DownloadFileWithProgress(downloadUrl, downloadDest);
            return downloadDest;
        }

        private void DownloadFileWithProgress(string url, string destPath) {
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | (SecurityProtocolType)3072;
            var request = (HttpWebRequest)WebRequest.Create(url);
            request.UserAgent = "BoardestInstaller/5.3.7";
            request.Timeout = 40000;

            using (var response = request.GetResponse()) {
                long totalBytes = response.ContentLength;
                using (var input = response.GetResponseStream())
                using (var output = new FileStream(destPath, FileMode.Create, FileAccess.Write, FileShare.None)) {
                    byte[] buffer = new byte[65536];
                    long receivedBytes = 0;
                    int bytesRead;
                    var sw = Stopwatch.StartNew();
                    long lastBytes = 0;
                    double lastTime = 0;
                    double currentSpeed = 0;

                    while ((bytesRead = input.Read(buffer, 0, buffer.Length)) > 0) {
                        output.Write(buffer, 0, bytesRead);
                        receivedBytes += bytesRead;

                        double elapsedSec = sw.Elapsed.TotalSeconds;
                        if (elapsedSec - lastTime >= 0.3) {
                            double deltaBytes = receivedBytes - lastBytes;
                            double deltaTime = elapsedSec - lastTime;
                            currentSpeed = (deltaBytes / deltaTime) / (1024 * 1024);
                            lastBytes = receivedBytes;
                            lastTime = elapsedSec;

                            int pct = 15 + (int)((receivedBytes / (double)Math.Max(totalBytes, 1)) * 50);
                            string bytesStr = string.Format("{0:F1} MB / {1:F1} MB", receivedBytes / (1024.0 * 1024.0), totalBytes / (1024.0 * 1024.0));
                            string speedStr = string.Format("{0:F2} MB/s", currentSpeed);

                            NotifyProgress(pct, "최신 교사용 패키지 다운로드 중...", bytesStr, speedStr, null);
                        }
                    }
                }
            }
        }

        private void ExtractZipPackage(string zipPath) {
            if (!Directory.Exists(_targetInstallDir)) {
                Directory.CreateDirectory(_targetInstallDir);
            }

            using (var archive = ZipFile.OpenRead(zipPath)) {
                int totalEntries = archive.Entries.Count;
                int current = 0;
                foreach (var entry in archive.Entries) {
                    current++;
                    if (string.IsNullOrEmpty(entry.Name)) continue; // Directory entry

                    string fullPath = Path.Combine(_targetInstallDir, entry.FullName);
                    string dir = Path.GetDirectoryName(fullPath);
                    if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);

                    try {
                        entry.ExtractToFile(fullPath, true);
                    } catch {
                        try {
                            string alt = fullPath + ".new";
                            entry.ExtractToFile(alt, true);
                        } catch { }
                    }

                    if (current % 15 == 0 || current == totalEntries) {
                        int pct = 70 + (int)((current / (double)totalEntries) * 15);
                        NotifyProgress(pct, "파일 압축 해제 중...", "", "", "압축 해제: " + entry.Name);
                    }
                }
            }
        }

        private void DeployUninstaller() {
            try {
                string uninstPath = Path.Combine(_targetInstallDir, "uninstall.exe");
                Program.ExtractResourceToFile("uninstall.exe", uninstPath);
            } catch (Exception ex) {
                Debug.WriteLine("DeployUninstaller error: " + ex);
            }
        }

        private void CreateShortcuts(bool createDesktop, bool createStartMenu) {
            try {
                Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                if (shellType == null) return;
                dynamic shell = Activator.CreateInstance(shellType);

                string shortcutName = "Boardest Teacher.lnk";

                if (createDesktop) {
                    string desktopPath = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                    string lnkPath = Path.Combine(desktopPath, shortcutName);
                    dynamic shortcut = shell.CreateShortcut(lnkPath);
                    shortcut.TargetPath = _mainExePath;
                    shortcut.WorkingDirectory = _targetInstallDir;
                    shortcut.Description = "Boardest Teacher - 교사용 스마트 전자칠판 & 수업 관리 솔루션";
                    shortcut.Save();
                }

                if (createStartMenu) {
                    string programsPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Boardest");
                    if (!Directory.Exists(programsPath)) Directory.CreateDirectory(programsPath);
                    string lnkPath = Path.Combine(programsPath, shortcutName);
                    dynamic shortcut = shell.CreateShortcut(lnkPath);
                    shortcut.TargetPath = _mainExePath;
                    shortcut.WorkingDirectory = _targetInstallDir;
                    shortcut.Description = "Boardest Teacher";
                    shortcut.Save();
                }
            } catch { }
        }

        private void RegisterInWindowsUninstall() {
            try {
                using (var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\BoardestTeacher")) {
                    if (key != null) {
                        key.SetValue("DisplayName", "Boardest Teacher");
                        key.SetValue("DisplayVersion", "5.3.7");
                        key.SetValue("Publisher", "Boardest");
                        key.SetValue("InstallLocation", _targetInstallDir);
                        key.SetValue("DisplayIcon", _mainExePath);
                        key.SetValue("UninstallString", "\"" + Path.Combine(_targetInstallDir, "uninstall.exe") + "\"");
                        key.SetValue("EstimatedSize", 68000, RegistryValueKind.DWord);
                        key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                        key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                    }
                }
            } catch { }
        }

        private void LaunchApp() {
            try {
                if (File.Exists(_mainExePath)) {
                    var psi = new ProcessStartInfo {
                        FileName = _mainExePath,
                        WorkingDirectory = _targetInstallDir
                    };
                    Process.Start(psi);
                }
            } catch { }
        }

        private void NotifyProgress(int pct, string status, string bytes, string speed, string log) {
            string script = string.Format(
                "if(window.updateProgress) window.updateProgress({0}, '{1}', '{2}', '{3}', '{4}');",
                pct, EscapeJs(status), EscapeJs(bytes), EscapeJs(speed), EscapeJs(log)
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
