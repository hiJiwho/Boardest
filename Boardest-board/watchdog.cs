using System;
using System.Diagnostics;
using System.IO;

namespace BoardestWatchdog
{
    static class Program
    {
        static void Main(string[] args)
        {
            // We need at least two arguments: parentPid and exePath
            if (args.Length < 2) return;
            
            int parentPid;
            if (!int.TryParse(args[0], out parentPid)) return;
            
            // Reconstruct the full path in case there are spaces in the directory path
            string exePath = "";
            for (int i = 1; i < args.Length; i++)
            {
                exePath += args[i] + (i == args.Length - 1 ? "" : " ");
            }
            exePath = exePath.Trim().Trim('"', '\'');

            string exeDir = Path.GetDirectoryName(exePath);
            
            // 1. Write a startup log to verify the watchdog is alive
            try
            {
                string startupLog = string.Format(
                    "[{0}] [Watchdog Startup] Monitoring parent PID: {1}, Path: {2}\r\n",
                    DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss"),
                    parentPid,
                    exePath
                );
                if (!string.IsNullOrEmpty(exeDir))
                {
                    File.AppendAllText(Path.Combine(exeDir, "watchdog_trace.txt"), startupLog);
                }
                File.AppendAllText(@"C:\Users\jiwho\Documents\Boardest\watchdog_trace.txt", startupLog);
            }
            catch {}

            try
            {
                // Retrieve the parent process by ID
                Process parent = Process.GetProcessById(parentPid);
                
                // Wait for the parent process to exit
                parent.WaitForExit();

                string exitLog = string.Format(
                    "[{0}] [Watchdog Event] Parent PID {1} exited. ExitCode: {2}\r\n",
                    DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss"),
                    parentPid,
                    parent.ExitCode
                );

                // Write exit event to trace log
                try
                {
                    if (!string.IsNullOrEmpty(exeDir))
                    {
                        File.AppendAllText(Path.Combine(exeDir, "watchdog_trace.txt"), exitLog);
                    }
                    File.AppendAllText(@"C:\Users\jiwho\Documents\Boardest\watchdog_trace.txt", exitLog);
                }
                catch {}

                // If the process exited unexpectedly (ExitCode != 0)
                if (parent.ExitCode != 0)
                {
                    string now = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss");
                    string logContent = string.Format(
                        "\r\n======================================================\r\n" +
                        "[Watchdog Revive Log]\r\n" +
                        "Timestamp: {0}\r\n" +
                        "Reason: Main process exited unexpectedly.\r\n" +
                        "ExitCode: {1}\r\n" +
                        "Action: Resurrecting boardest.exe...\r\n" +
                        "======================================================\r\n",
                        now,
                        parent.ExitCode
                    );

                    // Write next to executable
                    try
                    {
                        if (!string.IsNullOrEmpty(exeDir))
                        {
                            string logPath = Path.Combine(exeDir, "crash_logs.txt");
                            File.AppendAllText(logPath, logContent);
                        }
                    }
                    catch { }

                    // Write to workspace root
                    try
                    {
                        string workspaceLog = @"C:\Users\jiwho\Documents\Boardest\crash_logs.txt";
                        File.AppendAllText(workspaceLog, logContent);
                    }
                    catch { }

                    // Relaunch the application silently
                    try
                    {
                        ProcessStartInfo psi = new ProcessStartInfo();
                        psi.FileName = exePath;
                        psi.UseShellExecute = true;
                        Process.Start(psi);
                    }
                    catch (Exception launchEx)
                    {
                        string failLog = string.Format(
                            "[{0}] [Watchdog Error] Failed to relaunch boardest.exe: {1}\r\n",
                            DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss"),
                            launchEx.Message
                        );
                        try
                        {
                            if (!string.IsNullOrEmpty(exeDir))
                            {
                                File.AppendAllText(Path.Combine(exeDir, "watchdog_trace.txt"), failLog);
                            }
                            File.AppendAllText(@"C:\Users\jiwho\Documents\Boardest\watchdog_trace.txt", failLog);
                        }
                        catch {}
                    }
                }
            }
            catch (Exception ex)
            {
                string errLog = string.Format(
                    "[{0}] [Watchdog Exception] Error during wait loop: {1}\r\n",
                    DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss"),
                    ex.Message
                );
                try
                {
                    if (!string.IsNullOrEmpty(exeDir))
                    {
                        File.AppendAllText(Path.Combine(exeDir, "watchdog_trace.txt"), errLog);
                    }
                    File.AppendAllText(@"C:\Users\jiwho\Documents\Boardest\watchdog_trace.txt", errLog);
                }
                catch {}
            }
        }
    }
}
