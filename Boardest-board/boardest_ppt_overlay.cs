using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Ink;
using System.Windows.Media;
using System.Windows.Input;
using System.Windows.Threading;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;

namespace BoardestPptOverlay
{
    public class App : Application
    {
        [STAThread]
        public static void Main(string[] args)
        {
            try
            {
                Console.OutputEncoding = System.Text.Encoding.UTF8;
            }
            catch {}
            string pptPath = "";
            int startPage = 1;

            for (int i = 0; i < args.Length; i++)
            {
                if (args[i] == "--path" && i + 1 < args.Length)
                {
                    pptPath = args[i + 1];
                }
                else if (args[i] == "--page" && i + 1 < args.Length)
                {
                    int.TryParse(args[i + 1], out startPage);
                }
            }

            if (string.IsNullOrEmpty(pptPath) || !File.Exists(pptPath))
            {
                MessageBox.Show("PowerPoint file path is invalid or empty. Use --path <PPT Path>", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
                return;
            }

            App app = new App();
            OverlayWindow win = new OverlayWindow(pptPath, startPage);
            app.Run(win);
        }
    }

    public enum ShapeMode { None, Line, Arrow, Triangle, Rectangle, Circle, Cube, Cylinder }

    public class OverlayWindow : Window
    {
        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        private string _pptPath;
        private string _fileName;
        private int _startPage;

        // PowerPoint COM Objects
        private dynamic _pptApp;
        private dynamic _presentation;
        private dynamic _slideShowView;
        private uint _pptPid = 0;
        private bool _onlyTurnOffOverlay = false;

        // Slide change tracking
        private int _lastSlideIndex = -1;
        private int _slideCount = 1;
        private DispatcherTimer _pollTimer;

        // UI Components
        private Grid _mainGrid;
        private InkCanvas _inkCanvas;
        private StackPanel _toolbar;
        private TextBlock _pageLabel;
        private Border _jumpBorder;
        private WrapPanel _jumpWrapPanel;
        private Border _penDetailsCard;
        private Border _eraserDetailsCard;
        private Border _shapeDetailsCard;

        private Border _btnInteract;
        private Border _btnPen;
        private Border _btnEraser;
        private Border _btnShape;
        private Border _btnLasso;
        private Border _btnStrokeEraser;
        private Border _btnPointEraser;

        private bool _isDrawMode = true;
        private ShapeMode _activeShapeMode = ShapeMode.None;

        // Shape buttons
        private Border _btnShapeLine;
        private Border _btnShapeArrow;
        private Border _btnShapeTriangle;
        private Border _btnShapeRectangle;
        private Border _btnShapeCircle;
        private Border _btnShapeCube;
        private Border _btnShapeCylinder;

        private Slider _thicknessSlider;
        private TextBlock _txtThicknessVal;

        // Colors
        private Color _whiteColor = Colors.White;
        private Color _yellowColor = Color.FromRgb(255, 230, 0);
        private Color _redColor = Color.FromRgb(255, 80, 80);
        private Color _blueColor = Color.FromRgb(80, 160, 255);
        private Color _tealColor = Color.FromRgb(0, 245, 212);
        private Color _greenColor = Color.FromRgb(44, 182, 125);
        private Color _orangeColor = Color.FromRgb(255, 140, 0);
        private Color _purpleColor = Color.FromRgb(127, 90, 240);

        // Touch gesture tracking
        private Dictionary<int, Point> _activeTouchPoints = new Dictionary<int, Point>();
        private bool _gestureDetected = false;

        // Shape drawing interaction
        private Point? _shapeStartPoint = null;
        private Stroke _tempShapeStroke = null;

        public OverlayWindow(string pptPath, int startPage)
        {
            _pptPath = Path.GetFullPath(pptPath);
            _fileName = Path.GetFileName(_pptPath);

            if (startPage <= 1)
            {
                _startPage = LoadStateFromAppData();
            }
            else
            {
                _startPage = startPage;
            }

            this.Title = "Boardest PowerPoint Overlay";
            this.WindowStyle = WindowStyle.None;
            this.AllowsTransparency = true;
            this.Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
            this.Topmost = true;
            this.ShowInTaskbar = false;

            this.Left = SystemParameters.VirtualScreenLeft;
            this.Top = SystemParameters.VirtualScreenTop;
            this.Width = SystemParameters.VirtualScreenWidth;
            this.Height = SystemParameters.VirtualScreenHeight;

            InitUI();

            this.Loaded += OverlayWindow_Loaded;
            this.Closed += OverlayWindow_Closed;
        }

        private void InitUI()
        {
            _mainGrid = new Grid();
            _mainGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            _mainGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            _mainGrid.Background = Brushes.Transparent;

            _inkCanvas = new InkCanvas
            {
                Background = Brushes.Transparent,
                DefaultDrawingAttributes = new DrawingAttributes
                {
                    Color = _whiteColor,
                    Width = 4.0,
                    Height = 4.0,
                    FitToCurve = true,
                    StylusTip = StylusTip.Ellipse
                }
            };
            _mainGrid.Children.Add(_inkCanvas);

            // Shape drawing & floating cards close triggers
            _inkCanvas.PreviewMouseDown += InkCanvas_PreviewMouseDown;
            _inkCanvas.PreviewMouseMove += InkCanvas_PreviewMouseMove;
            _inkCanvas.PreviewMouseUp += InkCanvas_PreviewMouseUp;

            _inkCanvas.PreviewTouchDown += InkCanvas_PreviewTouchDown;
            _inkCanvas.TouchUp += InkCanvas_TouchUp;

            // Bottom toolbar border
            Border toolBorder = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(240, 19, 23, 31)),
                CornerRadius = new CornerRadius(30),
                BorderBrush = new SolidColorBrush(Color.FromArgb(30, 255, 255, 255)),
                BorderThickness = new Thickness(1.2),
                Padding = new Thickness(16, 8, 16, 8),
                VerticalAlignment = VerticalAlignment.Bottom,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 0, 0, 24),
                Effect = new System.Windows.Media.Effects.DropShadowEffect { Color = Colors.Black, BlurRadius = 16, ShadowDepth = 3, Opacity = 0.5 }
            };
            Grid.SetRow(toolBorder, 1);

            _toolbar = new StackPanel { Orientation = Orientation.Horizontal };

            // Exit/Close (완전종료)
            Border btnClose = CreateDockButton("❌", (s, e) => this.Close());
            ((TextBlock)btnClose.Child).Foreground = new SolidColorBrush(Color.FromRgb(255, 100, 100));

            // Turn Off Overlay (오버레이 끄기)
            Border btnTurnOff = CreateDockButton("🖥️ 끄기", (s, e) => HandleTurnOffOverlay());

            Separator sep1 = CreateSeparator();

            // Navigation
            Border btnPrev = CreateDockButton("◀", (s, e) => HandlePrevious());
            _pageLabel = new TextBlock
            {
                Text = "1 / 1 쪽 (이동)",
                Foreground = Brushes.White,
                FontWeight = FontWeights.Bold,
                FontSize = 13,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(10, 0, 10, 0),
                Cursor = Cursors.Hand
            };
            _pageLabel.MouseDown += PageLabel_MouseDown;
            Border btnNext = CreateDockButton("▶", (s, e) => HandleNext());

            Separator sep2 = CreateSeparator();

            // Controls
            _btnPen = CreateDockButton("✏️", (s, e) => SetDrawMode(true), true);
            _btnEraser = CreateDockButton("🧹", (s, e) => SetEraserMode(), false);
            _btnShape = CreateDockButton("🔷", (s, e) => SetShapeDrawMode(), false);
            _btnInteract = CreateDockButton("🖱️", (s, e) => SetDrawMode(false), false);

            Separator sep3 = CreateSeparator();

            Border btnUndo = CreateDockButton("↩", (s, e) => UndoLastStroke());

            _toolbar.Children.Add(btnClose);
            _toolbar.Children.Add(btnTurnOff);
            _toolbar.Children.Add(sep1);
            _toolbar.Children.Add(btnPrev);
            _toolbar.Children.Add(_pageLabel);
            _toolbar.Children.Add(btnNext);
            _toolbar.Children.Add(sep2);
            _toolbar.Children.Add(_btnPen);
            _toolbar.Children.Add(_btnEraser);
            _toolbar.Children.Add(_btnShape);
            _toolbar.Children.Add(_btnInteract);
            _toolbar.Children.Add(sep3);
            _toolbar.Children.Add(btnUndo);

            toolBorder.Child = _toolbar;
            _mainGrid.Children.Add(toolBorder);

            // Floating Pen settings card
            _penDetailsCard = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(245, 19, 23, 31)),
                CornerRadius = new CornerRadius(16),
                BorderBrush = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)),
                BorderThickness = new Thickness(1.2),
                Padding = new Thickness(12),
                Width = 240,
                VerticalAlignment = VerticalAlignment.Bottom,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(190, 0, 0, 84),
                Visibility = Visibility.Visible,
                Effect = new System.Windows.Media.Effects.DropShadowEffect { Color = Colors.Black, BlurRadius = 15, ShadowDepth = 2, Opacity = 0.5 }
            };

            StackPanel penCardStack = new StackPanel();
            penCardStack.Children.Add(new TextBlock { Text = "펜 색상 설정", Foreground = new SolidColorBrush(Color.FromRgb(180, 180, 180)), FontWeight = FontWeights.Bold, FontSize = 10, Margin = new Thickness(0, 0, 0, 6) });

            WrapPanel colorWrap = new WrapPanel { Orientation = Orientation.Horizontal };
            colorWrap.Children.Add(CreateColorButton(_whiteColor));
            colorWrap.Children.Add(CreateColorButton(Colors.Black));
            colorWrap.Children.Add(CreateColorButton(_yellowColor));
            colorWrap.Children.Add(CreateColorButton(_redColor));
            colorWrap.Children.Add(CreateColorButton(_blueColor));
            colorWrap.Children.Add(CreateColorButton(_tealColor));
            colorWrap.Children.Add(CreateColorButton(_greenColor));
            colorWrap.Children.Add(CreateColorButton(_orangeColor));
            colorWrap.Children.Add(CreateColorButton(_purpleColor));
            penCardStack.Children.Add(colorWrap);

            penCardStack.Children.Add(new TextBlock { Text = "펜 굵기 설정", Foreground = new SolidColorBrush(Color.FromRgb(180, 180, 180)), FontWeight = FontWeights.Bold, FontSize = 10, Margin = new Thickness(0, 8, 0, 6) });
            StackPanel thicknessStack = new StackPanel { Orientation = Orientation.Horizontal };
            _txtThicknessVal = new TextBlock { Text = "굵기: 4px", Foreground = Brushes.White, FontSize = 11, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) };
            _thicknessSlider = new Slider { Minimum = 1, Maximum = 20, Value = 4, TickFrequency = 1, IsSnapToTickEnabled = true, Width = 140, VerticalAlignment = VerticalAlignment.Center, Cursor = Cursors.Hand };
            _thicknessSlider.ValueChanged += (s, e) =>
            {
                double val = _thicknessSlider.Value;
                _txtThicknessVal.Text = string.Format("굵기: {0}px", (int)val);
                SetPenThickness(val);
            };
            thicknessStack.Children.Add(_txtThicknessVal);
            thicknessStack.Children.Add(_thicknessSlider);
            penCardStack.Children.Add(thicknessStack);
            _penDetailsCard.Child = penCardStack;
            _mainGrid.Children.Add(_penDetailsCard);

            // Floating Eraser settings card
            _eraserDetailsCard = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(245, 19, 23, 31)),
                CornerRadius = new CornerRadius(12),
                BorderBrush = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)),
                BorderThickness = new Thickness(1.2),
                Padding = new Thickness(8, 6, 8, 6),
                VerticalAlignment = VerticalAlignment.Bottom,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(250, 0, 0, 84),
                Visibility = Visibility.Collapsed,
                Effect = new System.Windows.Media.Effects.DropShadowEffect { Color = Colors.Black, BlurRadius = 15, ShadowDepth = 2, Opacity = 0.5 }
            };

            StackPanel eraserCardStack = new StackPanel { Orientation = Orientation.Horizontal };
            eraserCardStack.Children.Add(new TextBlock { Text = "🧹 지우개 설정", Foreground = new SolidColorBrush(Color.FromRgb(180, 180, 180)), FontWeight = FontWeights.Bold, FontSize = 10, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) });
            eraserCardStack.Children.Add(CreateSeparator());
            _btnStrokeEraser = CreateDockButton("획 지우개", (s, e) => {
                _inkCanvas.EditingMode = InkCanvasEditingMode.EraseByStroke;
                UpdateEraserButtonsState(true);
            }, true);
            _btnPointEraser = CreateDockButton("면적 지우개", (s, e) => {
                _inkCanvas.EditingMode = InkCanvasEditingMode.EraseByPoint;
                UpdateEraserButtonsState(false);
            }, false);
            eraserCardStack.Children.Add(_btnStrokeEraser);
            eraserCardStack.Children.Add(_btnPointEraser);
            eraserCardStack.Children.Add(CreateSeparator());
            Border btnClear = CreateDockButton("🗑 전체지움", (s, e) => {
                ClearCanvas();
                _eraserDetailsCard.Visibility = Visibility.Collapsed;
            });
            eraserCardStack.Children.Add(btnClear);
            _eraserDetailsCard.Child = eraserCardStack;
            _mainGrid.Children.Add(_eraserDetailsCard);

            // Floating Shape settings card
            _shapeDetailsCard = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(245, 19, 23, 31)),
                CornerRadius = new CornerRadius(16),
                BorderBrush = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)),
                BorderThickness = new Thickness(1.2),
                Padding = new Thickness(12),
                Width = 320,
                VerticalAlignment = VerticalAlignment.Bottom,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(310, 0, 0, 84),
                Visibility = Visibility.Collapsed,
                Effect = new System.Windows.Media.Effects.DropShadowEffect { Color = Colors.Black, BlurRadius = 15, ShadowDepth = 2, Opacity = 0.5 }
            };

            StackPanel shapeCardStack = new StackPanel();
            shapeCardStack.Children.Add(new TextBlock { Text = "🔷 삽입할 도형 선택", Foreground = new SolidColorBrush(Color.FromRgb(180, 180, 180)), FontWeight = FontWeights.Bold, FontSize = 10, Margin = new Thickness(0, 0, 0, 6) });

            WrapPanel shapeWrap = new WrapPanel { Orientation = Orientation.Horizontal };
            _btnShapeLine = CreateShapeSelectorBtn("📏 직선", ShapeMode.Line, true);
            _btnShapeArrow = CreateShapeSelectorBtn("↗️ 화살표", ShapeMode.Arrow, false);
            _btnShapeTriangle = CreateShapeSelectorBtn("🔺 삼각형", ShapeMode.Triangle, false);
            _btnShapeRectangle = CreateShapeSelectorBtn("🟩 사각형", ShapeMode.Rectangle, false);
            _btnShapeCircle = CreateShapeSelectorBtn("🟡 원", ShapeMode.Circle, false);
            _btnShapeCube = CreateShapeSelectorBtn("📦 큐브", ShapeMode.Cube, false);
            _btnShapeCylinder = CreateShapeSelectorBtn("🛢️ 원기둥", ShapeMode.Cylinder, false);

            shapeWrap.Children.Add(_btnShapeLine);
            shapeWrap.Children.Add(_btnShapeArrow);
            shapeWrap.Children.Add(_btnShapeTriangle);
            shapeWrap.Children.Add(_btnShapeRectangle);
            shapeWrap.Children.Add(_btnShapeCircle);
            shapeWrap.Children.Add(_btnShapeCube);
            shapeWrap.Children.Add(_btnShapeCylinder);
            shapeCardStack.Children.Add(shapeWrap);
            _shapeDetailsCard.Child = shapeCardStack;
            _mainGrid.Children.Add(_shapeDetailsCard);

            // Floating Slide Page Picker above the Page Label
            _jumpBorder = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(250, 22, 25, 32)),
                CornerRadius = new CornerRadius(16),
                BorderBrush = new SolidColorBrush(Color.FromArgb(50, 0, 245, 212)),
                BorderThickness = new Thickness(1.5),
                Width = 320,
                Height = 260,
                VerticalAlignment = VerticalAlignment.Bottom,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(-180, 0, 0, 144),
                Visibility = Visibility.Collapsed,
                Effect = new System.Windows.Media.Effects.DropShadowEffect { Color = Colors.Black, BlurRadius = 20, ShadowDepth = 3, Opacity = 0.6 }
            };

            Grid jumpGrid = new Grid();
            jumpGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            jumpGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            StackPanel topPanel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(12, 12, 12, 6) };
            topPanel.Children.Add(new TextBlock { Text = "이동할 쪽수:", Foreground = Brushes.White, FontWeight = FontWeights.Bold, FontSize = 13, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) });
            
            TextBox jumpInput = new TextBox { Width = 100, Height = 28, Background = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)), Foreground = Brushes.White, BorderBrush = new SolidColorBrush(Color.FromArgb(50, 255, 255, 255)), BorderThickness = new Thickness(1), VerticalContentAlignment = VerticalAlignment.Center, FontWeight = FontWeights.Bold, FontSize = 13, Padding = new Thickness(6, 0, 6, 0), Margin = new Thickness(0, 0, 8, 0) };
            Button jumpBtn = new Button { Content = "이동", Width = 60, Height = 28, Background = new SolidColorBrush(Color.FromArgb(255, 0, 245, 212)), Foreground = Brushes.Black, FontWeight = FontWeights.Bold, BorderThickness = new Thickness(0) };

            jumpInput.KeyDown += (s, e) => { if (e.Key == System.Windows.Input.Key.Enter) { ExecuteTextBoxJump(jumpInput.Text); } };
            jumpBtn.Click += (s, e) => { ExecuteTextBoxJump(jumpInput.Text); };

            topPanel.Children.Add(jumpInput);
            topPanel.Children.Add(jumpBtn);
            Grid.SetRow(topPanel, 0);
            jumpGrid.Children.Add(topPanel);

            ScrollViewer scrollViewer = new ScrollViewer { VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled, Margin = new Thickness(12, 6, 12, 12) };
            _jumpWrapPanel = new WrapPanel { Orientation = Orientation.Horizontal };
            scrollViewer.Content = _jumpWrapPanel;
            Grid.SetRow(scrollViewer, 1);
            jumpGrid.Children.Add(scrollViewer);

            _jumpBorder.Child = jumpGrid;
            _mainGrid.Children.Add(_jumpBorder);

            this.Content = _mainGrid;
        }

        private Border CreateDockButton(string text, MouseButtonEventHandler clickHandler, bool active = false)
        {
            var activeColor = Color.FromRgb(0, 245, 212);
            var normalColor = Color.FromRgb(220, 220, 220);

            Border btn = new Border
            {
                Background = active ? new SolidColorBrush(Color.FromArgb(46, 0, 245, 212)) : Brushes.Transparent,
                BorderBrush = active ? new SolidColorBrush(activeColor) : Brushes.Transparent,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(14),
                Padding = new Thickness(12, 6, 12, 6),
                Margin = new Thickness(4, 0, 4, 0),
                Cursor = Cursors.Hand,
                VerticalAlignment = VerticalAlignment.Center
            };

            TextBlock tb = new TextBlock
            {
                Text = text,
                Foreground = active ? new SolidColorBrush(activeColor) : new SolidColorBrush(normalColor),
                FontWeight = FontWeights.SemiBold,
                FontSize = 13,
                VerticalAlignment = VerticalAlignment.Center,
                HorizontalAlignment = HorizontalAlignment.Center
            };
            btn.Child = tb;

            btn.MouseDown += clickHandler;

            btn.MouseEnter += (s, e) =>
            {
                if (btn.BorderBrush == Brushes.Transparent)
                {
                    btn.Background = new SolidColorBrush(Color.FromArgb(30, 255, 255, 255));
                    tb.Foreground = Brushes.White;
                }
            };

            btn.MouseLeave += (s, e) =>
            {
                if (btn.BorderBrush == Brushes.Transparent)
                {
                    btn.Background = Brushes.Transparent;
                    tb.Foreground = new SolidColorBrush(normalColor);
                }
            };

            return btn;
        }

        private Border CreateShapeSelectorBtn(string text, ShapeMode mode, bool active = false)
        {
            var activeColor = Color.FromRgb(0, 245, 212);
            var normalColor = Color.FromRgb(220, 220, 220);

            Border btn = new Border
            {
                Background = active ? new SolidColorBrush(Color.FromArgb(46, 0, 245, 212)) : Brushes.Transparent,
                BorderBrush = active ? new SolidColorBrush(activeColor) : Brushes.Transparent,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(8, 4, 8, 4),
                Margin = new Thickness(4),
                Cursor = Cursors.Hand
            };

            TextBlock tb = new TextBlock
            {
                Text = text,
                Foreground = active ? new SolidColorBrush(activeColor) : new SolidColorBrush(normalColor),
                FontSize = 11,
                FontWeight = FontWeights.Medium
            };
            btn.Child = tb;

            btn.MouseDown += (s, e) =>
            {
                SelectShapeMode(mode);
            };

            return btn;
        }

        private void SelectShapeMode(ShapeMode mode)
        {
            _activeShapeMode = mode;
            var activeColor = Color.FromRgb(0, 245, 212);
            var normalColor = Color.FromRgb(220, 220, 220);

            Border[] btns = { _btnShapeLine, _btnShapeArrow, _btnShapeTriangle, _btnShapeRectangle, _btnShapeCircle, _btnShapeCube, _btnShapeCylinder };
            ShapeMode[] modes = { ShapeMode.Line, ShapeMode.Arrow, ShapeMode.Triangle, ShapeMode.Rectangle, ShapeMode.Circle, ShapeMode.Cube, ShapeMode.Cylinder };

            for (int i = 0; i < btns.Length; i++)
            {
                if (btns[i] == null) continue;
                bool isMe = (modes[i] == mode);
                btns[i].Background = isMe ? new SolidColorBrush(Color.FromArgb(46, 0, 245, 212)) : Brushes.Transparent;
                btns[i].BorderBrush = isMe ? new SolidColorBrush(activeColor) : Brushes.Transparent;
                ((TextBlock)btns[i].Child).Foreground = isMe ? new SolidColorBrush(activeColor) : new SolidColorBrush(normalColor);
            }

            SetShapeDrawMode();
        }

        private void SetDrawMode(bool isDraw)
        {
            var activeColor = Color.FromRgb(0, 245, 212);
            var normalColor = Color.FromRgb(220, 220, 220);

            if (isDraw)
            {
                if (_isDrawMode && _inkCanvas.EditingMode == InkCanvasEditingMode.Ink && _activeShapeMode == ShapeMode.None)
                {
                    if (_penDetailsCard != null)
                        _penDetailsCard.Visibility = (_penDetailsCard.Visibility == Visibility.Visible) ? Visibility.Collapsed : Visibility.Visible;
                    if (_eraserDetailsCard != null) _eraserDetailsCard.Visibility = Visibility.Collapsed;
                    if (_shapeDetailsCard != null) _shapeDetailsCard.Visibility = Visibility.Collapsed;
                    if (_jumpBorder != null) _jumpBorder.Visibility = Visibility.Collapsed;
                    return;
                }

                _isDrawMode = true;
                _activeShapeMode = ShapeMode.None;
                if (_penDetailsCard != null) _penDetailsCard.Visibility = Visibility.Visible;
                if (_eraserDetailsCard != null) _eraserDetailsCard.Visibility = Visibility.Collapsed;
                if (_shapeDetailsCard != null) _shapeDetailsCard.Visibility = Visibility.Collapsed;
                if (_jumpBorder != null) _jumpBorder.Visibility = Visibility.Collapsed;

                this.Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
                _inkCanvas.EditingMode = InkCanvasEditingMode.Ink;

                UpdateToolButtonsHighlight(_btnPen);
            }
            else
            {
                _isDrawMode = false;
                _activeShapeMode = ShapeMode.None;
                if (_penDetailsCard != null) _penDetailsCard.Visibility = Visibility.Collapsed;
                if (_eraserDetailsCard != null) _eraserDetailsCard.Visibility = Visibility.Collapsed;
                if (_shapeDetailsCard != null) _shapeDetailsCard.Visibility = Visibility.Collapsed;
                if (_jumpBorder != null) _jumpBorder.Visibility = Visibility.Collapsed;

                this.Background = Brushes.Transparent;
                _inkCanvas.EditingMode = InkCanvasEditingMode.None;

                UpdateToolButtonsHighlight(_btnInteract);
            }
        }

        private void SetEraserMode()
        {
            var activeColor = Color.FromRgb(0, 245, 212);
            var normalColor = Color.FromRgb(220, 220, 220);

            if (_inkCanvas.EditingMode == InkCanvasEditingMode.EraseByStroke || _inkCanvas.EditingMode == InkCanvasEditingMode.EraseByPoint)
            {
                if (_eraserDetailsCard != null)
                    _eraserDetailsCard.Visibility = (_eraserDetailsCard.Visibility == Visibility.Visible) ? Visibility.Collapsed : Visibility.Visible;
                if (_penDetailsCard != null) _penDetailsCard.Visibility = Visibility.Collapsed;
                if (_shapeDetailsCard != null) _shapeDetailsCard.Visibility = Visibility.Collapsed;
                if (_jumpBorder != null) _jumpBorder.Visibility = Visibility.Collapsed;
                return;
            }

            _isDrawMode = true;
            _activeShapeMode = ShapeMode.None;
            this.Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));

            bool isPoint = (_btnPointEraser != null && _btnPointEraser.Background != Brushes.Transparent);
            _inkCanvas.EditingMode = isPoint ? InkCanvasEditingMode.EraseByPoint : InkCanvasEditingMode.EraseByStroke;

            if (_eraserDetailsCard != null) _eraserDetailsCard.Visibility = Visibility.Visible;
            if (_penDetailsCard != null) _penDetailsCard.Visibility = Visibility.Collapsed;
            if (_shapeDetailsCard != null) _shapeDetailsCard.Visibility = Visibility.Collapsed;
            if (_jumpBorder != null) _jumpBorder.Visibility = Visibility.Collapsed;

            UpdateToolButtonsHighlight(_btnEraser);
        }

        private void SetShapeDrawMode()
        {
            if (_activeShapeMode == ShapeMode.None)
            {
                _activeShapeMode = ShapeMode.Line;
            }

            if (_btnShape != null && _btnShape.Background != Brushes.Transparent && _shapeDetailsCard.Visibility == Visibility.Collapsed)
            {
                _shapeDetailsCard.Visibility = Visibility.Visible;
                if (_penDetailsCard != null) _penDetailsCard.Visibility = Visibility.Collapsed;
                if (_eraserDetailsCard != null) _eraserDetailsCard.Visibility = Visibility.Collapsed;
                if (_jumpBorder != null) _jumpBorder.Visibility = Visibility.Collapsed;
                return;
            }

            _isDrawMode = true;
            this.Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
            _inkCanvas.EditingMode = InkCanvasEditingMode.None; // Intercept manually!

            if (_shapeDetailsCard != null) _shapeDetailsCard.Visibility = Visibility.Visible;
            if (_penDetailsCard != null) _penDetailsCard.Visibility = Visibility.Collapsed;
            if (_eraserDetailsCard != null) _eraserDetailsCard.Visibility = Visibility.Collapsed;
            if (_jumpBorder != null) _jumpBorder.Visibility = Visibility.Collapsed;

            UpdateToolButtonsHighlight(_btnShape);
        }

        private void UpdateToolButtonsHighlight(Border activeBtn)
        {
            var activeColor = Color.FromRgb(0, 245, 212);
            var normalColor = Color.FromRgb(220, 220, 220);

            Border[] btns = { _btnPen, _btnEraser, _btnShape, _btnInteract };
            foreach (var btn in btns)
            {
                if (btn == null) continue;
                bool isMe = (btn == activeBtn);
                btn.Background = isMe ? new SolidColorBrush(Color.FromArgb(46, 0, 245, 212)) : Brushes.Transparent;
                btn.BorderBrush = isMe ? new SolidColorBrush(activeColor) : Brushes.Transparent;
                ((TextBlock)btn.Child).Foreground = isMe ? new SolidColorBrush(activeColor) : new SolidColorBrush(normalColor);
            }
        }

        private void SetPenThickness(double w)
        {
            _inkCanvas.DefaultDrawingAttributes.Width = w;
            _inkCanvas.DefaultDrawingAttributes.Height = w;
        }

        private Border CreateColorButton(Color color)
        {
            Border circle = new Border { Width = 20, Height = 20, CornerRadius = new CornerRadius(10), Background = new SolidColorBrush(color), BorderBrush = new SolidColorBrush(Color.FromArgb(120, 255, 255, 255)), BorderThickness = new Thickness(1.5) };
            Border btn = new Border { Background = Brushes.Transparent, CornerRadius = new CornerRadius(14), Width = 28, Height = 28, Margin = new Thickness(4, 2, 4, 2), Cursor = Cursors.Hand, Child = circle };
            btn.MouseDown += (s, e) => SetPenColor(color);
            btn.MouseEnter += (s, e) => { btn.Background = new SolidColorBrush(Color.FromArgb(46, 0, 245, 212)); circle.BorderBrush = new SolidColorBrush(Color.FromRgb(0, 245, 212)); };
            btn.MouseLeave += (s, e) => { btn.Background = Brushes.Transparent; circle.BorderBrush = new SolidColorBrush(Color.FromArgb(120, 255, 255, 255)); };
            return btn;
        }

        private void SetPenColor(Color color)
        {
            _inkCanvas.DefaultDrawingAttributes.Color = color;
            SetDrawMode(true);
        }

        private Separator CreateSeparator()
        {
            return new Separator { Background = new SolidColorBrush(Color.FromArgb(20, 255, 255, 255)), Width = 1, Height = 20, Margin = new Thickness(6, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center };
        }

        private void UpdateEraserButtonsState(bool stroke)
        {
            var activeColor = Color.FromRgb(0, 245, 212);
            var normalColor = Color.FromRgb(220, 220, 220);
            if (_btnStrokeEraser != null) { _btnStrokeEraser.Background = stroke ? new SolidColorBrush(Color.FromArgb(46, 0, 245, 212)) : Brushes.Transparent; _btnStrokeEraser.BorderBrush = stroke ? new SolidColorBrush(activeColor) : Brushes.Transparent; ((TextBlock)_btnStrokeEraser.Child).Foreground = new SolidColorBrush(stroke ? activeColor : normalColor); }
            if (_btnPointEraser != null) { _btnPointEraser.Background = !stroke ? new SolidColorBrush(Color.FromArgb(46, 0, 245, 212)) : Brushes.Transparent; _btnPointEraser.BorderBrush = !stroke ? new SolidColorBrush(activeColor) : Brushes.Transparent; ((TextBlock)_btnPointEraser.Child).Foreground = new SolidColorBrush(!stroke ? activeColor : normalColor); }
        }

        private void HideFloatingCards()
        {
            if (_penDetailsCard != null) _penDetailsCard.Visibility = Visibility.Collapsed;
            if (_eraserDetailsCard != null) _eraserDetailsCard.Visibility = Visibility.Collapsed;
            if (_shapeDetailsCard != null) _shapeDetailsCard.Visibility = Visibility.Collapsed;
            if (_jumpBorder != null) _jumpBorder.Visibility = Visibility.Collapsed;
        }

        private void UndoLastStroke()
        {
            if (_inkCanvas.Strokes.Count > 0)
            {
                _inkCanvas.Strokes.RemoveAt(_inkCanvas.Strokes.Count - 1);
            }
        }

        private void ClearCanvas()
        {
            _inkCanvas.Strokes.Clear();
            SaveStrokesToStorage(_lastSlideIndex);
        }

        private void HandleTurnOffOverlay()
        {
            _onlyTurnOffOverlay = true;
            this.Close();
        }

        private void PageLabel_MouseDown(object sender, MouseButtonEventArgs e)
        {
            _jumpBorder.Visibility = (_jumpBorder.Visibility == Visibility.Visible) ? Visibility.Collapsed : Visibility.Visible;
            if (_jumpBorder.Visibility == Visibility.Visible)
            {
                PopulateSlideButtons();
            }
        }

        private void PopulateSlideButtons()
        {
            if (_jumpWrapPanel == null) return;
            _jumpWrapPanel.Children.Clear();
            for (int i = 1; i <= _slideCount; i++)
            {
                int slideNum = i;
                Button btn = new Button { Content = slideNum.ToString(), Width = 42, Height = 42, Margin = new Thickness(4), FontWeight = FontWeights.Bold, FontSize = 13, BorderThickness = new Thickness(1.2), BorderBrush = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)) };
                if (slideNum == _lastSlideIndex)
                {
                    btn.Background = new SolidColorBrush(Color.FromArgb(255, 0, 245, 212));
                    btn.Foreground = Brushes.Black;
                    btn.BorderBrush = new SolidColorBrush(Color.FromArgb(255, 0, 245, 212));
                }
                else
                {
                    btn.Background = new SolidColorBrush(Color.FromArgb(30, 255, 255, 255));
                    btn.Foreground = Brushes.White;
                }
                btn.Click += (s, e) => { _jumpBorder.Visibility = Visibility.Collapsed; JumpToSlide(slideNum); };
                _jumpWrapPanel.Children.Add(btn);
            }
        }

        private void ExecuteTextBoxJump(string text)
        {
            int pageNum;
            if (int.TryParse(text.Trim(), out pageNum))
            {
                if (pageNum >= 1 && pageNum <= _slideCount) { _jumpBorder.Visibility = Visibility.Collapsed; JumpToSlide(pageNum); }
                else { MessageBox.Show(string.Format("1부터 {0} 사이의 쪽수를 입력하세요.", _slideCount), "알림", MessageBoxButton.OK, MessageBoxImage.Warning); }
            }
            else { MessageBox.Show("올바른 숫자를 입력하세요.", "알림", MessageBoxButton.OK, MessageBoxImage.Warning); }
        }

        // Shape Drawing Mouse Interception
        private void InkCanvas_PreviewMouseDown(object sender, MouseButtonEventArgs e)
        {
            HideFloatingCards();
            if (_activeShapeMode != ShapeMode.None)
            {
                _shapeStartPoint = e.GetPosition(_inkCanvas);
                _tempShapeStroke = null;
                e.Handled = true;
            }
        }

        private void InkCanvas_PreviewMouseMove(object sender, MouseEventArgs e)
        {
            if (_shapeStartPoint != null && e.LeftButton == MouseButtonState.Pressed)
            {
                Point currentPoint = e.GetPosition(_inkCanvas);

                if (_tempShapeStroke != null)
                {
                    _inkCanvas.Strokes.Remove(_tempShapeStroke);
                }

                StylusPointCollection pts = GenerateShapePoints(_activeShapeMode, _shapeStartPoint.Value, currentPoint);
                if (pts.Count > 0)
                {
                    _tempShapeStroke = new Stroke(pts, _inkCanvas.DefaultDrawingAttributes.Clone());
                    _inkCanvas.Strokes.Add(_tempShapeStroke);
                }
                e.Handled = true;
            }
        }

        private void InkCanvas_PreviewMouseUp(object sender, MouseButtonEventArgs e)
        {
            if (_shapeStartPoint != null)
            {
                Point currentPoint = e.GetPosition(_inkCanvas);

                if (_tempShapeStroke != null)
                {
                    _inkCanvas.Strokes.Remove(_tempShapeStroke);
                }

                StylusPointCollection pts = GenerateShapePoints(_activeShapeMode, _shapeStartPoint.Value, currentPoint);
                if (pts.Count > 0)
                {
                    Stroke finalStroke = new Stroke(pts, _inkCanvas.DefaultDrawingAttributes.Clone());
                    _inkCanvas.Strokes.Add(finalStroke);
                }

                _shapeStartPoint = null;
                _tempShapeStroke = null;
                e.Handled = true;
            }
        }

        // Touch Gesture Handling
        private void InkCanvas_PreviewTouchDown(object sender, TouchEventArgs e)
        {
            HideFloatingCards();
            var point = e.GetTouchPoint(this).Position;
            _activeTouchPoints[e.TouchDevice.Id] = point;
            _gestureDetected = false;

            if (_activeTouchPoints.Count >= 2)
            {
                _inkCanvas.EditingMode = InkCanvasEditingMode.None;
            }
        }

        private void InkCanvas_TouchUp(object sender, TouchEventArgs e)
        {
            _activeTouchPoints.Remove(e.TouchDevice.Id);
            if (_isDrawMode && _inkCanvas.EditingMode == InkCanvasEditingMode.None)
            {
                _inkCanvas.EditingMode = (_activeShapeMode == ShapeMode.None) ? InkCanvasEditingMode.Ink : InkCanvasEditingMode.None;
            }
        }

        protected override void OnTouchMove(TouchEventArgs e)
        {
            base.OnTouchMove(e);
            if (_gestureDetected) return;

            if (_activeTouchPoints.ContainsKey(e.TouchDevice.Id))
            {
                var startPoint = _activeTouchPoints[e.TouchDevice.Id];
                var currentPoint = e.GetTouchPoint(this).Position;

                if (_activeTouchPoints.Count == 2)
                {
                    double dx = currentPoint.X - startPoint.X;
                    double dy = currentPoint.Y - startPoint.Y;

                    // Left to Right -> Previous slide
                    if (dx > 120 && Math.Abs(dy) < 80)
                    {
                        _gestureDetected = true;
                        HandlePrevious();
                        e.Handled = true;
                    }
                    // Right to Left -> Next slide
                    else if (dx < -120 && Math.Abs(dy) < 80)
                    {
                        _gestureDetected = true;
                        HandleNext();
                        e.Handled = true;
                    }
                    // Top to Bottom -> Close slideshow + overlay
                    else if (dy > 150 && Math.Abs(dx) < 80)
                    {
                        _gestureDetected = true;
                        this.Close();
                        e.Handled = true;
                    }
                }
            }
        }

        // Shape Generation Method
        private StylusPointCollection GenerateShapePoints(ShapeMode shape, Point start, Point end)
        {
            StylusPointCollection pts = new StylusPointCollection();
            double dx = end.X - start.X;
            double dy = end.Y - start.Y;

            if (shape == ShapeMode.Line)
            {
                pts.Add(new StylusPoint(start.X, start.Y));
                pts.Add(new StylusPoint(end.X, end.Y));
            }
            else if (shape == ShapeMode.Arrow)
            {
                pts.Add(new StylusPoint(start.X, start.Y));
                pts.Add(new StylusPoint(end.X, end.Y));

                double angle = Math.Atan2(dy, dx);
                double arrowLength = 15;
                double arrowAngle = Math.PI / 6;

                double x1 = end.X - arrowLength * Math.Cos(angle - arrowAngle);
                double y1 = end.Y - arrowLength * Math.Sin(angle - arrowAngle);
                double x2 = end.X - arrowLength * Math.Cos(angle + arrowAngle);
                double y2 = end.Y - arrowLength * Math.Sin(angle + arrowAngle);

                pts.Add(new StylusPoint(x1, y1));
                pts.Add(new StylusPoint(end.X, end.Y));
                pts.Add(new StylusPoint(x2, y2));
            }
            else if (shape == ShapeMode.Triangle)
            {
                pts.Add(new StylusPoint((start.X + end.X) / 2, start.Y));
                pts.Add(new StylusPoint(start.X, end.Y));
                pts.Add(new StylusPoint(end.X, end.Y));
                pts.Add(new StylusPoint((start.X + end.X) / 2, start.Y));
            }
            else if (shape == ShapeMode.Rectangle)
            {
                pts.Add(new StylusPoint(start.X, start.Y));
                pts.Add(new StylusPoint(end.X, start.Y));
                pts.Add(new StylusPoint(end.X, end.Y));
                pts.Add(new StylusPoint(start.X, end.Y));
                pts.Add(new StylusPoint(start.X, start.Y));
            }
            else if (shape == ShapeMode.Circle)
            {
                double cx = start.X;
                double cy = start.Y;
                double r = Math.Sqrt(dx * dx + dy * dy);
                for (int i = 0; i <= 360; i += 10)
                {
                    double rad = i * Math.PI / 180.0;
                    pts.Add(new StylusPoint(cx + r * Math.Cos(rad), cy + r * Math.Sin(rad)));
                }
            }
            else if (shape == ShapeMode.Cube)
            {
                double ox = dx * 0.3;
                double oy = -dy * 0.3;

                Point p0 = start;
                Point p1 = new Point(start.X + dx * 0.7, start.Y);
                Point p2 = new Point(start.X + dx * 0.7, start.Y + dy * 0.7);
                Point p3 = new Point(start.X, start.Y + dy * 0.7);

                Point q0 = new Point(p0.X + ox, p0.Y + oy);
                Point q1 = new Point(p1.X + ox, p1.Y + oy);
                Point q2 = new Point(p2.X + ox, p2.Y + oy);
                Point q3 = new Point(p3.X + ox, p3.Y + oy);

                pts.Add(new StylusPoint(p0.X, p0.Y));
                pts.Add(new StylusPoint(p1.X, p1.Y));
                pts.Add(new StylusPoint(p2.X, p2.Y));
                pts.Add(new StylusPoint(p3.X, p3.Y));
                pts.Add(new StylusPoint(p0.X, p0.Y));

                pts.Add(new StylusPoint(q0.X, q0.Y));
                pts.Add(new StylusPoint(q1.X, q1.Y));
                pts.Add(new StylusPoint(q2.X, q2.Y));
                pts.Add(new StylusPoint(q3.X, q3.Y));
                pts.Add(new StylusPoint(q0.X, q0.Y));

                pts.Add(new StylusPoint(q1.X, q1.Y));
                pts.Add(new StylusPoint(p1.X, p1.Y));
                pts.Add(new StylusPoint(p2.X, p2.Y));
                pts.Add(new StylusPoint(q2.X, q2.Y));
                pts.Add(new StylusPoint(q3.X, q3.Y));
                pts.Add(new StylusPoint(p3.X, p3.Y));
                pts.Add(new StylusPoint(p0.X, p0.Y));
                pts.Add(new StylusPoint(q0.X, q0.Y));
            }
            else if (shape == ShapeMode.Cylinder)
            {
                double w = Math.Abs(dx);
                double h = Math.Abs(dy);
                double rx = w / 2;
                double ry = h * 0.15;
                double cx = (start.X + end.X) / 2;

                Point topCenter = new Point(cx, start.Y + ry);
                Point bottomCenter = new Point(cx, end.Y - ry);

                for (int i = 0; i <= 360; i += 10)
                {
                    double rad = i * Math.PI / 180.0;
                    pts.Add(new StylusPoint(topCenter.X + rx * Math.Cos(rad), topCenter.Y + ry * Math.Sin(rad)));
                }

                pts.Add(new StylusPoint(bottomCenter.X + rx, bottomCenter.Y));

                for (int i = 0; i <= 360; i += 10)
                {
                    double rad = i * Math.PI / 180.0;
                    pts.Add(new StylusPoint(bottomCenter.X + rx * Math.Cos(rad), bottomCenter.Y + ry * Math.Sin(rad)));
                }

                pts.Add(new StylusPoint(topCenter.X - rx, topCenter.Y));
            }

            return pts;
        }

        // PowerPoint COM Automation details
        private void OverlayWindow_Loaded(object sender, RoutedEventArgs e)
        {
            try
            {
                Type pptType = Type.GetTypeFromProgID("PowerPoint.Application");
                if (pptType == null)
                {
                    MessageBox.Show("Microsoft PowerPoint is not installed on this system.", "Error", MessageBoxButton.OK, MessageBoxImage.Error);
                    this.Close();
                    return;
                }

                try
                {
                    _pptApp = Marshal.GetActiveObject("PowerPoint.Application");
                }
                catch
                {
                    _pptApp = Activator.CreateInstance(pptType);
                    _pptApp.Visible = 1;
                }

                try
                {
                    int pptHwnd = _pptApp.HWND;
                    if (pptHwnd != 0)
                    {
                        uint pid;
                        GetWindowThreadProcessId((IntPtr)pptHwnd, out pid);
                        _pptPid = pid;
                    }
                }
                catch {}

                dynamic presentations = _pptApp.Presentations;
                bool isLoaded = false;

                if (presentations.Count > 0)
                {
                    for (int i = 1; i <= presentations.Count; i++)
                    {
                        dynamic pres = presentations.Item(i);
                        if (Path.GetFullPath(pres.FullName).ToLower() == _pptPath.ToLower())
                        {
                            _presentation = pres;
                            isLoaded = true;
                            break;
                        }
                    }
                }

                if (!isLoaded)
                {
                    _presentation = presentations.Open(_pptPath, WithWindow: 1);
                }

                dynamic slideShowSettings = _presentation.SlideShowSettings;
                dynamic slideShowWindow;
                try
                {
                    slideShowWindow = slideShowSettings.Run();
                }
                catch
                {
                    slideShowWindow = _pptApp.SlideShowWindows.Item(1);
                }

                _slideShowView = slideShowWindow.View;

                int totalSlides = _presentation.Slides.Count;
                _slideCount = totalSlides;
                if (_startPage > 1 && _startPage <= totalSlides)
                {
                    _slideShowView.GotoSlide(_startPage);
                }

                _lastSlideIndex = _slideShowView.CurrentShowPosition;

                LoadStrokesFromStorage(_lastSlideIndex);
                PopulateSlideButtons();
                UpdatePageIndicator(_lastSlideIndex, totalSlides);

                _pollTimer = new DispatcherTimer();
                _pollTimer.Interval = TimeSpan.FromMilliseconds(100);
                _pollTimer.Tick += PollTimer_Tick;
                _pollTimer.Start();
            }
            catch (Exception ex)
            {
                MessageBox.Show(string.Format("Failed to connect to PowerPoint: {0}", ex.Message), "Connection Failure", MessageBoxButton.OK, MessageBoxImage.Error);
                this.Close();
            }
        }

        private void PollTimer_Tick(object sender, EventArgs e)
        {
            try
            {
                int currentSlideIdx = _slideShowView.CurrentShowPosition;
                if (currentSlideIdx != _lastSlideIndex)
                {
                    SaveStrokesToStorage(_lastSlideIndex);
                    _lastSlideIndex = currentSlideIdx;
                    _inkCanvas.Strokes.Clear();
                    LoadStrokesFromStorage(_lastSlideIndex);
                    int totalSlides = _presentation.Slides.Count;
                    UpdatePageIndicator(_lastSlideIndex, totalSlides);
                }
            }
            catch
            {
                this.Close();
            }
        }

        private void UpdatePageIndicator(int current, int total)
        {
            if (_pageLabel != null)
                _pageLabel.Text = current + " / " + total + " 쪽";
            
            Console.WriteLine("PAGE_UPDATE:" + (current - 1) + "," + total);
            SaveStateToAppData(current, total);
        }

        private void HandleNext()
        {
            try
            {
                int pageBefore = _slideShowView.CurrentShowPosition;
                int currentClick = _slideShowView.GetClickIndex();
                int totalClicks = _slideShowView.GetClickCount();

                _slideShowView.Next();

                int pageAfter = _slideShowView.CurrentShowPosition;

                if (pageBefore != pageAfter)
                {
                    SaveStrokesToStorage(pageBefore);
                    _lastSlideIndex = pageAfter;
                    _inkCanvas.Strokes.Clear();
                    LoadStrokesFromStorage(pageAfter);
                    int total = _presentation.Slides.Count;
                    UpdatePageIndicator(pageAfter, total);
                }
                else
                {
                    int total = _presentation.Slides.Count;
                    if (pageBefore >= total && currentClick >= totalClicks)
                    {
                        SaveStrokesToStorage(pageBefore);
                        Console.WriteLine("LAST_SLIDE_NEXT:" + _pptPath);
                        this.Close();
                    }
                }
            }
            catch
            {
                this.Close();
            }
        }

        private void HandlePrevious()
        {
            try
            {
                int pageBefore = _slideShowView.CurrentShowPosition;
                _slideShowView.Previous();
                int pageAfter = _slideShowView.CurrentShowPosition;

                if (pageBefore != pageAfter)
                {
                    SaveStrokesToStorage(pageBefore);
                    _lastSlideIndex = pageAfter;
                    _inkCanvas.Strokes.Clear();
                    LoadStrokesFromStorage(pageAfter);
                    int total = _presentation.Slides.Count;
                    UpdatePageIndicator(pageAfter, total);
                }
            }
            catch {}
        }

        private void JumpToSlide(int slideIndex)
        {
            try
            {
                int pageBefore = _slideShowView.CurrentShowPosition;
                _slideShowView.GotoSlide(slideIndex);
                int pageAfter = _slideShowView.CurrentShowPosition;

                if (pageBefore != pageAfter)
                {
                    SaveStrokesToStorage(pageBefore);
                    _lastSlideIndex = pageAfter;
                    _inkCanvas.Strokes.Clear();
                    LoadStrokesFromStorage(pageAfter);
                    int total = _presentation.Slides.Count;
                    UpdatePageIndicator(pageAfter, total);
                }
            }
            catch {}
        }

        private void OverlayWindow_Closed(object sender, EventArgs e)
        {
            if (_pollTimer != null) _pollTimer.Stop();

            if (_lastSlideIndex != -1)
            {
                SaveStrokesToStorage(_lastSlideIndex);
                Console.WriteLine("LAST_PAGE:" + (_lastSlideIndex - 1));
            }

            if (_onlyTurnOffOverlay)
            {
                try
                {
                    if (_slideShowView != null)
                    {
                        _slideShowView.Exit(); // Exit slide show to PPT edit screen!
                    }
                }
                catch {}
            }
            else
            {
                try
                {
                    if (_slideShowView != null) _slideShowView.Exit();
                }
                catch {}
                try
                {
                    if (_presentation != null)
                    {
                        _presentation.Saved = true;
                        _presentation.Close();
                    }
                }
                catch {}
                try
                {
                    if (_pptApp != null) _pptApp.Quit();
                }
                catch {}
                try
                {
                    if (_pptPid != 0)
                    {
                        System.Diagnostics.Process proc = System.Diagnostics.Process.GetProcessById((int)_pptPid);
                        if (proc != null && !proc.HasExited) proc.Kill();
                    }
                }
                catch {}
            }

            try { if (_slideShowView != null) Marshal.ReleaseComObject(_slideShowView); } catch {}
            try { if (_presentation != null) Marshal.ReleaseComObject(_presentation); } catch {}
            try { if (_pptApp != null) Marshal.ReleaseComObject(_pptApp); } catch {}

            _slideShowView = null;
            _presentation = null;
            _pptApp = null;
        }

        // Strokes storage helpers
        private string GetPPTStrokesFilePath()
        {
            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            string pptDir = Path.Combine(appData, "BstSave", "PPT");
            if (!Directory.Exists(pptDir)) Directory.CreateDirectory(pptDir);
            string sanitized = Regex.Replace(_fileName, @"[\\/:*?""<>| ]", "_");
            return Path.Combine(pptDir, sanitized + ".iwb");
        }

        private string GetPPTMetadataFilePath()
        {
            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            string pptDir = Path.Combine(appData, "BstSave", "PPT");
            if (!Directory.Exists(pptDir)) Directory.CreateDirectory(pptDir);
            string sanitized = Regex.Replace(_fileName, @"[\\/:*?""<>| ]", "_");
            return Path.Combine(pptDir, sanitized + ".json");
        }

        private void SavePPTMetadata(int slide0Based)
        {
            try
            {
                string metadataFile = GetPPTMetadataFilePath();
                string timestamp = DateTime.Now.ToString("yyyy-MM-ddTHH:mm:ss.fffZ");
                string escapedFileName = _fileName.Replace("\\", "\\\\").Replace("\"", "\\\"");
                string json = string.Format(
                    "{{\"filePath\":\"{0}\",\"fileName\":\"{1}\",\"type\":\"ppt\",\"lastPage\":{2},\"totalPages\":{3},\"lastOpened\":\"{4}\"}}",
                    escapedFileName, escapedFileName, slide0Based, _slideCount, timestamp
                );
                File.WriteAllText(metadataFile, json, Encoding.UTF8);
            }
            catch {}
        }

        private void SaveStateToAppData(int current, int total)
        {
            SavePPTMetadata(current - 1);
        }

        private int LoadStateFromAppData()
        {
            try
            {
                string metadataFile = GetPPTMetadataFilePath();
                if (File.Exists(metadataFile))
                {
                    string json = File.ReadAllText(metadataFile, Encoding.UTF8);
                    var match = Regex.Match(json, @"""lastPage""\s*:\s*(\d+)");
                    if (match.Success)
                    {
                        return int.Parse(match.Groups[1].Value) + 1;
                    }
                }
            }
            catch {}
            return 1;
        }

        private Dictionary<string, string> ParseIwbPages(string filePath)
        {
            var dict = new Dictionary<string, string>();
            if (!File.Exists(filePath)) return dict;
            try
            {
                string content = File.ReadAllText(filePath, Encoding.UTF8);
                int pagesStartIndex = content.IndexOf("\"pages\"");
                if (pagesStartIndex == -1) return dict;

                var matches = Regex.Matches(content, @"""(\d+)""\s*:\s*\[");
                foreach (Match m in matches)
                {
                    string pageKey = m.Groups[1].Value;
                    int startOfArray = content.IndexOf("[", m.Index);
                    if (startOfArray == -1) continue;

                    int bracketDepth = 0;
                    int endOfArray = -1;
                    for (int i = startOfArray; i < content.Length; i++)
                    {
                        if (content[i] == '[') bracketDepth++;
                        else if (content[i] == ']')
                        {
                            bracketDepth--;
                            if (bracketDepth == 0) { endOfArray = i; break; }
                        }
                    }
                    if (endOfArray != -1)
                    {
                        dict[pageKey] = content.Substring(startOfArray, endOfArray - startOfArray + 1);
                    }
                }
            }
            catch {}
            return dict;
        }

        private void WriteIwbFile(string filePath, Dictionary<string, string> pagesDict)
        {
            try
            {
                StringBuilder sb = new StringBuilder();
                sb.Append("{\"version\":1,\"totalPages\":").Append(_slideCount).Append(",\"pages\":{");
                bool first = true;
                foreach (var kvp in pagesDict)
                {
                    if (!first) sb.Append(",");
                    first = false;
                    sb.Append("\"").Append(kvp.Key).Append("\":").Append(kvp.Value);
                }
                sb.Append("}}");
                File.WriteAllText(filePath, sb.ToString(), Encoding.UTF8);
            }
            catch {}
        }

        private void SaveStrokesToStorage(int slideIndex)
        {
            if (slideIndex <= 0) return;
            string iwbPath = GetPPTStrokesFilePath();

            try
            {
                StringBuilder sb = new StringBuilder();
                sb.Append("[");
                bool firstStroke = true;
                foreach (Stroke stroke in _inkCanvas.Strokes)
                {
                    if (!firstStroke) sb.Append(",");
                    firstStroke = false;

                    sb.Append("{");
                    sb.Append("\"points\":[");
                    bool firstPt = true;
                    foreach (var pt in stroke.StylusPoints)
                    {
                        if (!firstPt) sb.Append(",");
                        firstPt = false;
                        sb.Append("{\"dx\":").Append(pt.X.ToString("F1")).Append(",\"dy\":").Append(pt.Y.ToString("F1")).Append("}");
                    }
                    sb.Append("],");

                    uint argbVal = ((uint)stroke.DrawingAttributes.Color.A << 24) |
                                  ((uint)stroke.DrawingAttributes.Color.R << 16) |
                                  ((uint)stroke.DrawingAttributes.Color.G << 8) |
                                  (uint)stroke.DrawingAttributes.Color.B;

                    sb.Append("\"color\":").Append(argbVal).Append(",");
                    sb.Append("\"strokeWidth\":").Append(stroke.DrawingAttributes.Width.ToString("F1")).Append(",");
                    sb.Append("\"isEraser\":false");
                    sb.Append("}");
                }
                sb.Append("]");

                string slideKey = (slideIndex - 1).ToString();
                var pagesDict = ParseIwbPages(iwbPath);
                pagesDict[slideKey] = sb.ToString();

                WriteIwbFile(iwbPath, pagesDict);
                SavePPTMetadata(slideIndex - 1);
            }
            catch {}
        }

        private void LoadStrokesFromStorage(int slideIndex)
        {
            if (slideIndex <= 0) return;
            string iwbPath = GetPPTStrokesFilePath();
            if (!File.Exists(iwbPath)) return;

            try
            {
                string slideKey = (slideIndex - 1).ToString();
                var pagesDict = ParseIwbPages(iwbPath);
                if (!pagesDict.ContainsKey(slideKey)) return;

                string json = pagesDict[slideKey];
                var strokeMatches = Regex.Matches(json, @"\{""points"":\[(.*?)\]\s*,\s*""color"":(\d+)\s*,\s*""strokeWidth"":([\d\.]+)\s*,\s*""isEraser"":(true|false)\}");
                foreach (Match match in strokeMatches)
                {
                    string ptsGroup = match.Groups[1].Value;
                    uint colorVal = uint.Parse(match.Groups[2].Value);
                    double width = double.Parse(match.Groups[3].Value);

                    byte a = (byte)((colorVal >> 24) & 0xFF);
                    byte r = (byte)((colorVal >> 16) & 0xFF);
                    byte g = (byte)((colorVal >> 8) & 0xFF);
                    byte b = (byte)(colorVal & 0xFF);

                    var points = new StylusPointCollection();
                    var ptMatches = Regex.Matches(ptsGroup, @"\{""(x|dx)"":([\-\d\.]+),""(y|dy)"":([\-\d\.]+)\}");
                    foreach (Match ptMatch in ptMatches)
                    {
                        double x = double.Parse(ptMatch.Groups[2].Value);
                        double y = double.Parse(ptMatch.Groups[4].Value);
                        points.Add(new StylusPoint(x, y));
                    }

                    if (points.Count > 0)
                    {
                        var attrib = new DrawingAttributes
                        {
                            Color = Color.FromArgb(a, r, g, b),
                            Width = width,
                            Height = width,
                            StylusTip = StylusTip.Ellipse
                        };
                        _inkCanvas.Strokes.Add(new Stroke(points, attrib));
                    }
                }
            }
            catch {}
        }
    }
}
