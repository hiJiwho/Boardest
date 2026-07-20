using System;
using System.IO;
using System.Net.Sockets;
using System.Windows.Forms;
using Microsoft.Web.WebView2.WinForms;
using Microsoft.Web.WebView2.Core;

namespace BoadestPlusEdit
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            ApplicationConfiguration.Initialize();
            Application.Run(new MainForm());
        }
    }

    public class MainForm : Form
    {
        private WebView2 webView;

        public MainForm()
        {
            Text = "Boardest Plus Editor";
            Width = 1280;
            Height = 800;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = System.Drawing.Color.FromArgb(30, 30, 30);

            webView = new WebView2
            {
                Dock = DockStyle.Fill
            };
            Controls.Add(webView);

            InitWebView();
        }

        private async void InitWebView()
        {
            try
            {
                var options = new CoreWebView2EnvironmentOptions("--allow-file-access-from-files --allow-universal-access-from-files");
                var env = await CoreWebView2Environment.CreateAsync(null, null, options);
                await webView.EnsureCoreWebView2Async(env);

                // Enable DevTools & Message Channel
                webView.CoreWebView2.Settings.IsWebMessageEnabled = true;
                webView.CoreWebView2.Settings.AreDevToolsEnabled = true;

                // Check if Vite dev server is running on port 5173
                bool devServerRunning = false;
                try
                {
                    using (var client = new TcpClient())
                    {
                        var result = client.BeginConnect("127.0.0.1", 5173, null, null);
                        devServerRunning = result.AsyncWaitHandle.WaitOne(300);
                    }
                }
                catch { }

                if (devServerRunning)
                {
                    webView.CoreWebView2.Navigate("http://localhost:5173");
                }
                else
                {
                    string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                    string distFolder = Path.Combine(baseDir, "dist");
                    
                    if (!Directory.Exists(distFolder))
                    {
                        distFolder = Path.Combine(Directory.GetCurrentDirectory(), "dist");
                    }
                    if (!Directory.Exists(distFolder))
                    {
                        distFolder = Directory.GetCurrentDirectory();
                    }

                    // Map virtual host domain to prevent file:// CORS blocking for ES modules
                    webView.CoreWebView2.SetVirtualHostNameToFolderMapping(
                        "editor.app",
                        distFolder,
                        CoreWebView2HostResourceAccessKind.Allow
                    );

                    webView.CoreWebView2.Navigate("https://editor.app/index.html");
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show("WebView2 초기화 실패: " + ex.Message, "오류", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
