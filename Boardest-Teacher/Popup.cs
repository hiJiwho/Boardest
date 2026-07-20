using System;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Input;
using System.Windows.Threading;
using System.Threading.Tasks;
using System.Diagnostics;
using System.Text.RegularExpressions;

namespace BoardestMiniWidget
{
    public class App : Application
    {
        [STAThread]
        public static void Main(string[] args)
        {
            // 인자 파싱
            string theme = "dark";
            string period = "일과 시간 외";
            string teacherClass = "수업 없음";
            string teacherSubject = "";
            string classroomSubject = "수업 없음";
            string classroomTeacher = "";

            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "--theme" && i + 1 < args.Length) theme = args[i + 1];
                if (args[i] == "--period" && i + 1 < args.Length) period = args[i + 1];
                if (args[i] == "--teacher-class" && i + 1 < args.Length) teacherClass = args[i + 1];
                if (args[i] == "--teacher-subject" && i + 1 < args.Length) teacherSubject = args[i + 1];
                if (args[i] == "--classroom-subject" && i + 1 < args.Length) classroomSubject = args[i + 1];
                if (args[i] == "--classroom-teacher" && i + 1 < args.Length) classroomTeacher = args[i + 1];
            }

            var app = new App();
            var win = new MiniWindow(theme, period, teacherClass, teacherSubject, classroomSubject, classroomTeacher);
            app.Run(win);
        }
    }

    public class MiniWindow : Window
    {
        private string _lastUsbDrive = "";
        private bool _isSyncing = false;
        private DispatcherTimer _usbTimer;

        public MiniWindow(string theme, string period, string tClass, string tSub, string cSub, string cTeach)
        {
            // 윈도우 스타일 설정
            this.Width = 320;
            this.Height = 130;
            this.WindowStyle = WindowStyle.None;
            this.AllowsTransparency = true;
            this.Background = Brushes.Transparent;
            this.Topmost = true;
            this.ShowInTaskbar = false;
            this.Title = "Boardest Mini Widget";

            // 화면 우측 상단 배치 (작업 영역 기준)
            double screenWidth = SystemParameters.WorkArea.Width;
            double screenHeight = SystemParameters.WorkArea.Height;
            this.Left = screenWidth - this.Width - 10;
            this.Top = 10;

            // 테마 및 색상 분기 (다크/라이트)
            bool isDark = theme == "dark";
            Color bgCardColor = isDark ? Color.FromArgb(128, 22, 22, 26) : Color.FromArgb(128, 255, 255, 255);
            Color borderCardColor = isDark ? Color.FromArgb(30, 255, 255, 255) : Color.FromArgb(30, 0, 0, 0);
            Brush primaryTextBrush = isDark ? Brushes.White : new SolidColorBrush(Color.FromRgb(26, 26, 26));
            Brush tertiaryTextBrush = isDark ? new SolidColorBrush(Color.FromRgb(100, 100, 100)) : new SolidColorBrush(Color.FromRgb(160, 160, 160));
            Brush periodTextBrush = isDark ? new SolidColorBrush(Color.FromRgb(0, 245, 212)) : new SolidColorBrush(Color.FromRgb(0, 191, 166));

            // 전체 레이아웃 그리드
            Grid mainGrid = new Grid();
            mainGrid.Background = Brushes.Transparent;
            this.Content = mainGrid;

            // 1. [50% 반투명 텍스트 카드]
            Border cardBorder = new Border();
            cardBorder.Width = 320;
            cardBorder.Height = 130;
            cardBorder.Background = new SolidColorBrush(bgCardColor);
            cardBorder.BorderBrush = new SolidColorBrush(borderCardColor);
            cardBorder.BorderThickness = new Thickness(1.5);
            cardBorder.CornerRadius = new CornerRadius(12);
            cardBorder.Padding = new Thickness(14, 10, 14, 10);
            cardBorder.IsHitTestVisible = false; // 마우스 무시/통과
            mainGrid.Children.Add(cardBorder);

            // 카드 안의 세로 스택 패널
            StackPanel cardStack = new StackPanel();
            cardBorder.Child = cardStack;

            // 헤더 영역 (현교시 정보)
            Grid headerGrid = new Grid();
            headerGrid.Height = 24;
            
            TextBlock periodBlock = new TextBlock();
            periodBlock.Text = period;
            periodBlock.FontFamily = new FontFamily("Malgun Gothic");
            periodBlock.FontSize = 12.5;
            periodBlock.FontWeight = FontWeights.Bold;
            periodBlock.Foreground = periodTextBrush;
            periodBlock.VerticalAlignment = VerticalAlignment.Center;
            periodBlock.Margin = new Thickness(40, 0, 0, 0); // 좌상단 원형 버튼 마진 확보
            headerGrid.Children.Add(periodBlock);
            cardStack.Children.Add(headerGrid);

            // 간격
            cardStack.Children.Add(new Border { Height = 4 });

            // 교사 시간표 Row
            StackPanel teacherRow = new StackPanel { Orientation = Orientation.Horizontal };
            Border tBadge = CreateBadge("교사", isDark ? Color.FromRgb(46, 196, 182) : Color.FromRgb(15, 155, 142));
            teacherRow.Children.Add(tBadge);

            TextBlock tText = new TextBlock();
            tText.Text = tClass;
            tText.FontFamily = new FontFamily("Malgun Gothic");
            tText.FontSize = 18;
            tText.FontWeight = FontWeights.ExtraBold;
            tText.Foreground = primaryTextBrush;
            tText.Margin = new Thickness(10, 0, 0, 0);
            tText.VerticalAlignment = VerticalAlignment.Center;
            teacherRow.Children.Add(tText);

            if (!string.IsNullOrEmpty(tSub))
            {
                TextBlock tSubText = new TextBlock();
                tSubText.Text = "[" + tSub + "]";
                tSubText.FontFamily = new FontFamily("Malgun Gothic");
                tSubText.FontSize = 14;
                tSubText.Foreground = tertiaryTextBrush;
                tSubText.Margin = new Thickness(6, 0, 0, 0);
                tSubText.VerticalAlignment = VerticalAlignment.Center;
                teacherRow.Children.Add(tSubText);
            }
            cardStack.Children.Add(teacherRow);

            // 간격
            cardStack.Children.Add(new Border { Height = 4 });

            // 교실 시간표 Row
            StackPanel classRow = new StackPanel { Orientation = Orientation.Horizontal };
            Border cBadge = CreateBadge("교실", isDark ? Color.FromRgb(155, 124, 250) : Color.FromRgb(98, 58, 214));
            classRow.Children.Add(cBadge);

            TextBlock cText = new TextBlock();
            cText.Text = cSub;
            cText.FontFamily = new FontFamily("Malgun Gothic");
            cText.FontSize = 18;
            cText.FontWeight = FontWeights.ExtraBold;
            cText.Foreground = primaryTextBrush;
            cText.Margin = new Thickness(10, 0, 0, 0);
            cText.VerticalAlignment = VerticalAlignment.Center;
            classRow.Children.Add(cText);

            if (!string.IsNullOrEmpty(cTeach))
            {
                TextBlock cTeachText = new TextBlock();
                cTeachText.Text = "(" + cTeach + ")";
                cTeachText.FontFamily = new FontFamily("Malgun Gothic");
                cTeachText.FontSize = 14;
                cTeachText.Foreground = tertiaryTextBrush;
                cTeachText.Margin = new Thickness(6, 0, 0, 0);
                cTeachText.VerticalAlignment = VerticalAlignment.Center;
                classRow.Children.Add(cTeachText);
            }
            cardStack.Children.Add(classRow);

            // 2. [마우스를 입력받아야 하는 별도 버튼 레이어]
            Canvas buttonCanvas = new Canvas();
            buttonCanvas.Width = 320;
            buttonCanvas.Height = 130;
            buttonCanvas.IsHitTestVisible = true;
            mainGrid.Children.Add(buttonCanvas);

            // 빨간색 원 (프로그램 완전 종료 - exit)
            Ellipse redCircle = new Ellipse { Width = 12, Height = 12, Fill = new SolidColorBrush(Color.FromRgb(255, 95, 86)) };
            Canvas.SetLeft(redCircle, 14);
            Canvas.SetTop(redCircle, 16);
            redCircle.Cursor = Cursors.Hand;
            redCircle.MouseDown += (s, e) => {
                Environment.Exit(0);
            };
            buttonCanvas.Children.Add(redCircle);

            // 파란색 원 (Flutter 메인 앱 실행 복원 및 위젯 종료)
            Ellipse blueCircle = new Ellipse { Width = 12, Height = 12, Fill = new SolidColorBrush(Color.FromRgb(0, 122, 255)) };
            Canvas.SetLeft(blueCircle, 34);
            Canvas.SetTop(blueCircle, 16);
            blueCircle.Cursor = Cursors.Hand;
            blueCircle.MouseDown += (s, e) => {
                RestoreFlutterMainApp();
            };
            buttonCanvas.Children.Add(blueCircle);

            // 창 드래그 기능 추가
            buttonCanvas.MouseDown += (s, e) => {
                if (e.ChangedButton == MouseButton.Left)
                {
                    this.DragMove();
                }
            };

            // USB 감시 타이머 시작
            StartUsbMonitor();
        }

        private Border CreateBadge(string text, Color color)
        {
            Border border = new Border();
            border.Padding = new Thickness(7, 3, 7, 3);
            border.Background = new SolidColorBrush(Color.FromArgb(46, color.R, color.G, color.B));
            border.CornerRadius = new CornerRadius(4);
            border.VerticalAlignment = VerticalAlignment.Center;

            TextBlock tb = new TextBlock();
            tb.Text = text;
            tb.FontFamily = new FontFamily("Malgun Gothic");
            tb.FontSize = 12.5;
            tb.FontWeight = FontWeights.Bold;
            tb.Foreground = new SolidColorBrush(color);
            border.Child = tb;

            return border;
        }

        private void RestoreFlutterMainApp()
        {
            if (_usbTimer != null) _usbTimer.Stop();
            try
            {
                Process.Start("boardest_teacher.exe");
            }
            catch (Exception ex)
            {
                MessageBox.Show("boardest_teacher.exe를 시작하지 못했습니다: " + ex.Message, "오류", MessageBoxButton.OK, MessageBoxImage.Error);
            }
            Environment.Exit(0);
        }

        // USB 감시 및 동기화 스케줄링
        private void StartUsbMonitor()
        {
            _usbTimer = new DispatcherTimer();
            _usbTimer.Interval = TimeSpan.FromSeconds(2.0);
            _usbTimer.Tick += (s, e) => {
                CheckUsbDriveAndSync();
            };
            _usbTimer.Start();
        }

        private void CheckUsbDriveAndSync()
        {
            if (_isSyncing) return;

            string foundDrive = "";
            foreach (var drive in DriveInfo.GetDrives())
            {
                if (drive.DriveType == DriveType.Removable && drive.IsReady)
                {
                    foundDrive = drive.RootDirectory.FullName;
                    break;
                }
            }

            if (string.IsNullOrEmpty(foundDrive))
            {
                _lastUsbDrive = "";
                return;
            }

            if (_lastUsbDrive != foundDrive)
            {
                _lastUsbDrive = foundDrive;
                _isSyncing = true;
                
                // 백그라운드 비동기 동기화 구동
                Task.Run(() => {
                    try
                    {
                        RunFolderSyncProcess(_lastUsbDrive);
                    }
                    finally
                    {
                        _isSyncing = false;
                    }
                });
            }
        }

        private void RunFolderSyncProcess(string usbRoot)
        {
            string exeDir = AppDomain.CurrentDomain.BaseDirectory;
            string configPath = System.IO.Path.Combine(exeDir, "sync_configs.json");
            if (!File.Exists(configPath)) return;

            try
            {
                string json = File.ReadAllText(configPath);
                // "local": "path", "usb": "path" 매핑 데이터 추출용 정규식
                var matches = Regex.Matches(json, @"\""local\""\s*:\s*\""([^\""]+)\""\s*,\s*\""usb\""\s*:\s*\""([^\""]+)\""");
                foreach (Match match in matches)
                {
                    string localPath = match.Groups[1].Value.Replace("\\\\", "\\");
                    string usbFolder = match.Groups[2].Value;

                    string usbSyncPath = System.IO.Path.Combine(usbRoot, usbFolder);
                    if (Directory.Exists(localPath))
                    {
                        if (!Directory.Exists(usbSyncPath))
                        {
                            Directory.CreateDirectory(usbSyncPath);
                        }
                        SyncDirectories(localPath, usbSyncPath);
                    }
                }
            }
            catch {}
        }

        private void SyncDirectories(string dirA, string dirB)
        {
            foreach (string fileA in Directory.GetFiles(dirA, "*", SearchOption.AllDirectories))
            {
                try
                {
                    string relative = fileA.Substring(dirA.Length).TrimStart('\\');
                    string fileB = System.IO.Path.Combine(dirB, relative);

                    string dirBSub = System.IO.Path.GetDirectoryName(fileB);
                    if (!Directory.Exists(dirBSub))
                    {
                        Directory.CreateDirectory(dirBSub);
                    }

                    bool needCopy = false;
                    if (!File.Exists(fileB))
                    {
                        needCopy = true;
                    }
                    else
                    {
                        DateTime timeA = File.GetLastWriteTime(fileA);
                        DateTime timeB = File.GetLastWriteTime(fileB);
                        if (timeA > timeB)
                        {
                            needCopy = true;
                        }
                    }

                    if (needCopy)
                    {
                        File.Copy(fileA, fileB, true);
                    }
                }
                catch {}
            }
        }
    }
}
