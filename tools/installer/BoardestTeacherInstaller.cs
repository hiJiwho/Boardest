using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

[assembly: AssemblyTitle("Boardest Unified Online Installer")]
[assembly: AssemblyDescription("Boardest 통합 온라인 설치 관리자 (Class / Teacher / Cloud)")]
[assembly: AssemblyCompany("Boardest Team")]
[assembly: AssemblyProduct("Boardest Online Installer")]
[assembly: AssemblyCopyright("Copyright © 2026 Boardest. All rights reserved.")]
[assembly: AssemblyVersion("5.4.0.0")]
[assembly: AssemblyFileVersion("5.4.0.0")]

namespace BoardestInstaller
{
    public class InstallerForm : Form
    {
        // =========================================================================
        // [보안 정책] 오직 https://boardest-windows-installer.web.app 만 명령 실행 허용!
        // =========================================================================
        private const string TrustedHost = "boardest-windows-installer.web.app";
        private const string TrustedInstallerUrl = "https://boardest-windows-installer.web.app/";

        // Win32 API: 창틀 닫기(X) 버튼 비활성화 (최소화만 가능하도록 강제)
        [DllImport("user32.dll")]
        private static extern IntPtr GetSystemMenu(IntPtr hWnd, bool bRevert);

        [DllImport("user32.dll")]
        private static extern bool EnableMenuItem(IntPtr hMenu, uint uIDEnableItem, uint uEnable);

        private const uint SC_CLOSE = 0xF060;
        private const uint MF_BYCOMMAND = 0x00000000;
        private const uint MF_GRAYED = 0x00000001;
        private const uint MF_DISABLED = 0x00000002;

        private WebView2 _webView;
        private string _productType = "Teacher"; // "Class", "Teacher", "Cloud"
        private string _productName = "Boardest 통합 온라인 설치";
        private string _productVersion = "5.4.0";
        private string _teacherInstallDir;
        private string _exeFileName = "";
        private bool _needsProductSelection = false;
        private bool _isInstalling = false;
        private bool _allowClose = false;

        public InstallerForm()
        {
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;

            // 실행 파일 이름 확인:
            // - boardest-class -> 교실 앱 (Class)
            // - boardest-teacher -> 교사 앱 (Teacher)
            // - boardest-cloud -> 클라우드 앱 (Cloud)
            // - 그 외 이름 -> 3개 중 무엇을 설치할지 물어봄 (_needsProductSelection = true)
            DetectProductFromExecutableName();

            _teacherInstallDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Programs",
                "BoardestTeacher"
            );

            // 창틀(Title Bar) 표시 + 최소화만 가능하도록 설정 (최대화 비활성화, 닫기 버튼 비활성화)
            this.Text = _needsProductSelection
                ? "Boardest 통합 온라인 설치 마법사"
                : (_productName + " 온라인 설치 마법사");
            this.Size = new Size(760, 560);
            this.FormBorderStyle = FormBorderStyle.FixedSingle;
            this.MaximizeBox = false;
            this.MinimizeBox = true;
            this.ControlBox = true;
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = Color.FromArgb(11, 12, 16);

            try
            {
                this.Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            }
            catch { }

            _webView = new WebView2();
            _webView.Dock = DockStyle.Fill;
            _webView.DefaultBackgroundColor = Color.FromArgb(11, 12, 16);
            this.Controls.Add(_webView);

            this.Load += async (s, e) =>
            {
                DisableCloseButtonOnWindowFrame();
                await InitializeWebViewAsync();
            };
        }

        private void DetectProductFromExecutableName()
        {
            string exeName = "";
            try
            {
                exeName = Path.GetFileNameWithoutExtension(Application.ExecutablePath).ToLowerInvariant();
            }
            catch { }

            _exeFileName = exeName;

            string[] args = Environment.GetCommandLineArgs();
            for (int i = 1; i < args.Length; i++)
            {
                string arg = (args[i] ?? "").ToLowerInvariant();
                if (arg.Contains("boardest-class") || arg == "--class")
                {
                    exeName = "boardest-class";
                }
                else if (arg.Contains("boardest-teacher") || arg == "--teacher")
                {
                    exeName = "boardest-teacher";
                }
                else if (arg.Contains("boardest-cloud") || arg == "--cloud")
                {
                    exeName = "boardest-cloud";
                }
            }

            if (exeName.Contains("boardest-class"))
            {
                _productType = "Class";
                _productName = "Boardest Class";
                _needsProductSelection = false;
            }
            else if (exeName.Contains("boardest-teacher"))
            {
                _productType = "Teacher";
                _productName = "Boardest Teacher";
                _needsProductSelection = false;
            }
            else if (exeName.Contains("boardest-cloud"))
            {
                _productType = "Cloud";
                _productName = "Boardest Cloud";
                _needsProductSelection = false;
            }
            else
            {
                _productType = "Class";
                _productName = "Boardest 통합 온라인 설치";
                _needsProductSelection = true;
            }
        }

        private void DisableCloseButtonOnWindowFrame()
        {
            try
            {
                IntPtr hMenu = GetSystemMenu(this.Handle, false);
                if (hMenu != IntPtr.Zero)
                {
                    EnableMenuItem(hMenu, SC_CLOSE, MF_BYCOMMAND | MF_DISABLED | MF_GRAYED);
                }
            }
            catch { }
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            // 설치 중이거나 명시적 종료 허용 전에는 창 닫기 차단 (최소화만 가능)
            if (!_allowClose && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                this.WindowState = FormWindowState.Minimized;
                return;
            }
            base.OnFormClosing(e);
        }

        // =========================================================================
        // [핵심 안전 로직] 오직 https://boardest-windows-installer.web.app 출처인지 검증
        // =========================================================================
        private bool IsTrustedOrigin(string urlString)
        {
            if (string.IsNullOrEmpty(urlString)) return false;
            Uri uri;
            if (!Uri.TryCreate(urlString, UriKind.Absolute, out uri)) return false;

            bool isHttps = string.Equals(uri.Scheme, "https", StringComparison.OrdinalIgnoreCase);
            bool isExactHost = string.Equals(uri.Host, TrustedHost, StringComparison.OrdinalIgnoreCase);
            return isHttps && isExactHost;
        }

        private async Task InitializeWebViewAsync()
        {
            try
            {
                string userDataFolder = Path.Combine(Path.GetTempPath(), "BoardestInstaller_WebView2");
                var env = await CoreWebView2Environment.CreateAsync(null, userDataFolder);
                await _webView.EnsureCoreWebView2Async(env);

                _webView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = false;
                _webView.CoreWebView2.Settings.AreDevToolsEnabled = false;
                _webView.CoreWebView2.Settings.IsStatusBarEnabled = false;
                _webView.CoreWebView2.Settings.IsZoomControlEnabled = false;

                // [안전 로직 1] https://boardest-windows-installer.web.app 외의 모든 URL 이동 차단!
                _webView.CoreWebView2.NavigationStarting += (s, args) =>
                {
                    if (!IsTrustedOrigin(args.Uri))
                    {
                        args.Cancel = true;
                    }
                };

                // [안전 로직 2] 새 창 팝업 열기 차단
                _webView.CoreWebView2.NewWindowRequested += (s, args) =>
                {
                    args.Handled = true;
                };

                // [안전 로직 3] 웹 메시지 수신 시 발신 URL 검증
                _webView.CoreWebView2.WebMessageReceived += OnWebMessageReceived;

                string prodQuery = _needsProductSelection ? "Select" : _productType;
                string targetUrl = string.Format(
                    "{0}?exe={1}&product={2}&ver={3}&t={4}",
                    TrustedInstallerUrl,
                    Uri.EscapeDataString(_exeFileName ?? ""),
                    Uri.EscapeDataString(prodQuery),
                    Uri.EscapeDataString(_productVersion),
                    DateTime.UtcNow.Ticks
                );

                _webView.CoreWebView2.Navigate(targetUrl);
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "WebView2 초기화 실패 (Microsoft Edge WebView2 런타임이 필요합니다): " + ex.Message,
                    "Boardest 온라인 설치 오류",
                    MessageBoxButtons.OK,
                    MessageBoxIcon.Error
                );
            }
        }

        private void OnWebMessageReceived(object sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            try
            {
                // [절대 보안 검증] 메시지 발신 Source와 현재 WebView2 Source가 모두
                // https://boardest-windows-installer.web.app 인지 엄격히 확인!
                string senderUrl = e.Source;
                string currentWebViewUrl = (_webView != null && _webView.CoreWebView2 != null)
                    ? _webView.CoreWebView2.Source
                    : "";

                if (!IsTrustedOrigin(senderUrl) || !IsTrustedOrigin(currentWebViewUrl))
                {
                    // 허용된 URL이 아니면 어떠한 명령도 듣지 않고 즉시 무시!
                    return;
                }

                string json = e.TryGetWebMessageAsString();
                if (string.IsNullOrEmpty(json)) return;

                string action = ExtractJsonString(json, "action");
                string reqId = ExtractJsonString(json, "reqId");

                if (action == "uiReady")
                {
                    SendInitData();
                }
                else if (action == "minimize")
                {
                    this.WindowState = FormWindowState.Minimized;
                }
                else if (action == "close")
                {
                    if (!_isInstalling)
                    {
                        _allowClose = true;
                        Application.Exit();
                    }
                }
                else if (action == "selectProduct")
                {
                    string selected = ExtractJsonString(json, "productType");
                    if (!string.IsNullOrEmpty(selected))
                    {
                        SetSelectedProduct(selected);
                    }
                }
                else if (action == "killProcesses")
                {
                    Task.Run(() => HandleKillProcessesCmd(reqId));
                }
                else if (action == "installCertificate")
                {
                    Task.Run(async () => await HandleInstallCertificateCmd(reqId, json));
                }
                else if (action == "downloadPackage")
                {
                    Task.Run(async () => await HandleDownloadPackageCmd(reqId, json));
                }
                else if (action == "extractAndCopyApp")
                {
                    Task.Run(() => HandleExtractAndCopyAppCmd(reqId, json));
                }
                else if (action == "installMsixPackage")
                {
                    Task.Run(() => HandleInstallMsixPackageCmd(reqId, json));
                }
                else if (action == "runPowerShell")
                {
                    Task.Run(() => HandleRunPowerShellCmd(reqId, json));
                }
                else if (action == "startInstall")
                {
                    // 하위 호환 일괄 실행 핸들러
                    if (_isInstalling) return;
                    string selected = ExtractJsonString(json, "productType");
                    if (!string.IsNullOrEmpty(selected)) SetSelectedProduct(selected);

                    bool createDesktop = !json.Contains("\"createDesktop\":false");
                    bool createStartMenu = !json.Contains("\"createStartMenu\":false");
                    string installScope = json.Contains("\"installScope\":\"standalone\"") ? "standalone" : "full";
                    Task.Run(async () => await RunInstallProcessAsync(createDesktop, createStartMenu, installScope));
                }
                else if (action == "launchApp")
                {
                    LaunchInstalledApp();
                    _allowClose = true;
                    Application.Exit();
                }
            }
            catch { }
        }

        private void SetSelectedProduct(string productType)
        {
            _productType = productType;
            if (productType == "Class") _productName = "Boardest Class";
            else if (productType == "Cloud") _productName = "Boardest Cloud";
            else _productName = "Boardest Teacher";

            if (this.InvokeRequired)
            {
                this.Invoke(new Action(() =>
                {
                    this.Text = _productName + " 온라인 설치 마법사";
                }));
            }
            else
            {
                this.Text = _productName + " 온라인 설치 마법사";
            }
        }

        private string ExtractJsonString(string json, string key)
        {
            if (string.IsNullOrEmpty(json) || string.IsNullOrEmpty(key)) return "";
            Match m = Regex.Match(json, "\"" + Regex.Escape(key) + "\"\\s*:\\s*\"((?:\\\\.|[^\"])*)\"");
            if (m.Success)
            {
                return Regex.Unescape(m.Groups[1].Value);
            }
            return "";
        }

        private void SendInitData()
        {
            string logoBase64 = "";
            try
            {
                var asm = Assembly.GetExecutingAssembly();
                using (var stream = asm.GetManifestResourceStream("app_logo.png"))
                {
                    if (stream != null)
                    {
                        using (var ms = new MemoryStream())
                        {
                            stream.CopyTo(ms);
                            logoBase64 = Convert.ToBase64String(ms.ToArray());
                        }
                    }
                }
            }
            catch { }

            string escapedDir = _teacherInstallDir.Replace("\\", "\\\\");
            string payload = string.Format(
                "{{\"productType\":\"{0}\",\"productName\":\"{1}\",\"productVersion\":\"{2}\",\"installDir\":\"{3}\",\"teacherInstallDir\":\"{3}\",\"isUninstall\":false,\"needsProductSelection\":{4},\"logoBase64\":\"{5}\",\"isAdmin\":true}}",
                _productType,
                _productName,
                _productVersion,
                escapedDir,
                _needsProductSelection ? "true" : "false",
                logoBase64
            );
            ExecuteScriptSafe(string.Format("if(window.receiveInitData) window.receiveInitData({0});", payload));
        }

        private void ResolveHostCommand(string reqId, bool success, string resultJsonObj, string errorMsg)
        {
            if (string.IsNullOrEmpty(reqId)) return;
            string safeResult = string.IsNullOrEmpty(resultJsonObj) ? "{}" : resultJsonObj;
            string safeErr = EscapeJs(errorMsg ?? "");
            string script = string.Format(
                "if(window.onHostCommandResult) window.onHostCommandResult('{0}', {1}, {2}, '{3}');",
                EscapeJs(reqId),
                success ? "true" : "false",
                safeResult,
                safeErr
            );
            ExecuteScriptSafe(script);
        }

        private void UpdateStageUI(int stageIndex, int stagePct, string stageStatus, string bytes, string speed, string log)
        {
            string bArg = bytes != null ? ("'" + EscapeJs(bytes) + "'") : "null";
            string sArg = speed != null ? ("'" + EscapeJs(speed) + "'") : "null";
            string lArg = log != null ? ("'" + EscapeJs(log) + "'") : "null";

            string script = string.Format(
                "if(window.updateStageProgress) window.updateStageProgress({0}, {1}, '{2}', {3}, {4}, {5});",
                stageIndex, stagePct, EscapeJs(stageStatus ?? ""), bArg, sArg, lArg
            );
            ExecuteScriptSafe(script);
        }

        private void ShowErrorUI(string errTitle, string errLog, int failedStageIndex)
        {
            string script = string.Format(
                "if(window.showInstallError) window.showInstallError('{0}', '{1}', {2});",
                EscapeJs(errTitle ?? "설치 오류"), EscapeJs(errLog ?? ""), failedStageIndex
            );
            ExecuteScriptSafe(script);
        }

        private void ExecuteScriptSafe(string script)
        {
            if (this.IsDisposed) return;
            if (this.InvokeRequired)
            {
                this.BeginInvoke(new Action(() => ExecuteScriptSafe(script)));
                return;
            }
            try
            {
                if (_webView != null && _webView.CoreWebView2 != null && IsTrustedOrigin(_webView.CoreWebView2.Source))
                {
                    _webView.CoreWebView2.ExecuteScriptAsync(script);
                }
            }
            catch { }
        }

        private string EscapeJs(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("\\", "\\\\").Replace("'", "\\'").Replace("\r", "").Replace("\n", " ");
        }

        // =========================================================================
        // 웹(boardest-windows-installer.web.app)에서 호출하는 단계별 시스템 명령 핸들러
        // =========================================================================

        private void HandleKillProcessesCmd(string reqId)
        {
            _isInstalling = true;
            KillRunningProcesses();
            ResolveHostCommand(reqId, true, "{\"killed\":true}", null);
        }

        private async Task HandleInstallCertificateCmd(string reqId, string json)
        {
            _isInstalling = true;
            try
            {
                string tempRoot = Path.Combine(Path.GetTempPath(), "Boardest_OnlineInstall");
                if (!Directory.Exists(tempRoot)) Directory.CreateDirectory(tempRoot);

                bool certOk = await InstallRootCertificateStageAsync(tempRoot);
                if (!certOk)
                {
                    _isInstalling = false;
                    ResolveHostCommand(reqId, false, null, "보안 루트 인증서(BoardestCert.cer) 설치에 실패했습니다.");
                    return;
                }
                ResolveHostCommand(reqId, true, "{\"certInstalled\":true}", null);
            }
            catch (Exception ex)
            {
                _isInstalling = false;
                ResolveHostCommand(reqId, false, null, ex.Message);
            }
        }

        private async Task HandleDownloadPackageCmd(string reqId, string json)
        {
            _isInstalling = true;
            try
            {
                string prodType = ExtractJsonString(json, "productType");
                if (!string.IsNullOrEmpty(prodType)) SetSelectedProduct(prodType);

                string directUrl = ExtractJsonString(json, "directUrl");
                string assetRegex = ExtractJsonString(json, "assetRegex");
                string fileType = ExtractJsonString(json, "fileType");
                string tempRoot = Path.Combine(Path.GetTempPath(), "Boardest_OnlineInstall_" + Guid.NewGuid().ToString("N").Substring(0, 8));
                Directory.CreateDirectory(tempRoot);

                string downloadUrl = !string.IsNullOrEmpty(directUrl)
                    ? directUrl
                    : await ResolveDownloadUrlAsync(assetRegex);
                string ext = !string.IsNullOrEmpty(fileType)
                    ? fileType
                    : ((_productType == "Teacher") ? ".zip" : ".msix");
                string packageFile = Path.Combine(tempRoot, "package_" + _productType.ToLowerInvariant() + ext);

                await DownloadFileWithStageProgressAsync(downloadUrl, packageFile);

                FileInfo fi = new FileInfo(packageFile);
                if (!fi.Exists || fi.Length < 1024 * 100)
                {
                    throw new Exception("다운로드된 패키지 파일이 손상되었거나 크기가 너무 작습니다.");
                }

                string escapedPath = packageFile.Replace("\\", "\\\\");
                ResolveHostCommand(reqId, true, string.Format("{{\"downloadedPath\":\"{0}\"}}", escapedPath), null);
            }
            catch (Exception ex)
            {
                _isInstalling = false;
                ResolveHostCommand(reqId, false, null, ex.Message);
            }
        }

        private void HandleExtractAndCopyAppCmd(string reqId, string json)
        {
            _isInstalling = true;
            try
            {
                string zipPath = ExtractJsonString(json, "zipPath");
                string customTargetDir = ExtractJsonString(json, "targetDir");
                if (!string.IsNullOrEmpty(customTargetDir))
                {
                    _teacherInstallDir = Environment.ExpandEnvironmentVariables(customTargetDir);
                }
                string customVer = ExtractJsonString(json, "productVersion");
                if (!string.IsNullOrEmpty(customVer))
                {
                    _productVersion = customVer;
                }
                bool createDesktop = !json.Contains("\"createDesktop\":false");
                bool createStartMenu = !json.Contains("\"createStartMenu\":false");
                string installScope = json.Contains("\"installScope\":\"standalone\"") ? "standalone" : "full";

                string tempRoot = Path.GetDirectoryName(zipPath);
                InstallTeacherZipStage(zipPath, tempRoot, createDesktop, createStartMenu, installScope);

                _isInstalling = false;
                string escapedDir = _teacherInstallDir.Replace("\\", "\\\\");
                ResolveHostCommand(reqId, true, string.Format("{{\"installedDir\":\"{0}\"}}", escapedDir), null);
            }
            catch (Exception ex)
            {
                _isInstalling = false;
                ResolveHostCommand(reqId, false, null, ex.Message);
            }
        }

        private void HandleInstallMsixPackageCmd(string reqId, string json)
        {
            _isInstalling = true;
            try
            {
                string msixPath = ExtractJsonString(json, "msixPath");
                string prodType = ExtractJsonString(json, "productType");
                if (!string.IsNullOrEmpty(prodType)) SetSelectedProduct(prodType);

                InstallMsixPackageStage(msixPath);

                try
                {
                    string dir = Path.GetDirectoryName(msixPath);
                    if (!string.IsNullOrEmpty(dir) && Directory.Exists(dir))
                    {
                        Directory.Delete(dir, true);
                    }
                }
                catch { }

                _isInstalling = false;
                ResolveHostCommand(reqId, true, "{\"msixInstalled\":true}", null);
            }
            catch (Exception ex)
            {
                _isInstalling = false;
                ResolveHostCommand(reqId, false, null, ex.Message);
            }
        }

        private void HandleRunPowerShellCmd(string reqId, string json)
        {
            try
            {
                string command = ExtractJsonString(json, "command");
                if (string.IsNullOrEmpty(command))
                {
                    ResolveHostCommand(reqId, false, null, "실행할 PowerShell 명령이 비어 있습니다.");
                    return;
                }

                ProcessStartInfo psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \"" + command.Replace("\"", "\\\"") + "\"",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };
                using (Process p = Process.Start(psi))
                {
                    string stdOut = p.StandardOutput.ReadToEnd();
                    string stdErr = p.StandardError.ReadToEnd();
                    p.WaitForExit();
                    if (p.ExitCode != 0)
                    {
                        ResolveHostCommand(reqId, false, null, string.IsNullOrEmpty(stdErr) ? stdOut : stdErr);
                        return;
                    }
                    ResolveHostCommand(reqId, true, "{\"exitCode\":0}", null);
                }
            }
            catch (Exception ex)
            {
                ResolveHostCommand(reqId, false, null, ex.Message);
            }
        }

        // =========================================================================
        // 3단계 설치 엔진 코어 구현
        // =========================================================================
        private async Task RunInstallProcessAsync(bool createDesktop, bool createStartMenu, string installScope)
        {
            _isInstalling = true;
            int currentStage = 1;
            string tempRoot = Path.Combine(Path.GetTempPath(), "Boardest_OnlineInstall_" + Guid.NewGuid().ToString("N").Substring(0, 8));

            try
            {
                Directory.CreateDirectory(tempRoot);
                KillRunningProcesses();

                if (_productType != "Teacher")
                {
                    currentStage = 1;
                    bool certOk = await InstallRootCertificateStageAsync(tempRoot);
                    if (!certOk)
                    {
                        throw new Exception("보안 인증서 설치가 완료되지 않았습니다.");
                    }
                }

                currentStage = 2;
                UpdateStageUI(2, 0, "최신 릴리즈 패키지 정보 확인 중...", "0.0 MB / 0.0 MB", "0.00 MB/s", "[2단계] GitHub 최신 릴리즈 패키지 URL 조회 중...");
                string downloadUrl = await ResolveDownloadUrlAsync(null);
                string ext = (_productType == "Teacher") ? ".zip" : ".msix";
                string packageFile = Path.Combine(tempRoot, "package" + ext);

                await DownloadFileWithStageProgressAsync(downloadUrl, packageFile);
                UpdateStageUI(2, 100, "패키지 다운로드 완료 (100%)", null, null, "[2단계 완료] 최신 패키지 다운로드가 완료되었습니다.");

                currentStage = 3;
                if (_productType == "Teacher")
                {
                    InstallTeacherZipStage(packageFile, tempRoot, createDesktop, createStartMenu, installScope);
                }
                else
                {
                    InstallMsixPackageStage(packageFile);
                }

                try { Directory.Delete(tempRoot, true); } catch { }
                _isInstalling = false;
            }
            catch (Exception ex)
            {
                _isInstalling = false;
                try { Directory.Delete(tempRoot, true); } catch { }
                ShowErrorUI("설치 오류: " + ex.Message, ex.Message, currentStage);
            }
        }

        private async Task<bool> InstallRootCertificateStageAsync(string tempDir)
        {
            UpdateStageUI(1, 10, "기존 보안 인증서 설치 여부 확인 중...", null, null, "[1단계] LocalMachine\\Root 인증서 확인 중...");

            if (IsCertAlreadyInstalled("006d6eb59ce360dbd15bf1367ea107b34033c7a3"))
            {
                UpdateStageUI(1, 100, "보안 인증서가 이미 설치되어 있습니다 (100%)", null, null, "[1단계 완료] 루트 인증서가 이미 등록되어 있습니다.");
                return true;
            }

            string certPath = Path.Combine(tempDir, "BoardestCert.cer");
            UpdateStageUI(1, 30, "보안 서명 인증서(BoardestCert.cer) 준비 중...", null, null, "[1단계] 보안 인증서 추출 중...");

            bool extracted = ExtractResourceToFile("BoardestCert.cer", certPath);
            if (!extracted || !File.Exists(certPath))
            {
                UpdateStageUI(1, 45, "온라인에서 보안 인증서 다운로드 중...", null, null, "[1단계] 서버에서 BoardestCert.cer 다운로드 중...");
                string[] certUrls = new string[]
                {
                    "https://bst-installer.web.app/BoardestCert.cer",
                    "https://github.com/hiJiwho/Boardest/releases/latest/download/BoardestCert.cer"
                };

                foreach (string cUrl in certUrls)
                {
                    try
                    {
                        using (var wc = new WebClient())
                        {
                            await wc.DownloadFileTaskAsync(new Uri(cUrl), certPath);
                        }
                        if (File.Exists(certPath) && new FileInfo(certPath).Length > 100) break;
                    }
                    catch { }
                }
            }

            if (!File.Exists(certPath))
            {
                return false;
            }

            UpdateStageUI(1, 70, "Windows 신뢰할 수 있는 루트 인증 기관에 등록 중...", null, null, "[1단계] 관리자 권한으로 루트 인증서(LocalMachine\\Root) 설치 중...");

            try
            {
                ProcessStartInfo psi = new ProcessStartInfo
                {
                    FileName = "certutil.exe",
                    Arguments = string.Format("-addstore -f \"Root\" \"{0}\"", certPath),
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                using (Process p = Process.Start(psi))
                {
                    p.WaitForExit(15000);
                    if (p.ExitCode == 0)
                    {
                        UpdateStageUI(1, 100, "보안 인증서 설치 완료 (100%)", null, null, "[1단계 완료] 신뢰할 수 있는 루트 인증 기관 등록 성공!");
                        return true;
                    }
                }
            }
            catch { }

            return IsCertAlreadyInstalled("006d6eb59ce360dbd15bf1367ea107b34033c7a3");
        }

        private bool IsCertAlreadyInstalled(string thumbprint)
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo
                {
                    FileName = "powershell.exe",
                    Arguments = string.Format("-NoProfile -NonInteractive -Command \"if (Get-ChildItem -Path Cert:\\LocalMachine\\Root | Where-Object {{ $_.Thumbprint -eq '{0}' }}) {{ exit 0 }} else {{ exit 1 }}\"", thumbprint),
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                using (Process p = Process.Start(psi))
                {
                    p.WaitForExit(8000);
                    return p.ExitCode == 0;
                }
            }
            catch
            {
                return false;
            }
        }

        private async Task<string> ResolveDownloadUrlAsync(string customRegex)
        {
            string pattern = customRegex;
            if (string.IsNullOrEmpty(pattern))
            {
                if (_productType == "Class")
                {
                    pattern = @"https://github\.com/[^""\s]+/releases/download/[^""\s]+/(?:boardest|bst-class)\.(?:msix|appx)";
                }
                else if (_productType == "Cloud")
                {
                    pattern = @"https://github\.com/[^""\s]+/releases/download/[^""\s]+/(?:boardest-cloud|bcld)\.(?:msix|appx)";
                }
                else
                {
                    pattern = @"https://github\.com/[^""\s]+/releases/download/[^""\s]+/(?:bst-teacher-windows|boardest-teacher-windows|boardest-teacher)\.zip";
                }
            }

            try
            {
                HttpWebRequest req = (HttpWebRequest)WebRequest.Create("https://api.github.com/repos/hiJiwho/Boardest/releases/latest");
                req.UserAgent = "Boardest-Unified-Online-Installer";
                req.Timeout = 10000;
                using (WebResponse resp = await req.GetResponseAsync())
                using (StreamReader reader = new StreamReader(resp.GetResponseStream()))
                {
                    string json = await reader.ReadToEndAsync();
                    Match m = Regex.Match(json, pattern, RegexOptions.IgnoreCase);
                    if (m.Success) return m.Value;
                }
            }
            catch { }

            if (_productType == "Class")
                return "https://github.com/hiJiwho/Boardest/releases/latest/download/boardest.msix";
            if (_productType == "Cloud")
                return "https://github.com/hiJiwho/Boardest/releases/latest/download/boardest-cloud.msix";
            return "https://github.com/hiJiwho/Boardest/releases/latest/download/bst-teacher-windows.zip";
        }

        private async Task DownloadFileWithStageProgressAsync(string primaryUrl, string destinationPath)
        {
            string[] candidateUrls;
            if (_productType == "Class")
            {
                candidateUrls = new string[]
                {
                    primaryUrl,
                    "https://github.com/hiJiwho/Boardest/releases/latest/download/boardest.msix",
                    "https://github.com/hiJiwho/Boardest/releases/latest/download/boardest.appx",
                    "https://github.com/hiJiwho/Boardest/releases/latest/download/bst-class.appx"
                };
            }
            else if (_productType == "Cloud")
            {
                candidateUrls = new string[]
                {
                    primaryUrl,
                    "https://github.com/hiJiwho/Boardest/releases/latest/download/boardest-cloud.msix",
                    "https://github.com/hiJiwho/Boardest/releases/latest/download/boardest-cloud.appx",
                    "https://github.com/hiJiwho/Boardest/releases/latest/download/bcld.appx"
                };
            }
            else
            {
                candidateUrls = new string[]
                {
                    primaryUrl,
                    "https://github.com/hiJiwho/Boardest/releases/latest/download/bst-teacher-windows.zip",
                    "https://github.com/hiJiwho/Boardest/releases/latest/download/boardest-teacher-windows.zip",
                    "https://github.com/hiJiwho/Boardest/releases/latest/download/boardest-teacher.zip"
                };
            }

            Exception lastEx = null;
            foreach (string url in candidateUrls)
            {
                if (string.IsNullOrEmpty(url)) continue;
                try
                {
                    await DownloadSingleUrlWithStageProgressAsync(url, destinationPath);
                    FileInfo fi = new FileInfo(destinationPath);
                    if (fi.Exists && fi.Length > 1024 * 100) return;
                }
                catch (Exception ex)
                {
                    lastEx = ex;
                }
            }

            throw new Exception("패키지 다운로드에 실패했습니다: " + (lastEx != null ? lastEx.Message : "네트워크 확인 필요"));
        }

        private async Task DownloadSingleUrlWithStageProgressAsync(string url, string destinationPath)
        {
            HttpWebRequest req = (HttpWebRequest)WebRequest.Create(url);
            req.UserAgent = "Boardest-Unified-Online-Installer";
            req.AllowAutoRedirect = true;
            req.Timeout = 20000;

            using (WebResponse resp = await req.GetResponseAsync())
            {
                long totalBytes = resp.ContentLength;
                if (totalBytes <= 0) totalBytes = 65 * 1024 * 1024;

                using (Stream input = resp.GetResponseStream())
                using (FileStream output = new FileStream(destinationPath, FileMode.Create, FileAccess.Write, FileShare.None))
                {
                    byte[] buffer = new byte[65536];
                    long totalRead = 0;
                    int bytesRead;
                    Stopwatch sw = Stopwatch.StartNew();
                    long lastUiTick = 0;

                    while ((bytesRead = await input.ReadAsync(buffer, 0, buffer.Length)) > 0)
                    {
                        await output.WriteAsync(buffer, 0, bytesRead);
                        totalRead += bytesRead;

                        if (sw.ElapsedMilliseconds - lastUiTick >= 100 || totalRead == totalBytes)
                        {
                            lastUiTick = sw.ElapsedMilliseconds;
                            double ratio = (double)totalRead / totalBytes;
                            if (ratio > 1.0) ratio = 1.0;

                            int stagePct = (int)(ratio * 100);
                            double mbRead = totalRead / (1024.0 * 1024.0);
                            double mbTotal = totalBytes / (1024.0 * 1024.0);
                            double elapsedSec = Math.Max(0.1, sw.Elapsed.TotalSeconds);
                            double speedMbs = mbRead / elapsedSec;

                            string bytesStr = string.Format("{0:F1} MB / {1:F1} MB", mbRead, mbTotal);
                            string speedStr = string.Format("{0:F2} MB/s", speedMbs);

                            UpdateStageUI(2, stagePct, string.Format("패키지 다운로드 중... ({0}%)", stagePct), bytesStr, speedStr, null);
                        }
                    }
                }
            }
        }

        private void InstallTeacherZipStage(string zipFilePath, string tempRoot, bool createDesktop, bool createStartMenu, string installScope)
        {
            UpdateStageUI(3, 5, "다운로드된 패키지 압축 해제 중...", null, null, "[3단계] ZIP 아카이브 압축을 해제하고 있습니다...");

            string extractDir = Path.Combine(tempRoot, "extracted");
            if (Directory.Exists(extractDir)) Directory.Delete(extractDir, true);
            ZipFile.ExtractToDirectory(zipFilePath, extractDir);

            string sourceRoot = FindDirectoryContainingExe(extractDir, "boardest_teacher.exe");
            if (string.IsNullOrEmpty(sourceRoot))
            {
                throw new Exception("압축 파일 내부에서 boardest_teacher.exe를 찾을 수 없습니다.");
            }

            UpdateStageUI(3, 20, "설치 폴더 준비 및 기존 파일 정리 중...", null, null, "[3단계] 대상 경로 준비: " + _teacherInstallDir);
            if (!Directory.Exists(_teacherInstallDir))
            {
                Directory.CreateDirectory(_teacherInstallDir);
            }

            string[] allFiles = Directory.GetFiles(sourceRoot, "*", SearchOption.AllDirectories);
            int totalFiles = Math.Max(1, allFiles.Length);
            int copiedCount = 0;

            foreach (string srcFile in allFiles)
            {
                string relPath = srcFile.Substring(sourceRoot.Length).TrimStart('\\', '/');
                if (installScope == "standalone" && relPath.IndexOf("overlay_panser", StringComparison.OrdinalIgnoreCase) >= 0)
                {
                    copiedCount++;
                    continue;
                }

                string destFile = Path.Combine(_teacherInstallDir, relPath);
                string destFolder = Path.GetDirectoryName(destFile);
                if (!Directory.Exists(destFolder))
                {
                    Directory.CreateDirectory(destFolder);
                }

                CopyFileWithRetry(srcFile, destFile);
                copiedCount++;

                if (copiedCount % 4 == 0 || copiedCount == totalFiles)
                {
                    int copyPct = 20 + (int)(((double)copiedCount / totalFiles) * 65);
                    UpdateStageUI(3, copyPct, string.Format("앱 파일 복사 중... ({0}/{1})", copiedCount, totalFiles), null, null, null);
                }
            }

            UpdateStageUI(3, 88, "언인스톨러 및 바로가기 생성 중...", null, null, "[3단계] 제거 프로그램(uninstall.exe) 및 바로가기를 등록합니다...");
            string uninstallerPath = Path.Combine(_teacherInstallDir, "uninstall.exe");
            ExtractResourceToFile("uninstall.exe", uninstallerPath);

            string mainExePath = Path.Combine(_teacherInstallDir, "boardest_teacher.exe");
            if (createDesktop)
            {
                string desktopDir = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                CreateShortcut(Path.Combine(desktopDir, "Boardest Teacher.lnk"), mainExePath, _teacherInstallDir, "Boardest Teacher - 스마트 수업 관리 솔루션");
            }

            if (createStartMenu)
            {
                string startMenuDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Boardest");
                if (!Directory.Exists(startMenuDir)) Directory.CreateDirectory(startMenuDir);
                CreateShortcut(Path.Combine(startMenuDir, "Boardest Teacher.lnk"), mainExePath, _teacherInstallDir, "Boardest Teacher");
                if (File.Exists(uninstallerPath))
                {
                    CreateShortcut(Path.Combine(startMenuDir, "Boardest Teacher 제거.lnk"), uninstallerPath, _teacherInstallDir, "Boardest Teacher 제거");
                }
            }

            RegisterUninstallRegistry(mainExePath, uninstallerPath);
            UpdateStageUI(3, 100, "앱 복사 및 설치 완료! (100%)", null, null, "[3단계 완료] Boardest Teacher 설치가 모두 완료되었습니다!");
        }

        private void InstallMsixPackageStage(string msixPath)
        {
            UpdateStageUI(3, 15, "기존 충돌 패키지 정리 중...", null, null, "[3단계] 구버전 패키지 충돌 여부를 확인합니다...");

            if (_productType == "Class")
            {
                try
                {
                    ProcessStartInfo cleanPsi = new ProcessStartInfo
                    {
                        FileName = "powershell.exe",
                        Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \"Get-AppxPackage *overlaypanser* | Remove-AppxPackage -ErrorAction SilentlyContinue\"",
                        UseShellExecute = false,
                        CreateNoWindow = true
                    };
                    using (Process cp = Process.Start(cleanPsi))
                    {
                        cp.WaitForExit(10000);
                    }
                }
                catch { }
            }

            UpdateStageUI(3, 45, _productName + " MSIX 패키지 시스템 설치 중...", null, null, "[3단계] Windows Add-AppxPackage 명령으로 앱을 설치하고 있습니다...");

            string psCmd = string.Format(
                "Add-AppxPackage -Path '{0}' -ForceApplicationShutdown -ErrorAction Stop",
                msixPath.Replace("'", "''")
            );

            ProcessStartInfo psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \"" + psCmd + "\"",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true
            };

            using (Process p = Process.Start(psi))
            {
                int animPct = 45;
                while (!p.WaitForExit(400))
                {
                    if (animPct < 92) animPct += 4;
                    UpdateStageUI(3, animPct, _productName + " 시스템 설치 진행 중...", null, null, null);
                }

                string stdErr = p.StandardError.ReadToEnd();
                string stdOut = p.StandardOutput.ReadToEnd();

                if (p.ExitCode != 0)
                {
                    string errDetail = !string.IsNullOrEmpty(stdErr) ? stdErr.Trim() : stdOut.Trim();
                    throw new Exception("MSIX 패키지 설치 실패 (코드 " + p.ExitCode + "): " + errDetail);
                }
            }

            UpdateStageUI(3, 100, _productName + " 설치 완료! (100%)", null, null, "[3단계 완료] " + _productName + " 설치가 성공적으로 완료되었습니다!");
        }

        private string FindDirectoryContainingExe(string rootDir, string exeName)
        {
            if (File.Exists(Path.Combine(rootDir, exeName))) return rootDir;
            foreach (string subDir in Directory.GetDirectories(rootDir, "*", SearchOption.AllDirectories))
            {
                if (File.Exists(Path.Combine(subDir, exeName))) return subDir;
            }
            return null;
        }

        private void KillRunningProcesses()
        {
            string[] targets = new string[] { "boardest", "boardest_teacher", "boardest_cloud", "overlay_panser" };
            foreach (string procName in targets)
            {
                try
                {
                    foreach (Process p in Process.GetProcessesByName(procName))
                    {
                        try { p.Kill(); p.WaitForExit(2000); } catch { }
                    }
                }
                catch { }
            }
        }

        private void CopyFileWithRetry(string src, string dest)
        {
            for (int i = 0; i < 4; i++)
            {
                try
                {
                    File.Copy(src, dest, true);
                    return;
                }
                catch
                {
                    Thread.Sleep(250);
                }
            }
            File.Copy(src, dest, true);
        }

        private bool ExtractResourceToFile(string resourceName, string outPath)
        {
            try
            {
                var asm = Assembly.GetExecutingAssembly();
                using (Stream s = asm.GetManifestResourceStream(resourceName))
                {
                    if (s == null) return false;
                    using (FileStream fs = new FileStream(outPath, FileMode.Create, FileAccess.Write))
                    {
                        s.CopyTo(fs);
                    }
                    return true;
                }
            }
            catch
            {
                return false;
            }
        }

        private void CreateShortcut(string shortcutPath, string targetPath, string workingDir, string description)
        {
            try
            {
                Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                if (shellType == null) return;
                dynamic shell = Activator.CreateInstance(shellType);
                dynamic shortcut = shell.CreateShortcut(shortcutPath);
                shortcut.TargetPath = targetPath;
                shortcut.WorkingDirectory = workingDir;
                shortcut.Description = description;
                shortcut.IconLocation = targetPath + ",0";
                shortcut.Save();
            }
            catch { }
        }

        private void RegisterUninstallRegistry(string mainExePath, string uninstallerPath)
        {
            try
            {
                string regPath = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\BoardestTeacher";
                using (RegistryKey key = Registry.CurrentUser.CreateSubKey(regPath))
                {
                    if (key != null)
                    {
                        key.SetValue("DisplayName", "Boardest Teacher");
                        key.SetValue("DisplayVersion", _productVersion);
                        key.SetValue("Publisher", "Boardest Team");
                        key.SetValue("DisplayIcon", mainExePath);
                        key.SetValue("InstallLocation", _teacherInstallDir);
                        key.SetValue("UninstallString", "\"" + uninstallerPath + "\"");
                        key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                        key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                    }
                }
            }
            catch { }
        }

        private void LaunchInstalledApp()
        {
            try
            {
                if (_productType == "Teacher")
                {
                    string exePath = Path.Combine(_teacherInstallDir, "boardest_teacher.exe");
                    if (File.Exists(exePath))
                    {
                        Process.Start(new ProcessStartInfo
                        {
                            FileName = exePath,
                            WorkingDirectory = _teacherInstallDir,
                            UseShellExecute = true
                        });
                    }
                }
                else
                {
                    string pkgFilter = (_productType == "Cloud") ? "*boardest*cloud*" : "*boardest*";
                    string psLaunch = string.Format(
                        "$pkg = Get-AppxPackage {0} | Select-Object -First 1; if ($pkg) {{ $manifest = Get-AppxPackageManifest $pkg; $appId = $manifest.Package.Applications.Application.Id; if ($appId -is [array]) {{ $appId = $appId[0] }}; Start-Process ('shell:AppsFolder\\' + $pkg.PackageFamilyName + '!' + $appId) }}",
                        pkgFilter
                    );
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = "powershell.exe",
                        Arguments = "-NoProfile -WindowStyle Hidden -Command \"" + psLaunch + "\"",
                        UseShellExecute = false,
                        CreateNoWindow = true
                    });
                }
            }
            catch { }
        }
    }

    static class Program
    {
        private static bool IsRunningAsAdministrator()
        {
            try
            {
                WindowsIdentity identity = WindowsIdentity.GetCurrent();
                WindowsPrincipal principal = new WindowsPrincipal(identity);
                return principal.IsInRole(WindowsBuiltInRole.Administrator);
            }
            catch
            {
                return false;
            }
        }

        [STAThread]
        static void Main(string[] args)
        {
            // [필수] 실행 시 관리자 권한 확인 및 강제 권한 상승(UAC runas)
            if (!IsRunningAsAdministrator())
            {
                try
                {
                    StringBuilder argBuilder = new StringBuilder();
                    if (args != null)
                    {
                        for (int i = 0; i < args.Length; i++)
                        {
                            if (i > 0) argBuilder.Append(" ");
                            argBuilder.Append("\"").Append(args[i]).Append("\"");
                        }
                    }

                    ProcessStartInfo elevatePsi = new ProcessStartInfo
                    {
                        FileName = Application.ExecutablePath,
                        Arguments = argBuilder.ToString(),
                        UseShellExecute = true,
                        Verb = "runas"
                    };
                    Process.Start(elevatePsi);
                }
                catch
                {
                    MessageBox.Show(
                        "Boardest 온라인 설치 관리자는 안전한 인증서 등록 및 앱 설치를 위해 반드시 [관리자 권한]으로 실행되어야 합니다.",
                        "관리자 권한 필요",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Warning
                    );
                }
                return;
            }

            bool isNew;
            using (var mutex = new Mutex(true, "Boardest_Unified_Online_Installer_Mutex", out isNew))
            {
                if (!isNew)
                {
                    MessageBox.Show("이미 Boardest 온라인 설치 관리자가 실행 중입니다.", "Boardest 설치 안내", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return;
                }

                // 내장된 WebView2 DLL 자동 추출 로드
                AppDomain.CurrentDomain.AssemblyResolve += (sender, resolveArgs) =>
                {
                    string dllName = new AssemblyName(resolveArgs.Name).Name + ".dll";
                    string tempDllDir = Path.Combine(Path.GetTempPath(), "BoardestInstaller_Libs");
                    Directory.CreateDirectory(tempDllDir);
                    string dllPath = Path.Combine(tempDllDir, dllName);

                    var asm = Assembly.GetExecutingAssembly();
                    using (var stream = asm.GetManifestResourceStream(dllName))
                    {
                        if (stream != null)
                        {
                            try
                            {
                                if (!File.Exists(dllPath))
                                {
                                    using (var fs = new FileStream(dllPath, FileMode.Create, FileAccess.Write))
                                    {
                                        stream.CopyTo(fs);
                                    }
                                }
                                return Assembly.LoadFrom(dllPath);
                            }
                            catch { }
                        }
                    }
                    return null;
                };

                ExtractNativeLoader();

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new InstallerForm());
            }
        }

        private static void ExtractNativeLoader()
        {
            try
            {
                string tempDllDir = Path.Combine(Path.GetTempPath(), "BoardestInstaller_Libs");
                Directory.CreateDirectory(tempDllDir);
                string loaderPath = Path.Combine(tempDllDir, "WebView2Loader.dll");
                var asm = Assembly.GetExecutingAssembly();
                using (var stream = asm.GetManifestResourceStream("WebView2Loader.dll"))
                {
                    if (stream != null && !File.Exists(loaderPath))
                    {
                        using (var fs = new FileStream(loaderPath, FileMode.Create, FileAccess.Write))
                        {
                            stream.CopyTo(fs);
                        }
                    }
                }
                SetDllDirectory(tempDllDir);
            }
            catch { }
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        private static extern bool SetDllDirectory(string lpPathName);
    }
}
