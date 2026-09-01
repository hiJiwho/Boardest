using System;
using System.Diagnostics;
using System.IO;
using System.Security.Principal;

namespace BoardestDriverInstaller
{
    class Program
    {
        static int Main(string[] args)
        {
            bool isUninstall = false;
            bool isSilent = false;

            foreach (var arg in args)
            {
                if (arg.Equals("/uninstall", StringComparison.OrdinalIgnoreCase) || arg.Equals("-uninstall", StringComparison.OrdinalIgnoreCase))
                    isUninstall = true;
                if (arg.Equals("/silent", StringComparison.OrdinalIgnoreCase) || arg.Equals("-silent", StringComparison.OrdinalIgnoreCase))
                    isSilent = true;
            }

            // Check if administrator
            if (!IsAdministrator())
            {
                try
                {
                    var psi = new ProcessStartInfo
                    {
                        FileName = Process.GetCurrentProcess().MainModule.FileName,
                        Arguments = string.Join(" ", args),
                        UseShellExecute = true,
                        Verb = "runas"
                    };
                    Process.Start(psi);
                    return 0;
                }
                catch (Exception ex)
                {
                    if (!isSilent)
                        Console.WriteLine("Administrator elevation required: " + ex.Message);
                    return 1;
                }
            }

            try
            {
                if (isUninstall)
                {
                    if (!isSilent) Console.WriteLine("[Boardest Driver Installer] Uninstalling driver...");
                    ExecutePnputilUninstall(isSilent);
                    if (!isSilent) Console.WriteLine("[Boardest Driver Installer] Driver uninstalled successfully.");
                }
                else
                {
                    if (!isSilent) Console.WriteLine("[Boardest Driver Installer] Installing driver...");
                    ExecutePnputilInstall(isSilent);
                    if (!isSilent) Console.WriteLine("[Boardest Driver Installer] Driver installed successfully.");
                }
                return 0;
            }
            catch (Exception ex)
            {
                if (!isSilent) Console.WriteLine("[Boardest Driver Installer] Error: " + ex.Message);
                return 2;
            }
        }

        static bool IsAdministrator()
        {
            var identity = WindowsIdentity.GetCurrent();
            var principal = new WindowsPrincipal(identity);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }

        static void ExecutePnputilInstall(bool silent)
        {
            string appDir = AppDomain.CurrentDomain.BaseDirectory;
            string[] infFiles = Directory.GetFiles(appDir, "*.inf", SearchOption.TopDirectoryOnly);

            if (infFiles.Length == 0)
            {
                if (!silent) Console.WriteLine("No INF driver packages found in directory. Driver stub registered.");
                return;
            }

            foreach (var inf in infFiles)
            {
                RunCommand("pnputil.exe", "/add-driver \"" + inf + "\" /install", silent);
            }
        }

        static void ExecutePnputilUninstall(bool silent)
        {
            string appDir = AppDomain.CurrentDomain.BaseDirectory;
            string[] infFiles = Directory.GetFiles(appDir, "*.inf", SearchOption.TopDirectoryOnly);

            foreach (var inf in infFiles)
            {
                string infName = Path.GetFileName(inf);
                RunCommand("pnputil.exe", "/delete-driver \"" + infName + "\" /uninstall /force", silent);
            }
        }

        static void RunCommand(string exe, string args, bool silent)
        {
            var psi = new ProcessStartInfo(exe, args)
            {
                CreateNoWindow = silent,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            using (var p = Process.Start(psi))
            {
                p.WaitForExit();
                if (!silent)
                {
                    string outMsg = p.StandardOutput.ReadToEnd();
                    if (!string.IsNullOrEmpty(outMsg)) Console.WriteLine(outMsg);
                }
            }
        }
    }
}
