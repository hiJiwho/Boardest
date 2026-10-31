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
        private string _latestVersion = "5.3.7";
        private string _discoveredAssetUrl = null;

        public TeacherInstallerForm(string[] args) {
            _args = args;
            _isUpdate = args != null && Array.Exists(args, a => a.Equals("--update", StringComparison.OrdinalIgnoreCase));
            InitializeComponent();
        }

        private void InitializeComponent() {
            this.Text = "Boardest Teacher 온라인 설치 마법사";
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.Size = new Size(680, 560);
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

                // Asynchronously fetch latest version info in background
                Task.Run(() => FetchLatestVersionInfo());
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
                        Task.Run(() => PerformInstallation(true, true, "full"));
                    }
                } else if (json.Contains("\"action\":\"startInstall\"")) {
                    if (!_isInstalling) {
                        _isInstalling = true;
                        bool createDesktop = json.Contains("\"createDesktop\":true");
                        bool createStartMenu = json.Contains("\"createStartMenu\":true");
                        string installScope = "full";
                        if (json.Contains("\"installScope\":\"standalone\"")) {
                            installScope = "standalone";
                        }
                        Task.Run(() => PerformInstallation(createDesktop, createStartMenu, installScope));
                    }
                } else if (json.Contains("\"action\":\"launchApp\"")) {
                    LaunchApp();
                    this.Close();
                }
            } catch (Exception ex) {
                Debug.WriteLine("OnWebMessageReceived error: " + ex);
            }
        }

        private void FetchLatestVersionInfo() {
            try {
                ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | (SecurityProtocolType)12288 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;
                ServicePointManager.ServerCertificateValidationCallback = (sender, cert, chain, sslPolicyErrors) => true;

                var req = (HttpWebRequest)WebRequest.Create("https://api.github.com/repos/hiJiwho/Boardest/releases/latest");
                req.UserAgent = "BoardestTeacherInstaller/5.3.7";
                req.Accept = "application/vnd.github.v3+json";
                req.Timeout = 7000;

                using (var resp = req.GetResponse())
                using (var reader = new StreamReader(resp.GetResponseStream(), Encoding.UTF8)) {
                    string responseText = reader.ReadToEnd();

                    // Find tag_name
                    int tagIdx = responseText.IndexOf("\"tag_name\":");
                    if (tagIdx >= 0) {
                        int start = responseText.IndexOf("\"", tagIdx + 11) + 1;
                        int end = responseText.IndexOf("\"", start);
                        if (start > 0 && end > start) {
                            string tag = responseText.Substring(start, end - start).Trim().TrimStart('v');
                            if (!string.IsNullOrEmpty(tag)) {
                                _latestVersion = tag;
                            }
                        }
                    }

                    // Find bst-teacher-windows.zip asset download URL
                    int zipIdx = responseText.IndexOf("bst-teacher-windows.zip");
                    if (zipIdx >= 0) {
                        int urlIdx = responseText.LastIndexOf("\"browser_download_url\":", zipIdx);
                        if (urlIdx >= 0) {
                            int start = responseText.IndexOf("\"", urlIdx + 23) + 1;
                            int end = responseText.IndexOf("\"", start);
                            if (start > 0 && end > start) {
                                _discoveredAssetUrl = responseText.Substring(start, end - start);
                            }
                        }
                    }
                }

                // Update UI with discovered version
                RunScript(string.Format("document.getElementById('productVersion').innerText = 'v{0}';", EscapeJs(_latestVersion)));
            } catch (Exception ex) {
                Debug.WriteLine("FetchLatestVersionInfo warning: " + ex.Message);
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
                "{{\"productName\":\"Boardest Teacher\",\"productType\":\"Teacher\",\"productVersion\":\"{0}\",\"productDesc\":\"교사용 스마트 전자칠판 & 수업 관리 솔루션 온라인 설치\",\"heroIcon\":\"🎓\",\"installDir\":\"{1}\",\"hideDirField\":false,\"isUninstall\":false,\"logoBase64\":\"{2}\"}}",
                EscapeJson(_latestVersion),
                EscapeJson(_targetInstallDir),
                logoB64
            );
            RunScript(string.Format("if(window.receiveInitData) window.receiveInitData({0});", json));
        }

        private void PerformInstallation(bool createDesktop, bool createStartMenu, string installScope) {
            try {
                string modeText = installScope == "standalone" ? "교사용 메인 앱 단독 설치 (경량 모드)" : "Boardest Teacher PRO 전체 설치";
                NotifyProgress(5, "설치 준비 중...", "", "", "[설치 모드] " + modeText);

                NotifyProgress(10, "실행 중인 기존 앱 확인 및 종료 중...", "", "", "기존 실행 프로세스 확인 중...");
                KillRunningProcesses();

                string zipPath = AcquireZipPackage();

                NotifyProgress(65, "패키지 무결성 검증 및 설치 준비...", "", "", "패키지 확인 완료: " + Path.GetFileName(zipPath));
                NotifyProgress(70, "패키지 압축 해제 및 프로그램 파일 설치 중...", "", "", "설치 경로: " + _targetInstallDir);
                ExtractZipPackage(zipPath, installScope);

                NotifyProgress(85, "삭제 도구(Uninstaller) 등록 중...", "", "", "안전한 프로그램 제거 관리자(uninstall.exe) 등록");
                DeployUninstaller();

                NotifyProgress(90, "바로가기 생성 중...", "", "", "바탕화면 및 시작 메뉴 바로가기 구성");
                CreateShortcuts(createDesktop, createStartMenu, installScope);

                NotifyProgress(95, "시스템 앱 레지스트리 등록 중...", "", "", "Windows 프로그램 추가/제거에 등록");
                RegisterInWindowsUninstall(installScope);

                NotifyProgress(100, "설치 완료!", "", "", "Boardest Teacher 설치가 성공적으로 완료되었습니다!");
            } catch (Exception ex) {
                NotifyProgress(100, "설치 오류: " + ex.Message, "", "", "오류 세부 내용:\n" + ex.ToString());
            }
        }

        private void KillRunningProcesses() {
            string[] names = { "boardest_teacher", "bst-teacher", "BoardestTeacher", "watchdog", "boardest_hwp_overlay", "boardest_ppt_overlay", "boardest_ppt_helper" };
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

            // 1. Check local directory candidates
            string[] localNames = { "bst-teacher-windows.zip", "boardest-teacher-windows.zip", "boardest-windows.zip" };
            foreach (var name in localNames) {
                string localFile = Path.Combine(baseDir, name);
                if (File.Exists(localFile) && new FileInfo(localFile).Length > 1000000) {
                    NotifyProgress(50, "로컬 패키지 사용", "100%", "", "로컬 패키지 감지: " + Path.GetFileName(localFile));
                    return localFile;
                }
            }

            // 2. Prepare candidate mirror URLs in order of preference
            var urls = new System.Collections.Generic.List<string>();
            if (!string.IsNullOrEmpty(_discoveredAssetUrl)) {
                urls.Add(_discoveredAssetUrl);
            }
            urls.Add("https://github.com/hiJiwho/Boardest/releases/download/v" + _latestVersion + "/bst-teacher-windows.zip");
            urls.Add("https://github.com/hiJiwho/Boardest/releases/latest/download/bst-teacher-windows.zip");
            urls.Add("https://boardest-web.web.app/downloads/bst-teacher-windows.zip");
            urls.Add("https://boardest-downloads.web.app/bst-teacher-windows.zip");
            urls.Add("https://github.com/hiJiwho/Boardest/releases/download/v" + _latestVersion + "/boardest-windows.zip");
            urls.Add("https://github.com/hiJiwho/Boardest/releases/latest/download/boardest-windows.zip");

            string downloadDest = Path.Combine(Path.GetTempPath(), "bst_teacher_" + Guid.NewGuid().ToString("N").Substring(0, 8) + ".zip");

            Exception lastEx = null;
            foreach (var url in urls) {
                try {
                    NotifyProgress(15, "최신 설치 패키지 다운로드 준비 중...", "", "", "[다운로드 시도] " + url);
                    if (DownloadFileWithProgress(url, downloadDest)) {
                        if (File.Exists(downloadDest) && new FileInfo(downloadDest).Length > 1000000) {
                            NotifyProgress(60, "다운로드 완료!", "", "", "[다운로드 성공] " + new FileInfo(downloadDest).Length / (1024 * 1024) + " MB");
                            return downloadDest;
                        }
                    }
                } catch (Exception ex) {
                    lastEx = ex;
                    NotifyProgress(15, "다운로드 재시도 중...", "", "", "[미러 전환] 오류: " + ex.Message);
                    try { if (File.Exists(downloadDest)) File.Delete(downloadDest); } catch { }
                }
            }

            throw new InvalidOperationException("모든 다운로드 서버(GitHub, CDN 미러) 접속에 실패했습니다.\n네트워크 연결을 확인하거나 같은 폴더에 bst-teacher-windows.zip 파일을 넣어주세요.\n(마지막 오류: " + (lastEx != null ? lastEx.Message : "알 수 없음") + ")");
        }

        private bool DownloadFileWithProgress(string url, string destPath) {
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | (SecurityProtocolType)12288 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;
            ServicePointManager.ServerCertificateValidationCallback = (sender, cert, chain, sslPolicyErrors) => true;
            ServicePointManager.Expect100Continue = false;
            ServicePointManager.DefaultConnectionLimit = 10;

            string targetUrl = url;
            int maxRedirects = 8;

            while (maxRedirects-- > 0) {
                var request = (HttpWebRequest)WebRequest.Create(targetUrl);
                request.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) BoardestTeacherInstaller/5.3.7";
                request.Timeout = 60000;
                request.ReadWriteTimeout = 60000;
                request.AllowAutoRedirect = false; // Manually handle redirects for AWS S3 and GitHub reliability
                request.KeepAlive = true;

                HttpWebResponse response;
                try {
                    response = (HttpWebResponse)request.GetResponse();
                } catch (WebException wex) {
                    var errResp = wex.Response as HttpWebResponse;
                    if (errResp != null) {
                        response = errResp;
                    } else {
                        throw;
                    }
                }

                // Check for redirect (301, 302, 303, 307, 308)
                int statusCode = (int)response.StatusCode;
                if (statusCode >= 300 && statusCode < 400) {
                    string location = response.Headers["Location"];
                    response.Close();
                    if (!string.IsNullOrEmpty(location)) {
                        if (!location.StartsWith("http://", StringComparison.OrdinalIgnoreCase) &&
                            !location.StartsWith("https://", StringComparison.OrdinalIgnoreCase)) {
                            var baseUri = new Uri(targetUrl);
                            targetUrl = new Uri(baseUri, location).ToString();
                        } else {
                            targetUrl = location;
                        }
                        continue;
                    }
                }

                if (statusCode != 200) {
                    response.Close();
                    throw new WebException(string.Format("HTTP 서버 응답 오류 ({0})", statusCode));
                }

                using (response) {
                    long totalBytes = response.ContentLength;
                    using (var input = response.GetResponseStream())
                    using (var output = new FileStream(destPath, FileMode.Create, FileAccess.Write, FileShare.None)) {
                        byte[] buffer = new byte[65536];
                        long receivedBytes = 0;
                        int bytesRead;
                        var sw = Stopwatch.StartNew();
                        long lastBytes = 0;
                        double lastTime = 0;

                        while ((bytesRead = input.Read(buffer, 0, buffer.Length)) > 0) {
                            output.Write(buffer, 0, bytesRead);
                            receivedBytes += bytesRead;

                            double elapsedSec = sw.Elapsed.TotalSeconds;
                            if (elapsedSec - lastTime >= 0.25 || receivedBytes == totalBytes) {
                                double deltaBytes = receivedBytes - lastBytes;
                                double deltaTime = Math.Max(elapsedSec - lastTime, 0.001);
                                double currentSpeed = (deltaBytes / deltaTime) / (1024 * 1024);
                                lastBytes = receivedBytes;
                                lastTime = elapsedSec;

                                int pct;
                                string bytesStr;
                                if (totalBytes > 0) {
                                    pct = 15 + (int)((receivedBytes / (double)totalBytes) * 45);
                                    bytesStr = string.Format("{0:F1} MB / {1:F1} MB", receivedBytes / (1024.0 * 1024.0), totalBytes / (1024.0 * 1024.0));
                                } else {
                                    pct = Math.Min(58, 15 + (int)(receivedBytes / (1024.0 * 1024.0) * 2));
                                    bytesStr = string.Format("{0:F1} MB 다운로드 중", receivedBytes / (1024.0 * 1024.0));
                                }

                                string speedStr = string.Format("{0:F2} MB/s", currentSpeed);
                                NotifyProgress(pct, "최신 교사용 패키지 다운로드 중...", bytesStr, speedStr, null);
                            }
                        }
                    }
                }
                return true;
            }

            return false;
        }

        private void ExtractZipPackage(string zipPath, string installScope) {
            if (!Directory.Exists(_targetInstallDir)) {
                Directory.CreateDirectory(_targetInstallDir);
            }

            bool isStandalone = installScope == "standalone";

            using (var archive = ZipFile.OpenRead(zipPath)) {
                int totalEntries = archive.Entries.Count;
                int current = 0;
                foreach (var entry in archive.Entries) {
                    current++;
                    if (string.IsNullOrEmpty(entry.Name)) continue; // Directory entry

                    // In standalone mode, skip unnecessary background overlay services
                    if (isStandalone) {
                        string nameLower = entry.Name.ToLowerInvariant();
                        if (nameLower.Contains("watchdog") ||
                            nameLower.Contains("boardest_hwp_overlay") ||
                            nameLower.Contains("boardest_ppt_overlay") ||
                            nameLower.Contains("boardest_ppt_helper")) {
                            continue;
                        }
                    }

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
                        NotifyProgress(pct, "프로그램 파일 설치 중...", "", "", "설치: " + entry.Name);
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

        private void CreateShortcuts(bool createDesktop, bool createStartMenu, string installScope) {
            try {
                Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                if (shellType == null) return;
                dynamic shell = Activator.CreateInstance(shellType);

                string shortcutName = installScope == "standalone" ? "Boardest Teacher (단독).lnk" : "Boardest Teacher.lnk";

                if (createDesktop) {
                    string desktopPath = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                    string lnkPath = Path.Combine(desktopPath, shortcutName);
                    dynamic shortcut = shell.CreateShortcut(lnkPath);
                    shortcut.TargetPath = _mainExePath;
                    shortcut.WorkingDirectory = _targetInstallDir;
                    shortcut.Description = installScope == "standalone" ? "Boardest Teacher - 교사용 단독 실행 프로그램" : "Boardest Teacher - 교사용 스마트 전자칠판 & 수업 관리 솔루션";
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

        private void RegisterInWindowsUninstall(string installScope) {
            try {
                using (var key = Registry.CurrentUser.CreateSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\BoardestTeacher")) {
                    if (key != null) {
                        string displayName = installScope == "standalone" ? "Boardest Teacher (단독 실행형)" : "Boardest Teacher PRO";
                        key.SetValue("DisplayName", displayName);
                        key.SetValue("DisplayVersion", _latestVersion);
                        key.SetValue("Publisher", "Boardest");
                        key.SetValue("InstallLocation", _targetInstallDir);
                        key.SetValue("DisplayIcon", _mainExePath);
                        key.SetValue("UninstallString", "\"" + Path.Combine(_targetInstallDir, "uninstall.exe") + "\"");
                        key.SetValue("EstimatedSize", installScope == "standalone" ? 38000 : 68000, RegistryValueKind.DWord);
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
