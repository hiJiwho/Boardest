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
[assembly: AssemblyDescription("Boardest 통합 온라인 설치 및 관리 도구 (Class / Teacher / Cloud)")]
[assembly: AssemblyCompany("Boardest Team")]
[assembly: AssemblyProduct("Boardest Online Installer")]
[assembly: AssemblyCopyright("Copyright © 2026 Boardest. All rights reserved.")]
[assembly: AssemblyVersion("5.5.0.0")]
[assembly: AssemblyFileVersion("5.5.0.0")]

namespace BoardestInstaller
{
    public class InstallerForm : Form
    {
        // =========================================================================
        // [보안 정책] 오직 https://boardest-windows-installer.web.app 만 명령 실행 허용!
        // =========================================================================
        private const string TrustedHost = "boardest-windows-installer.web.app";
        private const string TrustedInstallerUrl = "https://boardest-windows-installer.web.app/";
        private const string CustomUserAgentTag = "boardest-win-install";

        // Win32 API: 창틀 닫기(X) 버튼 비활성화 (설치 중 최소화만 가능하도록 강제)
        [DllImport("user32.dll")]
        private static extern IntPtr GetSystemMenu(IntPtr hWnd, bool bRevert);

        [DllImport("user32.dll")]
        private static extern bool EnableMenuItem(IntPtr hMenu, uint uIDEnableItem, uint uEnable);

        [DllImport("shell32.dll")]
        private static extern void SHChangeNotify(int wEventId, int uFlags, IntPtr dwItem1, IntPtr dwItem2);

        private const uint SC_CLOSE = 0xF060;
        private const uint MF_BYCOMMAND = 0x00000000;
        private const uint MF_GRAYED = 0x00000001;
        private const uint MF_DISABLED = 0x00000002;

        private WebView2 _webView;
        private string _productType = "Teacher"; // "Class", "Teacher", "Cloud"
        private string _productName = "Boardest 통합 온라인 설치";
        private string _productVersion = "5.5.0";
        private string _teacherInstallDir;
        private string _exeFileName = "";
        private string _lastTargetUrl = "";
        private bool _needsProductSelection = false;
        private bool _isUninstall = false;
        private bool _isInstalling = false;
        private bool _allowClose = false;

        public InstallerForm()
        {
            ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;

            DetectProductAndMode();

            _teacherInstallDir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "Programs",
                "BoardestTeacher"
            );

            // 창틀(Title Bar) 표시 + 최소화만 가능 (최대화 비활성화, 닫기 버튼 비활성화)
            if (_isUninstall)
            {
                this.Text = "Boardest Teacher 온라인 삭제 마법사";
            }
            else
            {
                this.Text = _needsProductSelection
                    ? "Boardest 통합 온라인 설치 마법사"
                    : (_productName + " 온라인 설치 마법사");
            }

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
                await InitializeWebViewAsync();
            };
        }

        private void DetectProductAndMode()
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
                else if (arg == "--uninstall" || arg == "-uninstall" || arg == "/uninstall")
                {
                    _isUninstall = true;
                }
            }

            if (exeName.Contains("uninstall") || exeName.Contains("uninst"))
            {
                _isUninstall = true;
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
                _needsProductSelection = !_isUninstall;
            }
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            if (_isInstalling && e.CloseReason == CloseReason.UserClosing)
            {
                var res = MessageBox.Show(
                    "설치(또는 삭제) 작업이 아직 진행 중입니다.\r\n작업을 중단하고 창을 닫으시겠습니까?",
                    "작업 취소 확인",
                    MessageBoxButtons.YesNo,
                    MessageBoxIcon.Question
                );
                if (res != DialogResult.Yes)
                {
                    e.Cancel = true;
                    return;
                }
            }
            base.OnFormClosing(e);
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            if (_scheduleSelfDestructOnExit)
            {
                ScheduleSelfDestruct();
            }
            base.OnFormClosed(e);
        }

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

                // [요구사항 1] UserAgent에 boardest-win-install 추가
                try
                {
                    string defaultUa = _webView.CoreWebView2.Settings.UserAgent;
                    if (!string.IsNullOrEmpty(defaultUa) && !defaultUa.Contains(CustomUserAgentTag))
                    {
                        _webView.CoreWebView2.Settings.UserAgent = defaultUa + " " + CustomUserAgentTag;
                    }
                    else if (string.IsNullOrEmpty(defaultUa))
                    {
                        _webView.CoreWebView2.Settings.UserAgent = CustomUserAgentTag;
                    }
                }
                catch { }

                // [안전 로직 1] https://boardest-windows-installer.web.app 외의 모든 URL 이동 차단
                _webView.CoreWebView2.NavigationStarting += (s, args) =>
                {
                    if (args.Uri.StartsWith("about:blank") || args.Uri.StartsWith("data:")) return;
                    if (!IsTrustedOrigin(args.Uri))
                    {
                        args.Cancel = true;
                    }
                };

                // [요구사항 2] 오프라인 / 네트워크 연결 실패 시 Edge 기본 에러 창 대신 커스텀 오류창 표시
                _webView.CoreWebView2.NavigationCompleted += (s, args) =>
                {
                    if (!args.IsSuccess)
                    {
                        ShowOfflineErrorPage();
                    }
                };

                // [안전 로직 2] 새 창 팝업 열기 차단
                _webView.CoreWebView2.NewWindowRequested += (s, args) =>
                {
                    args.Handled = true;
                };

                // [안전 로직 3] 웹 메시지 수신 시 발신 URL 검증
                _webView.CoreWebView2.WebMessageReceived += OnWebMessageReceived;

                NavigateToOnlineSite();
            }
            catch (Exception ex)
            {
                ShowOfflineErrorPage("WebView2 초기화 실패: " + ex.Message);
            }
        }

        private void NavigateToOnlineSite()
        {
            string modeParam = _isUninstall ? "uninstall" : "install";
            string prodQuery = _needsProductSelection ? "Select" : _productType;
            _lastTargetUrl = string.Format(
                "{0}?mode={1}&exe={2}&product={3}&ver={4}&t={5}",
                TrustedInstallerUrl,
                modeParam,
                Uri.EscapeDataString(_exeFileName ?? ""),
                Uri.EscapeDataString(prodQuery),
                Uri.EscapeDataString(_productVersion),
                DateTime.UtcNow.Ticks
            );

            _webView.CoreWebView2.Navigate(_lastTargetUrl);
        }

        private void ShowOfflineErrorPage(string customMessage = null)
        {
            if (this.IsDisposed || _webView == null || _webView.CoreWebView2 == null) return;
            string desc = customMessage ?? "인터넷 네트워크에 연결할 수 없습니다. Wi-Fi 또는 이더넷 연결 상태를 확인한 후 아래 [다시 시도] 버튼을 눌러주세요.";
            string html = GetOfflineHtml(desc);
            _webView.CoreWebView2.NavigateToString(html);
        }

        private string GetOfflineHtml(string errorDescription)
        {
            return @"<!DOCTYPE html>
<html lang=""ko"">
<head>
  <meta charset=""UTF-8"">
  <title>네트워크 연결 필요 - Boardest</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; user-select: none; font-family: -apple-system, BlinkMacSystemFont, 'Pretendard', 'Segoe UI', Roboto, sans-serif; }
    body { background: #0B0C10; color: #FFFFFE; width: 100vw; height: 100vh; display: flex; align-items: center; justify-content: center; }
    .card { background: #16161A; border: 1.5px solid rgba(239, 69, 101, 0.4); border-radius: 16px; padding: 32px 28px; width: 520px; max-width: 90vw; text-align: center; box-shadow: 0 10px 40px rgba(0, 0, 0, 0.6); }
    .icon { font-size: 46px; margin-bottom: 14px; }
    h2 { font-size: 19px; font-weight: 800; color: #fff; margin-bottom: 10px; }
    p { font-size: 12.5px; color: rgba(255, 255, 255, 0.7); line-height: 1.55; margin-bottom: 24px; }
    .btn-row { display: flex; justify-content: center; gap: 12px; }
    .btn { padding: 10px 22px; border-radius: 8px; font-size: 13px; font-weight: 700; border: none; cursor: pointer; transition: all 0.2s; }
    .btn-primary { background: linear-gradient(135deg, #00F5D4, #00c9ad); color: #000; box-shadow: 0 4px 14px rgba(0, 245, 212, 0.25); }
    .btn-primary:hover { transform: translateY(-1px); filter: brightness(1.08); }
    .btn-secondary { background: rgba(255, 255, 255, 0.08); color: #fff; border: 1px solid rgba(255, 255, 255, 0.15); }
    .btn-secondary:hover { background: rgba(255, 255, 255, 0.14); }
  </style>
</head>
<body>
  <div class=""card"">
    <div class=""icon"">📡</div>
    <h2>인터넷 연결이 필요합니다</h2>
    <p>" + WebUtility.HtmlEncode(errorDescription) + @"</p>
    <div class=""btn-row"">
      <button class=""btn btn-secondary"" onclick=""window.chrome.webview.postMessage(JSON.stringify({action:'close'}))"">닫기</button>
      <button class=""btn btn-primary"" onclick=""window.chrome.webview.postMessage(JSON.stringify({action:'retry'}))"">다시 시도 ↻</button>
    </div>
  </div>
</body>
</html>";
        }

        private void OnWebMessageReceived(object sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            try
            {
                // [보안 검증] 오직 https://boardest-windows-installer.web.app 또는 로컬 NavigateToString 메시지만 허용
                string senderUrl = e.Source;
                string currentWebViewUrl = (_webView != null && _webView.CoreWebView2 != null)
                    ? _webView.CoreWebView2.Source
                    : "";

                bool isSenderTrusted = IsTrustedOrigin(senderUrl) || senderUrl.StartsWith("about:blank") || senderUrl.StartsWith("data:");
                bool isViewTrusted = IsTrustedOrigin(currentWebViewUrl) || currentWebViewUrl.StartsWith("about:blank") || currentWebViewUrl.StartsWith("data:");

                if (!isSenderTrusted || !isViewTrusted)
                {
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
                else if (action == "retry")
                {
                    NavigateToOnlineSite();
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
                else if (action == "startUninstall" || action == "uninstallTeacher")
                {
                    Task.Run(() => HandleUninstallTeacherCmd(reqId, json));
                }
                else if (action == "startInstall")
                {
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
            string escapedDir = _teacherInstallDir.Replace("\\", "\\\\");
            string payload = string.Format(
                "{{\"productType\":\"{0}\",\"productName\":\"{1}\",\"productVersion\":\"{2}\",\"installDir\":\"{3}\",\"teacherInstallDir\":\"{3}\",\"isUninstall\":{4},\"needsProductSelection\":{5},\"isAdmin\":true}}",
                _productType,
                _productName,
                _productVersion,
                escapedDir,
                _isUninstall ? "true" : "false",
                _needsProductSelection ? "true" : "false"
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
                if (_webView != null && _webView.CoreWebView2 != null)
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
        // =========================================================================
        // [요구사항 3] 온라인 삭제(언인스톨) 핸들러 구현 (MSIX 수준의 완전 무결 삭제)
        // =========================================================================
        private bool _scheduleSelfDestructOnExit = false;

        private void HandleUninstallTeacherCmd(string reqId, string json)
        {
            _isInstalling = true;
            try
            {
                // purgeData가 명시적으로 false가 아닌 한 기본적으로 모든 캐시와 사용자 데이터를 MSIX처럼 완전 삭제
                bool purgeData = !json.Contains("\"purgeData\":false");

                // 1단계: 실행 중인 프로세스 강제 종료
                ExecuteScriptSafe("if(window.updateUninstallProgress) window.updateUninstallProgress(15, '실행 중인 관련 프로세스 강제 종료 중...', '[MSIX 완전삭제 1/5] boardest 관련 프로세스 종료...');");
                KillRunningProcesses();
                Thread.Sleep(500);

                // 2단계: 바탕화면, 시작메뉴, 작업표시줄, 시작프로그램 바로가기 완전 제거
                ExecuteScriptSafe("if(window.updateUninstallProgress) window.updateUninstallProgress(35, '바탕화면 및 시작 메뉴/작업표시줄 바로가기 완전 제거 중...', '[MSIX 완전삭제 2/5] 등록된 모든 바로가기(.lnk) 탐색 및 삭제...');");
                RemoveShortcutsMultiLocations();

                // 3단계: Windows 레지스트리 완전 청소 (Uninstall, Run, App 설정)
                ExecuteScriptSafe("if(window.updateUninstallProgress) window.updateUninstallProgress(55, 'Windows 프로그램 추가/제거 및 레지스트리 키 완전 삭제 중...', '[MSIX 완전삭제 3/5] HKCU / HKLM 레지스트리 키 정리...');");
                RemoveUninstallRegistry();

                // 4단계: 설치 디렉토리 완전 삭제 (읽기 전용 해제 후 강제 삭제)
                ExecuteScriptSafe("if(window.updateUninstallProgress) window.updateUninstallProgress(75, '프로그램 설치 파일 영구 삭제 중...', '[MSIX 완전삭제 4/5] 설치 디렉토리 파일 강제 삭제...');");
                string myExe = Application.ExecutablePath;
                bool isRunningInsideInstallDir = myExe.StartsWith(_teacherInstallDir, StringComparison.OrdinalIgnoreCase);

                if (Directory.Exists(_teacherInstallDir))
                {
                    // 현재 실행 중인 exe를 제외한 모든 파일 삭제
                    ForceDeleteDirectoryContentsExceptSelf(_teacherInstallDir, myExe);
                }

                // 타 설치 경로 점검 (Program Files 등)
                try
                {
                    string pf = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "BoardestTeacher");
                    if (Directory.Exists(pf)) ForceDeleteDirectoryRecursive(pf);
                    string pf86 = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "BoardestTeacher");
                    if (Directory.Exists(pf86)) ForceDeleteDirectoryRecursive(pf86);
                }
                catch { }

                // 5단계: 사용자 데이터 및 캐시/임시파일 완전 정리 (MSIX와 동일한 무결 청소)
                if (purgeData)
                {
                    ExecuteScriptSafe("if(window.updateUninstallProgress) window.updateUninstallProgress(90, '임시 데이터, 세션 캐시 및 설정 완전 정리 중...', '[MSIX 완전삭제 5/5] AppData 및 캐시 영구 정리...');");
                    PurgeAllUserDataAndCaches();
                }

                if (isRunningInsideInstallDir)
                {
                    // 언인스톨러 종료 시 자기 자신과 남은 빈 설치 폴더를 자폭(Self-Destruct) 삭제하도록 예약
                    _scheduleSelfDestructOnExit = true;
                }

                ExecuteScriptSafe("if(window.updateUninstallProgress) window.updateUninstallProgress(100, 'Boardest Teacher의 모든 구성요소가 MSIX 수준으로 완벽하게 삭제되었습니다!', '[완료] 프로그램, 설정, 캐시, 바로가기 및 레지스트리가 흔적도 없이 삭제되었습니다.');");
                _isInstalling = false;
                ResolveHostCommand(reqId, true, "{\"uninstalled\":true}", null);
            }
            catch (Exception ex)
            {
                _isInstalling = false;
                ResolveHostCommand(reqId, false, null, ex.Message);
            }
        }

        private void ForceDeleteDirectoryRecursive(string path)
        {
            if (string.IsNullOrEmpty(path) || !Directory.Exists(path)) return;
            try
            {
                foreach (string file in Directory.GetFiles(path, "*", SearchOption.AllDirectories))
                {
                    try
                    {
                        File.SetAttributes(file, FileAttributes.Normal);
                        File.Delete(file);
                    }
                    catch { }
                }
                var dirs = new List<string>(Directory.GetDirectories(path, "*", SearchOption.AllDirectories));
                dirs.Sort((a, b) => b.Length.CompareTo(a.Length));
                foreach (string dir in dirs)
                {
                    try { Directory.Delete(dir, true); } catch { }
                }
                Directory.Delete(path, true);
            }
            catch { }
        }

        private void ForceDeleteDirectoryContentsExceptSelf(string rootDir, string selfExePath)
        {
            if (string.IsNullOrEmpty(rootDir) || !Directory.Exists(rootDir)) return;
            try
            {
                foreach (string file in Directory.GetFiles(rootDir, "*", SearchOption.AllDirectories))
                {
                    if (string.Equals(file, selfExePath, StringComparison.OrdinalIgnoreCase)) continue;
                    try
                    {
                        File.SetAttributes(file, FileAttributes.Normal);
                        File.Delete(file);
                    }
                    catch { }
                }

                // 빈 하위 디렉토리 삭제
                var subDirs = new List<string>(Directory.GetDirectories(rootDir, "*", SearchOption.AllDirectories));
                subDirs.Sort((a, b) => b.Length.CompareTo(a.Length));
                foreach (string dir in subDirs)
                {
                    try
                    {
                        if (Directory.GetFiles(dir).Length == 0 && Directory.GetDirectories(dir).Length == 0)
                        {
                            Directory.Delete(dir, false);
                        }
                    }
                    catch { }
                }
            }
            catch { }
        }

        private void PurgeAllUserDataAndCaches()
        {
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
            string tempDir = Path.GetTempPath();

            string[] targetDirs = new string[]
            {
                Path.Combine(localAppData, "Boardest"),
                Path.Combine(localAppData, "BoardestTeacher"),
                Path.Combine(localAppData, "boardest_teacher"),
                Path.Combine(localAppData, "boardest"),
                Path.Combine(appData, "Boardest"),
                Path.Combine(appData, "BoardestTeacher"),
                Path.Combine(appData, "boardest_teacher"),
                Path.Combine(userProfile, ".boardest")
            };

            foreach (string dir in targetDirs)
            {
                ForceDeleteDirectoryRecursive(dir);
            }

            try
            {
                foreach (string d in Directory.GetDirectories(tempDir, "Boardest*", SearchOption.TopDirectoryOnly))
                {
                    ForceDeleteDirectoryRecursive(d);
                }
                foreach (string d in Directory.GetDirectories(tempDir, "boardest*", SearchOption.TopDirectoryOnly))
                {
                    ForceDeleteDirectoryRecursive(d);
                }
            }
            catch { }
        }

        private void RemoveShortcutsMultiLocations()
        {
            string[] shortcutPatterns = new string[] { "Boardest Teacher*.lnk", "Boardest Teacher 제거*.lnk", "Boardest*.lnk" };
            var desktopDirs = GetCandidateDesktopDirectories();

            foreach (string dir in desktopDirs)
            {
                if (!Directory.Exists(dir)) continue;
                foreach (string pattern in shortcutPatterns)
                {
                    try
                    {
                        foreach (string lnk in Directory.GetFiles(dir, pattern))
                        {
                            try { File.Delete(lnk); } catch { }
                        }
                    }
                    catch { }
                }
            }

            var startMenuDirs = new List<string>
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms), "Boardest"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Boardest"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms), "Boardest Teacher"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Boardest Teacher")
            };

            foreach (string sDir in startMenuDirs)
            {
                ForceDeleteDirectoryRecursive(sDir);
            }

            string[] startRoots = new string[]
            {
                Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms),
                Environment.GetFolderPath(Environment.SpecialFolder.Programs),
                Environment.GetFolderPath(Environment.SpecialFolder.CommonStartup),
                Environment.GetFolderPath(Environment.SpecialFolder.Startup)
            };

            foreach (string sRoot in startRoots)
            {
                if (!Directory.Exists(sRoot)) continue;
                foreach (string pattern in shortcutPatterns)
                {
                    try
                    {
                        foreach (string lnk in Directory.GetFiles(sRoot, pattern))
                        {
                            try { File.Delete(lnk); } catch { }
                        }
                    }
                    catch { }
                }
            }

            try
            {
                string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                string taskbarPinned = Path.Combine(appData, @"Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar");
                if (Directory.Exists(taskbarPinned))
                {
                    foreach (string pattern in shortcutPatterns)
                    {
                        foreach (string lnk in Directory.GetFiles(taskbarPinned, pattern))
                        {
                            try { File.Delete(lnk); } catch { }
                        }
                    }
                }
                string quickLaunch = Path.Combine(appData, @"Microsoft\Internet Explorer\Quick Launch");
                if (Directory.Exists(quickLaunch))
                {
                    foreach (string pattern in shortcutPatterns)
                    {
                        foreach (string lnk in Directory.GetFiles(quickLaunch, pattern))
                        {
                            try { File.Delete(lnk); } catch { }
                        }
                    }
                }
            }
            catch { }

            try
            {
                // SHCNE_ASSOCCHANGED (0x08000000), SHCNF_IDLIST (0x0000) -> 윈도우 시작 메뉴/앱 서랍 즉시 새로고침
                SHChangeNotify(0x08000000, 0x0000, IntPtr.Zero, IntPtr.Zero);
            }
            catch { }
        }

        private void RemoveUninstallRegistry()
        {
            try
            {
                Registry.CurrentUser.DeleteSubKeyTree(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\BoardestTeacher", false);
            }
            catch { }
            try
            {
                Registry.LocalMachine.DeleteSubKeyTree(@"Software\Microsoft\Windows\CurrentVersion\Uninstall\BoardestTeacher", false);
            }
            catch { }
            try
            {
                Registry.LocalMachine.DeleteSubKeyTree(@"Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\BoardestTeacher", false);
            }
            catch { }

            try
            {
                using (var runKey = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true))
                {
                    if (runKey != null) runKey.DeleteValue("BoardestTeacher", false);
                }
            }
            catch { }
            try
            {
                using (var runKey = Registry.LocalMachine.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true))
                {
                    if (runKey != null) runKey.DeleteValue("BoardestTeacher", false);
                }
            }
            catch { }

            try
            {
                Registry.CurrentUser.DeleteSubKeyTree(@"Software\BoardestTeacher", false);
                Registry.CurrentUser.DeleteSubKeyTree(@"Software\Boardest\Teacher", false);
            }
            catch { }
            try
            {
                Registry.LocalMachine.DeleteSubKeyTree(@"Software\BoardestTeacher", false);
                Registry.LocalMachine.DeleteSubKeyTree(@"Software\Boardest\Teacher", false);
            }
            catch { }
        }

        private void ScheduleSelfDestruct()
        {
            try
            {
                string exePath = Application.ExecutablePath;
                string installDir = _teacherInstallDir;

                string cmdArgs = string.Format(
                    "/c ping 127.0.0.1 -n 3 > nul & del /f /q \"{0}\" & (rmdir /s /q \"{1}\" 2>nul) & exit",
                    exePath,
                    installDir
                );

                ProcessStartInfo psi = new ProcessStartInfo
                {
                    FileName = "cmd.exe",
                    Arguments = cmdArgs,
                    CreateNoWindow = true,
                    WindowStyle = ProcessWindowStyle.Hidden,
                    UseShellExecute = false
                };
                Process.Start(psi);
            }
            catch { }
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

            UpdateStageUI(3, 88, "언인스톨러 복사 및 바로가기 등록 중...", null, null, "[3단계] 언인스톨러 및 바로가기 등록 중...");

            // [경량화] 무거운 중복 바이너리를 리소스에 넣지 않고, 현재 실행 파일 자체를 uninstall.exe로 복사
            string uninstallerPath = Path.Combine(_teacherInstallDir, "uninstall.exe");
            try
            {
                File.Copy(Application.ExecutablePath, uninstallerPath, true);
            }
            catch { }

            string mainExePath = Path.Combine(_teacherInstallDir, "boardest_teacher.exe");

            // [요구사항 4] 바로가기 생성 대폭 강화 (공용 바탕화면 + 사용자 바탕화면 + 시작메뉴 모두 생성)
            if (createDesktop)
            {
                CreateDesktopShortcutsMultiLocations("Boardest Teacher.lnk", mainExePath, _teacherInstallDir, "Boardest Teacher - 스마트 수업 관리 솔루션");
            }

            if (createStartMenu)
            {
                CreateStartMenuShortcutsMultiLocations("Boardest Teacher.lnk", mainExePath, _teacherInstallDir, "Boardest Teacher");
                if (File.Exists(uninstallerPath))
                {
                    CreateStartMenuShortcutsMultiLocations("Boardest Teacher 제거.lnk", uninstallerPath, _teacherInstallDir, "Boardest Teacher 제거", "--uninstall");
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
            string[] targets = new string[] { 
                "boardest", 
                "boardest_teacher", 
                "boardest_cloud", 
                "overlay_panser",
                "BoardestTeacher",
                "boardest-teacher",
                "teacher-daemon",
                "ffmpeg"
            };

            foreach (string procName in targets)
            {
                try
                {
                    foreach (Process p in Process.GetProcessesByName(procName))
                    {
                        try { p.Kill(); p.WaitForExit(1500); } catch { }
                    }
                }
                catch { }

                // 혹시 남아있는 하위 프로세스 강제 정리 (taskkill)
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo
                    {
                        FileName = "taskkill.exe",
                        Arguments = string.Format("/F /T /IM {0}.exe", procName),
                        CreateNoWindow = true,
                        WindowStyle = ProcessWindowStyle.Hidden,
                        UseShellExecute = false
                    };
                    using (var proc = Process.Start(psi))
                    {
                        if (proc != null) proc.WaitForExit(1000);
                    }
                }
                catch { }
            }

            // 모든 프로세스가 완전히 닫히고 파일 핸들이 해제될 때까지 확인 대기
            int maxWaitMs = 3000;
            int elapsed = 0;
            while (elapsed < maxWaitMs)
            {
                bool anyAlive = false;
                foreach (string procName in targets)
                {
                    if (Process.GetProcessesByName(procName).Length > 0)
                    {
                        anyAlive = true;
                        break;
                    }
                }
                if (!anyAlive) break;
                Thread.Sleep(200);
                elapsed += 200;
            }

            Thread.Sleep(300); // 파일 시스템 락 해제 대기
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

        // =========================================================================
        // 바로가기 생성 강화: 공용 바탕화면(All Users) + 사용자 바탕화면 동시 생성
        // =========================================================================
        private List<string> GetCandidateDesktopDirectories()
        {
            var list = new List<string>();

            // 1. 공용 바탕화면 (모든 사용자에게 즉시 표시됨 - 관리자 권한 필수)
            try
            {
                string pub = Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory);
                if (!string.IsNullOrEmpty(pub) && !list.Contains(pub)) list.Add(pub);
            }
            catch { }

            // 2. 현재 사용자 특수 폴더 바탕화면
            try
            {
                string usr = Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory);
                if (!string.IsNullOrEmpty(usr) && !list.Contains(usr)) list.Add(usr);
            }
            catch { }

            // 3. 레지스트리 User Shell Folders Desktop
            try
            {
                using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"))
                {
                    if (key != null)
                    {
                        string regDesk = key.GetValue("Desktop") as string;
                        if (!string.IsNullOrEmpty(regDesk))
                        {
                            regDesk = Environment.ExpandEnvironmentVariables(regDesk);
                            if (!list.Contains(regDesk)) list.Add(regDesk);
                        }
                    }
                }
            }
            catch { }

            return list;
        }

        private void CreateDesktopShortcutsMultiLocations(string shortcutName, string targetPath, string workingDir, string description, string args = "")
        {
            var desktopDirs = GetCandidateDesktopDirectories();
            foreach (string dir in desktopDirs)
            {
                try
                {
                    if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                    string fullPath = Path.Combine(dir, shortcutName);
                    CreateShortcutWithFallback(fullPath, targetPath, workingDir, description, args);
                }
                catch { }
            }
        }

        private void CreateStartMenuShortcutsMultiLocations(string shortcutName, string targetPath, string workingDir, string description, string args = "")
        {
            var startDirs = new List<string>();
            try
            {
                string commonPrograms = Environment.GetFolderPath(Environment.SpecialFolder.CommonPrograms);
                if (!string.IsNullOrEmpty(commonPrograms))
                {
                    startDirs.Add(commonPrograms);
                    startDirs.Add(Path.Combine(commonPrograms, "Boardest"));
                }
            }
            catch { }

            try
            {
                string userPrograms = Environment.GetFolderPath(Environment.SpecialFolder.Programs);
                if (!string.IsNullOrEmpty(userPrograms))
                {
                    if (!startDirs.Contains(userPrograms)) startDirs.Add(userPrograms);
                    string userSub = Path.Combine(userPrograms, "Boardest");
                    if (!startDirs.Contains(userSub)) startDirs.Add(userSub);
                }
            }
            catch { }

            foreach (string dir in startDirs)
            {
                try
                {
                    if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                    string fullPath = Path.Combine(dir, shortcutName);
                    CreateShortcutWithFallback(fullPath, targetPath, workingDir, description, args);
                }
                catch { }
            }

            try
            {
                // SHCNE_ASSOCCHANGED (0x08000000), SHCNF_IDLIST (0x0000) -> 윈도우 시작 메뉴/앱 서랍 즉시 새로고침
                SHChangeNotify(0x08000000, 0x0000, IntPtr.Zero, IntPtr.Zero);
            }
            catch { }
        }

        private void CreateShortcutWithFallback(string shortcutPath, string targetPath, string workingDir, string description, string args = "")
        {
            bool success = false;
            // 1. WScript.Shell COM 객체 시도
            try
            {
                Type shellType = Type.GetTypeFromProgID("WScript.Shell");
                if (shellType != null)
                {
                    dynamic shell = Activator.CreateInstance(shellType);
                    dynamic shortcut = shell.CreateShortcut(shortcutPath);
                    shortcut.TargetPath = targetPath;
                    shortcut.WorkingDirectory = workingDir;
                    shortcut.Description = description;
                    if (!string.IsNullOrEmpty(args)) shortcut.Arguments = args;
                    shortcut.IconLocation = targetPath + ",0";
                    shortcut.Save();
                    success = File.Exists(shortcutPath);
                }
            }
            catch { }

            // 2. COM 실패 시 PowerShell 스크립트로 2차 보장
            if (!success)
            {
                try
                {
                    string psCmd = string.Format(
                        "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('{0}'); $s.TargetPath = '{1}'; $s.WorkingDirectory = '{2}'; $s.Description = '{3}'; {4} $s.IconLocation = '{1},0'; $s.Save();",
                        shortcutPath.Replace("'", "''"),
                        targetPath.Replace("'", "''"),
                        workingDir.Replace("'", "''"),
                        description.Replace("'", "''"),
                        string.IsNullOrEmpty(args) ? "" : ("$s.Arguments = '" + args.Replace("'", "''") + "';")
                    );

                    ProcessStartInfo psi = new ProcessStartInfo
                    {
                        FileName = "powershell.exe",
                        Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command \"" + psCmd + "\"",
                        UseShellExecute = false,
                        CreateNoWindow = true
                    };
                    using (Process p = Process.Start(psi))
                    {
                        p.WaitForExit(4000);
                    }
                }
                catch { }
            }
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
                        key.SetValue("UninstallString", "\"" + uninstallerPath + "\" --uninstall");
                        key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                        key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                    }
                }

                // Program Files 등 전역 설치 경로인 경우 HKLM에도 함께 등록
                string progFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
                if (!string.IsNullOrEmpty(progFiles) && _teacherInstallDir.StartsWith(progFiles, StringComparison.OrdinalIgnoreCase))
                {
                    using (RegistryKey lmKey = Registry.LocalMachine.CreateSubKey(regPath))
                    {
                        if (lmKey != null)
                        {
                            lmKey.SetValue("DisplayName", "Boardest Teacher");
                            lmKey.SetValue("DisplayVersion", _productVersion);
                            lmKey.SetValue("Publisher", "Boardest Team");
                            lmKey.SetValue("DisplayIcon", mainExePath);
                            lmKey.SetValue("InstallLocation", _teacherInstallDir);
                            lmKey.SetValue("UninstallString", "\"" + uninstallerPath + "\" --uninstall");
                            lmKey.SetValue("NoModify", 1, RegistryValueKind.DWord);
                            lmKey.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                        }
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
            // [필수] 관리자 권한 확인 및 강제 권한 상승 (UAC runas)
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
                        "Boardest 온라인 설치/관리 도구는 안전한 시스템 등록 및 파일 관리를 위해 반드시 [관리자 권한]으로 실행되어야 합니다.",
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

                // 내장된 필수 WebView2 DLL 로드
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
