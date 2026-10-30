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

namespace Boardest.ClassInstaller {
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
            Application.Run(new ClassInstallerForm(args));
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

    public class ClassInstallerForm : Form {
        [DllImport("user32.dll")]
        public static extern bool ReleaseCapture();
        [DllImport("user32.dll")]
        public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);

        private readonly string[] _args;
        private readonly bool _isUpdate;
        private WebView2 _webView;
        private bool _isInstalling = false;

        public ClassInstallerForm(string[] args) {
            _args = args;
            _isUpdate = args != null && Array.Exists(args, a => a.Equals("--update", StringComparison.OrdinalIgnoreCase));
            InitializeComponent();
        }

        private void InitializeComponent() {
            this.Text = "Boardest Class 설치 마법사";
            this.FormBorderStyle = FormBorderStyle.None;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.Size = new Size(680, 520);
            this.BackColor = Color.FromArgb(11, 12, 16);
            this.ShowIcon = false;

            _webView = new WebView2 { Dock = DockStyle.Fill };
            this.Controls.Add(_webView);

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
            return "<html><body><h3>Boardest Class Installer</h3></body></html>";
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
                        Task.Run(() => PerformInstallation());
                    }
                } else if (json.Contains("\"action\":\"startInstall\"")) {
                    if (!_isInstalling) {
                        _isInstalling = true;
                        Task.Run(() => PerformInstallation());
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
                "{{\"productName\":\"Boardest Class\",\"productType\":\"Class\",\"productVersion\":\"5.3.7\",\"productDesc\":\"초·중·고 교실 스마트 전자칠판 전용 통합 교육 솔루션\",\"heroIcon\":\"🏫\",\"installDir\":\"WindowsApps (MSIX 현대 패키지)\",\"hideDirField\":true,\"isUninstall\":false,\"logoBase64\":\"{0}\"}}",
                logoB64
            );
            RunScript(string.Format("if(window.receiveInitData) window.receiveInitData({0});", json));
        }

        private void PerformInstallation() {
            try {
                NotifyProgress(20, "기존 실행 중인 전자칠판 프로세스 정리 중...", "프로세스 안전 종료...");
                KillRunningProcesses();

                NotifyProgress(45, "보안 서명 인증서 등록 중...", "신뢰할 수 있는 루트 인증서 등록...");
                InstallCertificate();

                NotifyProgress(70, "내장된 MSIX 패키지 배포 중...", "패키지 추출 및 Windows 배포 중...");
                InstallMsixPackage();

                NotifyProgress(100, "Boardest Class 설치 완료!", "설치가 성공적으로 완료되었습니다!");
            } catch (Exception ex) {
                NotifyProgress(100, "설치 오류: " + ex.Message, "오류 발생: " + ex.ToString());
            }
        }

        private void KillRunningProcesses() {
            string[] names = { "boardest", "Boardest", "Boardest-Class", "bst-overlay-panser" };
            foreach (var name in names) {
                try {
                    foreach (var p in Process.GetProcessesByName(name)) {
                        p.Kill();
                        p.WaitForExit(3000);
                    }
                } catch { }
            }
        }

        private void InstallCertificate() {
            try {
                string tempCer = Path.Combine(Path.GetTempPath(), "BoardestCert.cer");
                Program.ExtractResourceToFile("BoardestCert.cer", tempCer);

                if (File.Exists(tempCer)) {
                    RunSilentProcess("certutil.exe", "-addstore -f \"Root\" \"" + tempCer + "\"");
                    RunSilentProcess("certutil.exe", "-addstore -f \"TrustedPeople\" \"" + tempCer + "\"");
                    RunSilentProcess("certutil.exe", "-user -addstore -f \"Root\" \"" + tempCer + "\"");
                    RunSilentProcess("certutil.exe", "-user -addstore -f \"TrustedPeople\" \"" + tempCer + "\"");
                }
            } catch (Exception ex) {
                Debug.WriteLine("InstallCertificate warning: " + ex.Message);
            }
        }

        private void InstallMsixPackage() {
            string tempMsix = Path.Combine(Path.GetTempPath(), "boardest-class-install.msix");
            Program.ExtractResourceToFile("package.msix", tempMsix);

            if (!File.Exists(tempMsix)) {
                // If package.msix wasn't embedded, check local file
                string local = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "boardest-class.msix");
                if (File.Exists(local)) tempMsix = local;
                else {
                    local = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "boardest.msix");
                    if (File.Exists(local)) tempMsix = local;
                }
            }

            if (!File.Exists(tempMsix)) {
                throw new FileNotFoundException("MSIX 설치 패키지를 찾을 수 없습니다.");
            }

            string psScript = string.Format(
                "Add-AppxPackage -Path '{0}' -ForceApplicationShutdown -ForceUpdateFromAnyVersion",
                tempMsix.Replace("'", "''")
            );

            RunSilentProcess("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -Command \"" + psScript + "\"");
        }

        private void LaunchApp() {
            try {
                // Launch via shell:AppsFolder
                var psi = new ProcessStartInfo {
                    FileName = "powershell.exe",
                    Arguments = "-NoProfile -ExecutionPolicy Bypass -Command \"Start-Process (Get-StartApps 'Boardest Class').AppID\"",
                    CreateNoWindow = true,
                    UseShellExecute = false
                };
                Process.Start(psi);
            } catch {
                try {
                    Process.Start("explorer.exe", "shell:AppsFolder");
                } catch { }
            }
        }

        private void RunSilentProcess(string fileName, string args) {
            try {
                var psi = new ProcessStartInfo {
                    FileName = fileName,
                    Arguments = args,
                    CreateNoWindow = true,
                    UseShellExecute = false,
                    WindowStyle = ProcessWindowStyle.Hidden
                };
                var p = Process.Start(psi);
                if (p != null) {
                    p.WaitForExit(40000);
                }
            } catch (Exception ex) {
                Debug.WriteLine("RunSilentProcess error: " + ex);
            }
        }

        private void NotifyProgress(int pct, string status, string log) {
            string script = string.Format(
                "if(window.updateProgress) window.updateProgress({0}, '{1}', '', '', '{2}');",
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

        private string EscapeJs(string s) {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("\\", "\\\\").Replace("'", "\\'").Replace("\r", "").Replace("\n", " ");
        }
    }
}
