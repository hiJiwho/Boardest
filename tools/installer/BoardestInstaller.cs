using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace Boardest.Installer {
    public enum ProductType {
        Teacher,
        Class,
        Cloud
    }

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

            // Launch Application
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            RunInstaller(args);
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

        private static void RunInstaller(string[] args) {
            var options = ParseArgs(args);
            Application.Run(new InstallerForm(options));
        }

        private static InstallerOptions ParseArgs(string[] args) {
            var opt = new InstallerOptions {
                Product = ProductType.Teacher,
                Version = "5.3.6",
                IsUpdate = false,
                IsSilent = false
            };

            string exeName = Process.GetCurrentProcess().MainModule.FileName.ToLower();
            if (exeName.Contains("cloud")) opt.Product = ProductType.Cloud;
            else if (exeName.Contains("class")) opt.Product = ProductType.Class;
            else if (exeName.Contains("teacher")) opt.Product = ProductType.Teacher;

            for (int i = 0; i < args.Length; i++) {
                string a = args[i].ToLower();
                if (a == "--update") opt.IsUpdate = true;
                else if (a == "--silent") opt.IsSilent = true;
                else if (a == "--product" && i + 1 < args.Length) {
                    string p = args[++i].ToLower();
                    if (p.Contains("cloud")) opt.Product = ProductType.Cloud;
                    else if (p.Contains("class")) opt.Product = ProductType.Class;
                    else if (p.Contains("teacher")) opt.Product = ProductType.Teacher;
                } else if (a == "--version" && i + 1 < args.Length) {
                    opt.Version = args[++i];
                }
            }
            return opt;
        }
    }

    public class InstallerOptions {
        public ProductType Product { get; set; }
        public string Version { get; set; }
        public bool IsUpdate { get; set; }
        public bool IsSilent { get; set; }
    }

    public class InstallerForm : Form {
        [DllImport("user32.dll")]
        public static extern bool ReleaseCapture();
        [DllImport("user32.dll")]
        public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);

        private readonly InstallerOptions _options;
        private WebView2 _webView;
        private bool _isInstalling = false;
        private string _targetInstallDir;
        private string _installedMainExe;

        public InstallerForm(InstallerOptions options) {
            _options = options;
            InitializeComponent();
        }

        private void InitializeComponent() {
            this.Text = "Boardest 온라인 설치 마법사";
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.Size = new Size(680, 520);
            this.BackColor = Color.FromArgb(11, 12, 16);
            this.ShowIcon = false;

            _webView = new WebView2 {
                Dock = DockStyle.Fill
            };
            this.Controls.Add(_webView);

            InitDefaultPaths();
            InitWebView();
        }

        private void InitDefaultPaths() {
            if (_options.Product == ProductType.Teacher) {
                _targetInstallDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Programs", "BoardestTeacher"
                );
            } else if (_options.Product == ProductType.Class) {
                _targetInstallDir = "WindowsApps (MSIX 패키지 자동 설치)";
            } else {
                _targetInstallDir = "WindowsApps (MSIX 패키지 자동 설치)";
            }
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
                MessageBox.Show("WebView2 초기화 실패: " + ex.Message, "오류", MessageBoxButtons.OK, MessageBoxIcon.Error);
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
            string localHtml = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "installer.html");
            if (File.Exists(localHtml)) return File.ReadAllText(localHtml, Encoding.UTF8);

            return "<html><body style='background:#111;color:#fff;'><h3>Boardest Installer</h3></body></html>";
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
            string pName = "Boardest Teacher";
            string pDesc = "교사용 스마트 전자칠판 & 수업 관리 솔루션";
            string heroIcon = "🎓";
            bool hideDir = false;

            if (_options.Product == ProductType.Class) {
                pName = "Boardest Class";
                pDesc = "스마트 전자칠판 교실 전용 솔루션 (MSIX)";
                heroIcon = "🏫";
                hideDir = true;
            } else if (_options.Product == ProductType.Cloud) {
                pName = "Boardest Class Cloud";
                pDesc = "클라우드 연동 전용 스마트 교실 솔루션 (MSIX)";
                heroIcon = "☁️";
                hideDir = true;
            }

            string json = string.Format(
                "{{\"productName\":\"{0}\",\"productVersion\":\"{1}\",\"productDesc\":\"{2}\",\"heroIcon\":\"{3}\",\"installDir\":\"{4}\",\"hideDirField\":{5},\"isUpdate\":{6}}}",
                EscapeJson(pName),
                EscapeJson(_options.Version),
                EscapeJson(pDesc),
                EscapeJson(heroIcon),
                EscapeJson(_targetInstallDir),
                hideDir ? "true" : "false",
                _options.IsUpdate ? "true" : "false"
            );

            this.BeginInvoke(new Action(() => {
                _webView.CoreWebView2.ExecuteScriptAsync(string.Format("window.initData({0});", json));
            }));
        }

        private void NotifyProgress(int pct, string status, string bytesText, string speedText, string logMsg) {
            this.BeginInvoke(new Action(() => {
                string script = string.Format(
                    "window.onProgress({0}, \"{1}\", \"{2}\", \"{3}\", \"{4}\");",
                    pct,
                    EscapeJson(status),
                    EscapeJson(bytesText),
                    EscapeJson(speedText),
                    EscapeJson(logMsg)
                );
                _webView.CoreWebView2.ExecuteScriptAsync(script);
            }));
        }

        private void NotifyComplete() {
            this.BeginInvoke(new Action(() => {
                _webView.CoreWebView2.ExecuteScriptAsync("window.onComplete();");
            }));
        }

        private void NotifyError(string err) {
            this.BeginInvoke(new Action(() => {
                _webView.CoreWebView2.ExecuteScriptAsync(string.Format("window.onError(\"{0}\");", EscapeJson(err)));
            }));
        }

        private string EscapeJson(string s) {
            if (s == null) return "";
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\r", "").Replace("\n", "\\n");
        }

        private async Task PerformInstallation(bool createDesktop, bool createStartMenu) {
            try {
                // 1. Process Cleanup (같은 앱 프로세스 종료)
                NotifyProgress(5, "실행 중인 기존 프로그램 확인 및 종료 중...", "", "", "[1/4] 실행 중인 이전 버전 프로세스 정리 중...");
                KillTargetProcesses();
                Thread.Sleep(600);

                // 2. Certificate Check & Install (For MSIX Class/Cloud)
                if (_options.Product == ProductType.Class || _options.Product == ProductType.Cloud) {
                    NotifyProgress(15, "Boardest 공식 디지털 서명 인증서 확인 및 설치 중...", "", "", "[2/4] 공식 보안 인증서(BoardestCert.cer) 등록 중...");
                    InstallCertificate();
                }

                // 3. Download Package (or use pre-downloaded package if local)
                string tempPackagePath = await DownloadPackageAsync();

                // 4. Install / Extract
                if (_options.Product == ProductType.Teacher) {
                    NotifyProgress(75, "압축 해제 및 프로그램 파일 설치 중...", "", "", "[3/4] 최신 파일 압축 해제 및 설치 디렉토리 반영 중...");
                    ExtractZipPackage(tempPackagePath);

                    if (createDesktop || createStartMenu) {
                        NotifyProgress(90, "바탕화면 및 시작메뉴 바로가기 생성 중...", "", "", "[4/4] 시스템 바로가기 등록 중...");
                        CreateShortcuts(createDesktop, createStartMenu);
                    }
                } else {
                    NotifyProgress(75, "MSIX 패키지 시스템 배포 및 등록 중...", "", "", "[3/4] PowerShell Add-AppxPackage 배포 진행 중...");
                    InstallMsixPackage(tempPackagePath);
                }

                NotifyProgress(100, "설치 완료!", "100%", "", "🎉 모든 설치 단계가 성공적으로 완료되었습니다.");
                Thread.Sleep(500);
                NotifyComplete();
            } catch (Exception ex) {
                NotifyError(ex.Message);
            }
        }

        private void KillTargetProcesses() {
            string[] targets = new string[0];
            if (_options.Product == ProductType.Teacher) {
                targets = new[] { "BoardestTeacher", "bst-teacher", "boardest_teacher" };
            } else if (_options.Product == ProductType.Class) {
                targets = new[] { "boardest", "Boardest" };
            } else if (_options.Product == ProductType.Cloud) {
                targets = new[] { "Boardest-Class-Cloud", "boardest-cloud" };
            }

            foreach (var name in targets) {
                try {
                    foreach (var proc in Process.GetProcessesByName(name)) {
                        try {
                            proc.Kill();
                            proc.WaitForExit(2000);
                        } catch { }
                    }
                } catch { }
            }
        }

        private void InstallCertificate() {
            try {
                // Check if certificate thumbprint is already installed
                string thumbprint = "006d6eb59ce360dbd15bf1367ea107b34033c7a3"; // BoardestCert Thumbprint
                bool alreadyInstalled = false;

                using (var store = new X509Store(StoreName.Root, StoreLocation.LocalMachine)) {
                    store.Open(OpenFlags.ReadOnly);
                    var matches = store.Certificates.Find(X509FindType.FindByThumbprint, thumbprint, false);
                    if (matches.Count > 0) alreadyInstalled = true;
                }

                if (!alreadyInstalled) {
                    using (var store = new X509Store(StoreName.Root, StoreLocation.CurrentUser)) {
                        store.Open(OpenFlags.ReadOnly);
                        var matches = store.Certificates.Find(X509FindType.FindByThumbprint, thumbprint, false);
                        if (matches.Count > 0) alreadyInstalled = true;
                    }
                }

                if (alreadyInstalled) {
                    NotifyProgress(25, "보안 인증서가 이미 등록되어 있습니다.", "", "", "보안 인증서 확인 완료.");
                    return;
                }

                // Extract embedded BoardestCert.cer
                string tempCer = Path.Combine(Path.GetTempPath(), "BoardestCert.cer");
                using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("BoardestCert.cer")) {
                    if (stream != null) {
                        using (var fs = new FileStream(tempCer, FileMode.Create, FileAccess.Write)) {
                            stream.CopyTo(fs);
                        }
                    }
                }

                if (File.Exists(tempCer)) {
                    // Install to Trusted Root via certutil
                    var psi = new ProcessStartInfo {
                        FileName = "certutil.exe",
                        Arguments = string.Format("-addstore -f \"Root\" \"{0}\"", tempCer),
                        CreateNoWindow = true,
                        UseShellExecute = false
                    };
                    var p = Process.Start(psi);
                    p.WaitForExit(5000);
                }
            } catch (Exception ex) {
                Debug.WriteLine("Certificate install warning: " + ex.Message);
            }
        }

        private async Task<string> DownloadPackageAsync() {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string localCandidate = null;

            if (_options.Product == ProductType.Teacher) {
                if (File.Exists(Path.Combine(baseDir, "bst-teacher-windows.zip"))) localCandidate = Path.Combine(baseDir, "bst-teacher-windows.zip");
                else if (File.Exists(Path.Combine(baseDir, "boardest-teacher-windows.zip"))) localCandidate = Path.Combine(baseDir, "boardest-teacher-windows.zip");
            } else if (_options.Product == ProductType.Class) {
                if (File.Exists(Path.Combine(baseDir, "boardest.msix"))) localCandidate = Path.Combine(baseDir, "boardest.msix");
                else if (File.Exists(Path.Combine(baseDir, "boardest-class.msix"))) localCandidate = Path.Combine(baseDir, "boardest-class.msix");
                else if (File.Exists(Path.Combine(baseDir, "boardest.appx"))) localCandidate = Path.Combine(baseDir, "boardest.appx");
            } else if (_options.Product == ProductType.Cloud) {
                if (File.Exists(Path.Combine(baseDir, "boardest-cloud.msix"))) localCandidate = Path.Combine(baseDir, "boardest-cloud.msix");
                else if (File.Exists(Path.Combine(baseDir, "boardest-class-cloud.msix"))) localCandidate = Path.Combine(baseDir, "boardest-class-cloud.msix");
                else if (File.Exists(Path.Combine(baseDir, "boardest-cloud.appx"))) localCandidate = Path.Combine(baseDir, "boardest-cloud.appx");
            }

            if (localCandidate != null) {
                NotifyProgress(65, "로컬 패키지 감지됨: 즉시 설치 모드로 진행합니다.", "100%", "", "로컬 패키지 발견: " + Path.GetFileName(localCandidate));
                return localCandidate;
            }

            // Online Download URLs
            List<string> urls = new List<string>();
            string extension = _options.Product == ProductType.Teacher ? ".zip" : ".msix";

            if (_options.Product == ProductType.Teacher) {
                urls.Add(string.Format("https://github.com/hiJiwho/Boardest/releases/download/v{0}/bst-teacher-windows.zip", _options.Version));
                urls.Add("https://github.com/hiJiwho/Boardest/releases/latest/download/bst-teacher-windows.zip");
                urls.Add("https://boardest-downloads.web.app/bst-teacher-windows.zip");
            } else if (_options.Product == ProductType.Class) {
                urls.Add(string.Format("https://github.com/hiJiwho/Boardest/releases/download/v{0}/boardest.msix", _options.Version));
                urls.Add("https://github.com/hiJiwho/Boardest/releases/latest/download/boardest.msix");
                urls.Add("https://boardest-downloads.web.app/boardest.msix");
            } else {
                urls.Add(string.Format("https://github.com/hiJiwho/Boardest/releases/download/v{0}/boardest-cloud.msix", _options.Version));
                urls.Add("https://github.com/hiJiwho/Boardest/releases/latest/download/boardest-cloud.msix");
                urls.Add("https://boardest-downloads.web.app/boardest-cloud.msix");
            }

            string downloadDest = Path.Combine(Path.GetTempPath(), "Boardest_" + Guid.NewGuid().ToString("N").Substring(0, 8) + extension);

            Exception lastErr = null;
            foreach (var url in urls) {
                try {
                    NotifyProgress(20, "최신 배포 패키지 연결 중...", "0.0 MB", "", "다운로드 연결: " + url);
                    await DownloadWithProgress(url, downloadDest);
                    if (File.Exists(downloadDest) && new FileInfo(downloadDest).Length > 1024 * 100) {
                        return downloadDest;
                    }
                } catch (Exception ex) {
                    lastErr = ex;
                    Debug.WriteLine("Download failed for " + url + ": " + ex.Message);
                }
            }

            throw new Exception("패키지 다운로드 실패: " + (lastErr != null ? lastErr.Message : "다운로드 서버 응답 없음"));
        }

        private async Task DownloadWithProgress(string url, string destPath) {
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12 | SecurityProtocolType.Tls11 | SecurityProtocolType.Tls;

            var request = (HttpWebRequest)WebRequest.Create(url);
            request.UserAgent = "Boardest-Installer/5.3.6";
            request.Timeout = 60000;

            using (var response = await request.GetResponseAsync()) {
                long totalBytes = response.ContentLength;
                using (var responseStream = response.GetResponseStream())
                using (var fileStream = new FileStream(destPath, FileMode.Create, FileAccess.Write, FileShare.None)) {
                    byte[] buffer = new byte[65536];
                    long totalRead = 0;
                    int bytesRead;
                    var sw = Stopwatch.StartNew();
                    long lastRead = 0;
                    long lastTime = 0;

                    while ((bytesRead = await responseStream.ReadAsync(buffer, 0, buffer.Length)) > 0) {
                        await fileStream.WriteAsync(buffer, 0, bytesRead);
                        totalRead += bytesRead;

                        long now = sw.ElapsedMilliseconds;
                        if (now - lastTime > 150 || totalRead == totalBytes) {
                            double speedMbps = 0;
                            if (now > lastTime) {
                                speedMbps = ((totalRead - lastRead) / 1024.0 / 1024.0) / ((now - lastTime) / 1000.0);
                            }
                            lastRead = totalRead;
                            lastTime = now;

                            int pct = totalBytes > 0 ? (int)((totalRead * 50) / totalBytes) + 20 : 45;
                            string bytesStr = string.Format("{0:F1} MB / {1:F1} MB", totalRead / 1048576.0, totalBytes / 1048576.0);
                            string speedStr = string.Format("{0:F1} MB/s", speedMbps);

                            NotifyProgress(pct, "최신 프로그램 바이너리 다운로드 중...", bytesStr, speedStr, null);
                        }
                    }
                }
            }
        }

        private void ExtractZipPackage(string zipPath) {
            Directory.CreateDirectory(_targetInstallDir);

            using (var archive = ZipFile.OpenRead(zipPath)) {
                int count = 0;
                int total = archive.Entries.Count;

                foreach (var entry in archive.Entries) {
                    string fullPath = Path.Combine(_targetInstallDir, entry.FullName);
                    if (string.IsNullOrEmpty(entry.Name)) {
                        Directory.CreateDirectory(fullPath);
                        continue;
                    }

                    string dir = Path.GetDirectoryName(fullPath);
                    if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);

                    entry.ExtractToFile(fullPath, true);
                    count++;

                    if (count % 10 == 0 || count == total) {
                        int pct = 70 + (int)((count * 20.0) / total);
                        NotifyProgress(pct, string.Format("파일 설치 중 ({0}/{1})...", count, total), "", "", entry.Name);
                    }
                }
            }

            // Find main executable in installed folder
            string[] candidates = new[] { "BoardestTeacher.exe", "bst-teacher.exe", "boardest_teacher.exe", "boardest.exe" };
            foreach (var c in candidates) {
                string p = Path.Combine(_targetInstallDir, c);
                if (File.Exists(p)) {
                    _installedMainExe = p;
                    break;
                }
            }
        }

        private void CreateShortcuts(bool createDesktop, bool createStartMenu) {
            if (string.IsNullOrEmpty(_installedMainExe) || !File.Exists(_installedMainExe)) return;

            string shortcutName = "Boardest Teacher.lnk";
            Type shellType = Type.GetTypeFromProgID("WScript.Shell");
            if (shellType == null) return;
            dynamic shell = Activator.CreateInstance(shellType);

            if (createDesktop) {
                string desktopPath = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                string lnkPath = Path.Combine(desktopPath, shortcutName);
                dynamic shortcut = shell.CreateShortcut(lnkPath);
                shortcut.TargetPath = _installedMainExe;
                shortcut.WorkingDirectory = Path.GetDirectoryName(_installedMainExe);
                shortcut.Description = "Boardest Teacher 전자칠판 수업 관리";
                shortcut.Save();
            }

            if (createStartMenu) {
                string programsPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Boardest");
                Directory.CreateDirectory(programsPath);
                string lnkPath = Path.Combine(programsPath, shortcutName);
                dynamic shortcut = shell.CreateShortcut(lnkPath);
                shortcut.TargetPath = _installedMainExe;
                shortcut.WorkingDirectory = Path.GetDirectoryName(_installedMainExe);
                shortcut.Description = "Boardest Teacher 전자칠판 수업 관리";
                shortcut.Save();
            }
        }

        private void InstallMsixPackage(string msixPath) {
            NotifyProgress(80, "MSIX 패키지 등록 중 (Add-AppxPackage)...", "", "", "PowerShell Add-AppxPackage 실행...");

            string script = string.Format("Add-AppxPackage -Path '{0}' -ForceApplicationShutdown -ForceUpdateFromAnyVersion", msixPath.Replace("'", "''"));
            var psi = new ProcessStartInfo {
                FileName = "powershell.exe",
                Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \"" + script + "\"",
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardError = true,
                RedirectStandardOutput = true
            };

            var p = Process.Start(psi);
            string stderr = p.StandardError.ReadToEnd();
            p.WaitForExit(60000);

            if (p.ExitCode != 0 && !string.IsNullOrEmpty(stderr)) {
                throw new Exception("MSIX 설치 실패: " + stderr);
            }
        }

        private void LaunchApp() {
            try {
                if (_options.Product == ProductType.Teacher) {
                    if (!string.IsNullOrEmpty(_installedMainExe) && File.Exists(_installedMainExe)) {
                        Process.Start(new ProcessStartInfo {
                            FileName = _installedMainExe,
                            WorkingDirectory = Path.GetDirectoryName(_installedMainExe)
                        });
                    }
                } else if (_options.Product == ProductType.Class) {
                    Process.Start("powershell.exe", "-NoProfile -Command \"explorer.exe shell:AppsFolder\\$(Get-AppxPackage jiwho.boardest.bst | Select-Object -ExpandProperty PackageFamilyName)!App\"");
                } else if (_options.Product == ProductType.Cloud) {
                    Process.Start("powershell.exe", "-NoProfile -Command \"explorer.exe shell:AppsFolder\\$(Get-AppxPackage jiwho.boardest.cloud | Select-Object -ExpandProperty PackageFamilyName)!App\"");
                }
            } catch (Exception ex) {
                Debug.WriteLine("LaunchApp error: " + ex.Message);
            }
        }
    }
}
