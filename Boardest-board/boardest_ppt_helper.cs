using System;
using System.IO;
using System.Threading;
using System.Runtime.InteropServices;

namespace BoardestPptHelper
{
    class Program
    {
        // Use dynamic to enable Late-Binding COM without external DLL dependencies
        private static dynamic _pptApp;
        private static dynamic _presentation;
        private static dynamic _slideShowView;
        
        private static int _lastSlideIndex = -1;
        private static bool _isWatching = true;

        static void Main(string[] args)
        {
            // Set console output encoding to UTF-8
            Console.OutputEncoding = System.Text.Encoding.UTF8;
            Console.InputEncoding = System.Text.Encoding.UTF8;
            
            // Output startup message
            SendJsonEvent("started", "PowerPoint COM Dynamic Helper initialized.");

            // Thread to listen to stdin commands
            Thread commandThread = new Thread(ListenToCommands);
            commandThread.IsBackground = true;
            commandThread.Start();

            // Main monitoring loop
            while (_isWatching)
            {
                MonitorPowerPoint();
                Thread.Sleep(1000);
            }
        }

        private static void ListenToCommands()
        {
            try
            {
                string line;
                while ((line = Console.ReadLine()) != null)
                {
                    line = line.Trim().ToLower();
                    if (string.IsNullOrEmpty(line)) continue;

                    if (line == "next")
                    {
                        AdvanceSlideWorkflow(true);
                    }
                    else if (line == "prev")
                    {
                        AdvanceSlideWorkflow(false);
                    }
                    else if (line.StartsWith("jump "))
                    {
                        string[] parts = line.Split(' ');
                        if (parts.Length >= 2)
                        {
                            int slideIdx;
                            if (int.TryParse(parts[1], out slideIdx))
                            {
                                JumpToSlide(slideIdx);
                            }
                        }
                    }
                    else if (line == "state")
                    {
                        SendCurrentState(false);
                    }
                    else if (line == "quit" || line == "exit")
                    {
                        _isWatching = false;
                        break;
                    }
                }
            }
            catch (Exception ex)
            {
                SendJsonError("Command listener thread error: " + ex.Message);
            }
        }

        private static void MonitorPowerPoint()
        {
            try
            {
                // Ensure COM connection
                if (!EnsureConnection())
                {
                    _lastSlideIndex = -1;
                    return;
                }

                int currentIdx = _slideShowView.CurrentShowPosition;
                if (currentIdx != _lastSlideIndex)
                {
                    // Slide physical page changed (e.g. by manual click in PowerPoint)
                    bool isSlideChanged = _lastSlideIndex != -1;
                    _lastSlideIndex = currentIdx;
                    SendCurrentState(isSlideChanged);
                }
            }
            catch (COMException ex)
            {
                // COM connection lost (e.g. user closed PowerPoint)
                SendJsonEvent("closed", "COM Connection lost: " + ex.Message);
                ResetComObjects();
            }
            catch (Exception ex)
            {
                SendJsonError("Monitor loop error: " + ex.Message);
            }
        }

        private static bool EnsureConnection()
        {
            try
            {
                if (_pptApp == null)
                {
                    try
                    {
                        _pptApp = Marshal.GetActiveObject("PowerPoint.Application");
                    }
                    catch
                    {
                        return false; // PowerPoint is not running
                    }
                }

                if (_presentation == null)
                {
                    try
                    {
                        if (_pptApp.Presentations.Count > 0)
                        {
                            _presentation = _pptApp.ActivePresentation;
                        }
                    }
                    catch
                    {
                        _pptApp = null;
                        return false;
                    }
                }

                if (_slideShowView == null)
                {
                    try
                    {
                        if (_pptApp.SlideShowWindows.Count > 0)
                        {
                            _slideShowView = _pptApp.SlideShowWindows.Item(1).View;
                            _lastSlideIndex = _slideShowView.CurrentShowPosition;
                        }
                    }
                    catch
                    {
                        _presentation = null;
                        return false;
                    }
                }

                return _pptApp != null && _presentation != null && _slideShowView != null;
            }
            catch
            {
                ResetComObjects();
                return false;
            }
        }

        private static void AdvanceSlideWorkflow(bool isNext)
        {
            if (!EnsureConnection())
            {
                SendJsonError("PowerPoint slide show is not running.");
                return;
            }

            try
            {
                int pageBefore = _slideShowView.CurrentShowPosition;
                int currentClick = _slideShowView.GetClickIndex();
                int totalClicks = _slideShowView.GetClickCount();

                if (isNext)
                {
                    if (currentClick < totalClicks)
                    {
                        // Plays animation, slide itself does not change
                        _slideShowView.Next();
                        SendCurrentState(false);
                    }
                    else
                    {
                        // Transition to next slide
                        _slideShowView.Next();
                        
                        // Check if slide actually changed (not on the last slide)
                        bool isChanged = _slideShowView.CurrentShowPosition != pageBefore;
                        _lastSlideIndex = _slideShowView.CurrentShowPosition;
                        SendCurrentState(isChanged);
                    }
                }
                else
                {
                    // Previous animation or previous slide
                    _slideShowView.Previous();
                    
                    bool isChanged = _slideShowView.CurrentShowPosition != pageBefore;
                    _lastSlideIndex = _slideShowView.CurrentShowPosition;
                    SendCurrentState(isChanged);
                }
            }
            catch (COMException ex)
            {
                if ((uint)ex.ErrorCode == 0x80010101) // RPC_E_CALL_REJECTED
                {
                    SendJsonError("PPT_BUSY");
                    return;
                }
                SendJsonError("COM error: " + ex.Message);
            }
            catch (Exception ex)
            {
                SendJsonError("Workflow error: " + ex.Message);
            }
        }

        private static void JumpToSlide(int slideIndex)
        {
            if (!EnsureConnection())
            {
                SendJsonError("PowerPoint slide show is not running.");
                return;
            }

            try
            {
                int slideCount = _presentation.Slides.Count;
                if (slideIndex < 1 || slideIndex > slideCount)
                {
                    SendJsonError("Slide index out of bounds: " + slideIndex);
                    return;
                }

                _slideShowView.GotoSlide(slideIndex);
                _lastSlideIndex = _slideShowView.CurrentShowPosition;
                SendCurrentState(true);
            }
            catch (Exception ex)
            {
                SendJsonError("Jump error: " + ex.Message);
            }
        }

        private static void SendCurrentState(bool isSlideChanged)
        {
            try
            {
                if (!EnsureConnection()) return;

                int slideIndex = _slideShowView.CurrentShowPosition;
                int slideCount = _presentation.Slides.Count;
                int clickIndex = _slideShowView.GetClickIndex();
                int clickCount = _slideShowView.GetClickCount();

                Console.WriteLine(string.Format(
                    "{{\"type\":\"state\",\"slideIndex\":{0},\"slideCount\":{1},\"clickIndex\":{2},\"clickCount\":{3},\"isSlideChanged\":{4}}}",
                    slideIndex, slideCount, clickIndex, clickCount, isSlideChanged ? "true" : "false"));
            }
            catch (Exception ex)
            {
                SendJsonError("State serialization error: " + ex.Message);
            }
        }

        private static void SendJsonEvent(string eventName, string message)
        {
            Console.WriteLine(string.Format(
                "{{\"type\":\"event\",\"event\":\"{0}\",\"message\":\"{1}\"}}",
                EscapeJson(eventName), EscapeJson(message)));
        }

        private static void SendJsonError(string errorMessage)
        {
            Console.WriteLine(string.Format(
                "{{\"type\":\"error\",\"message\":\"{0}\"}}",
                EscapeJson(errorMessage)));
        }

        private static string EscapeJson(string s)
        {
            if (s == null) return "";
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("\n", "\\n").Replace("\r", "");
        }

        private static void ResetComObjects()
        {
            try { if (_slideShowView != null) Marshal.ReleaseComObject(_slideShowView); } catch {}
            try { if (_presentation != null) Marshal.ReleaseComObject(_presentation); } catch {}
            try { if (_pptApp != null) Marshal.ReleaseComObject(_pptApp); } catch {}
            _slideShowView = null;
            _presentation = null;
            _pptApp = null;
        }
    }
}
