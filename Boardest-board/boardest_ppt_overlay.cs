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

            // Parse command line arguments: --path <PPT Path> --page <PPT Page>
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

    public class OverlayWindow : Window
    {
        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        private string _pptPath;
        private string _fileName;
        private int _startPage;

        // PowerPoint COM Objects (dynamic)
        private dynamic _pptApp;
        private dynamic _presentation;
        private dynamic _slideShowView;
        private uint _pptPid = 0;

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

        // Interactive control buttons
        private Border _btnInteract;
        private Border _btnPen;
        private Border _btnEraser;
        private Border _btnLasso;
        private Border _btnStrokeEraser;
        private Border _btnPointEraser;
        private bool _isDrawMode = true;

        // Slider thickness
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
        private Color _pinkColor = Color.FromRgb(255, 105, 180);

        public OverlayWindow(string pptPath, int startPage)
        {
            _pptPath = Path.GetFullPath(pptPath);
            _fileName = Path.GetFileName(_pptPath);
            
            // Try loading from appdata if startPage is 1 or less
            if (startPage <= 1)
            {
                _startPage = LoadStateFromAppData();
            }
            else
            {
                _startPage = startPage;
            }

            // 1. Transparent Topmost Fullscreen WPF Window Setup
            this.Title = "Boardest PowerPoint Overlay";
            this.WindowStyle = WindowStyle.None;
            this.AllowsTransparency = true;
            
            // Start in Drawing Mode (invisible background that captures hits)
            this.Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
            
            this.Topmost = true;
            this.ShowInTaskbar = false;

            // Fullscreen positioning on active screen
            this.Left = SystemParameters.VirtualScreenLeft;
            this.Top = SystemParameters.VirtualScreenTop;
            this.Width = SystemParameters.VirtualScreenWidth;
            this.Height = SystemParameters.VirtualScreenHeight;

            // 2. Initialize UI layout
            InitUI();

            // 3. Connect to PowerPoint and Run slideshow
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

            // Hide floating cards automatically when drawing starts
            _inkCanvas.PreviewMouseDown += InkCanvas_PreviewDrawingStart;
            _inkCanvas.PreviewTouchDown += InkCanvas_PreviewDrawingStart;
            _inkCanvas.PreviewStylusDown += InkCanvas_PreviewDrawingStart;

            // ───────────────── Floating Bottom Dock (Capsule Premium Style) ─────────────────
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
                Effect = new System.Windows.Media.Effects.DropShadowEffect
                {
                    Color = Colors.Black,
                    BlurRadius = 16,
                    ShadowDepth = 3,
                    Opacity = 0.5
                }
            };
            Grid.SetRow(toolBorder, 1);

            _toolbar = new StackPanel { Orientation = Orientation.Horizontal };

            // 1. Red Exit/Close button
            Border btnClose = CreateDockButton("❌", (s, e) => this.Close());
            ((TextBlock)btnClose.Child).Foreground = new SolidColorBrush(Color.FromRgb(255, 100, 100));

            Separator sep1 = CreateSeparator();

            // 2. Navigation
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

            // 3. Interactive control buttons (Pen, Eraser, Lasso, Pointer)
            _btnPen = CreateDockButton("✏️", (s, e) => SetDrawMode(true), true);
            _btnEraser = CreateDockButton("🧹", (s, e) => SetEraserMode(), false);
            _btnLasso = CreateDockButton("✨", (s, e) => SetLassoSelectMode(), false);
            _btnInteract = CreateDockButton("🖱️", (s, e) => SetDrawMode(false), false);

            Separator sep3 = CreateSeparator();

            // 4. Action button: Undo
            Border btnUndo = CreateDockButton("↩", (s, e) => UndoLastStroke());

            // Assemble main bottom toolbar in capsule layout
            _toolbar.Children.Add(btnClose);
            _toolbar.Children.Add(sep1);
            _toolbar.Children.Add(btnPrev);
            _toolbar.Children.Add(_pageLabel);
            _toolbar.Children.Add(btnNext);
            _toolbar.Children.Add(sep2);
            _toolbar.Children.Add(_btnPen);
            _toolbar.Children.Add(_btnEraser);
            _toolbar.Children.Add(_btnLasso);
            _toolbar.Children.Add(_btnInteract);
            _toolbar.Children.Add(sep3);
            _toolbar.Children.Add(btnUndo);

            toolBorder.Child = _toolbar;
            _mainGrid.Children.Add(toolBorder);

            // ───────────────── Floating Details Card (Pen Settings) ─────────────────
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
                Margin = new Thickness(190, 0, 0, 12), // Snug fit closely above the pen button
                Visibility = Visibility.Visible, // Pen is default active
                Effect = new System.Windows.Media.Effects.DropShadowEffect
                {
                    Color = Colors.Black,
                    BlurRadius = 15,
                    ShadowDepth = 2,
                    Opacity = 0.5
                }
            };

            StackPanel penCardStack = new StackPanel();

            TextBlock txtColors = new TextBlock
            {
                Text = "펜 색상 설정",
                Foreground = new SolidColorBrush(Color.FromRgb(180, 180, 180)),
                FontWeight = FontWeights.Bold,
                FontSize = 10,
                Margin = new Thickness(0, 0, 0, 6)
            };
            penCardStack.Children.Add(txtColors);

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
            colorWrap.Children.Add(CreateColorButton(_pinkColor));
            penCardStack.Children.Add(colorWrap);

            TextBlock txtThickness = new TextBlock
            {
                Text = "펜 굵기 설정",
                Foreground = new SolidColorBrush(Color.FromRgb(180, 180, 180)),
                FontWeight = FontWeights.Bold,
                FontSize = 10,
                Margin = new Thickness(0, 8, 0, 6)
            };
            penCardStack.Children.Add(txtThickness);

            StackPanel thicknessStack = new StackPanel { Orientation = Orientation.Horizontal };
            _txtThicknessVal = new TextBlock
            {
                Text = "굵기: 4px",
                Foreground = Brushes.White,
                FontSize = 11,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 0, 8, 0)
            };
            _thicknessSlider = new Slider
            {
                Minimum = 1,
                Maximum = 20,
                Value = 4,
                TickFrequency = 1,
                IsSnapToTickEnabled = true,
                Width = 140,
                VerticalAlignment = VerticalAlignment.Center,
                Cursor = Cursors.Hand
            };
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

            // ───────────────── Floating Details Card (Eraser Settings) ─────────────────
            _eraserDetailsCard = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(245, 19, 23, 31)),
                CornerRadius = new CornerRadius(12),
                BorderBrush = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)),
                BorderThickness = new Thickness(1.2),
                Padding = new Thickness(8, 6, 8, 6),
                VerticalAlignment = VerticalAlignment.Bottom,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 0, 0, 12), // Snug fit closely above toolbar
                Visibility = Visibility.Collapsed,
                Effect = new System.Windows.Media.Effects.DropShadowEffect
                {
                    Color = Colors.Black,
                    BlurRadius = 15,
                    ShadowDepth = 2,
                    Opacity = 0.5
                }
            };

            StackPanel eraserCardStack = new StackPanel { Orientation = Orientation.Horizontal };
            TextBlock txtEraser = new TextBlock
            {
                Text = "🧹 지우개 설정",
                Foreground = new SolidColorBrush(Color.FromRgb(180, 180, 180)),
                FontWeight = FontWeights.Bold,
                FontSize = 10,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 0, 8, 0)
            };
            eraserCardStack.Children.Add(txtEraser);
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

            // ───────────────── Floating Slide Page Picker above the Page Label ─────────────────
            _jumpBorder = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(250, 22, 25, 32)), // Dark premium background
                CornerRadius = new CornerRadius(16),
                BorderBrush = new SolidColorBrush(Color.FromArgb(50, 0, 245, 212)), // Teal border highlight
                BorderThickness = new Thickness(1.5),
                Width = 320,
                Height = 260,
                VerticalAlignment = VerticalAlignment.Bottom,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(-180, 0, 0, 84), // Adjusted offset above page label button
                Visibility = Visibility.Collapsed,
                Effect = new System.Windows.Media.Effects.DropShadowEffect
                {
                    Color = Colors.Black,
                    BlurRadius = 20,
                    ShadowDepth = 3,
                    Opacity = 0.6
                }
            };

            Grid jumpGrid = new Grid();
            jumpGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            jumpGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

            // Row 0: TextBox + Jump button
            StackPanel topPanel = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(12, 12, 12, 6) };
            
            TextBlock tbLabel = new TextBlock
            {
                Text = "이동할 쪽수:",
                Foreground = Brushes.White,
                FontWeight = FontWeights.Bold,
                FontSize = 13,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 0, 8, 0)
            };
            
            TextBox jumpInput = new TextBox
            {
                Width = 100,
                Height = 28,
                Background = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)),
                Foreground = Brushes.White,
                BorderBrush = new SolidColorBrush(Color.FromArgb(50, 255, 255, 255)),
                BorderThickness = new Thickness(1),
                VerticalContentAlignment = VerticalAlignment.Center,
                FontWeight = FontWeights.Bold,
                FontSize = 13,
                Padding = new Thickness(6, 0, 6, 0),
                Margin = new Thickness(0, 0, 8, 0)
            };
            
            Button jumpBtn = new Button
            {
                Content = "이동",
                Width = 60,
                Height = 28,
                Background = new SolidColorBrush(Color.FromArgb(255, 0, 245, 212)), // Teal accent
                Foreground = Brushes.Black,
                FontWeight = FontWeights.Bold,
                BorderThickness = new Thickness(0)
            };

            jumpInput.KeyDown += (s, e) =>
            {
                if (e.Key == System.Windows.Input.Key.Enter)
                {
                    ExecuteTextBoxJump(jumpInput.Text);
                }
            };
            jumpBtn.Click += (s, e) =>
            {
                ExecuteTextBoxJump(jumpInput.Text);
            };

            topPanel.Children.Add(tbLabel);
            topPanel.Children.Add(jumpInput);
            topPanel.Children.Add(jumpBtn);
            Grid.SetRow(topPanel, 0);
            jumpGrid.Children.Add(topPanel);

            // Row 1: ScrollViewer + WrapPanel for grid of slide square buttons
            ScrollViewer scrollViewer = new ScrollViewer
            {
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
                Margin = new Thickness(12, 6, 12, 12)
            };
            
            _jumpWrapPanel = new WrapPanel
            {
                Orientation = Orientation.Horizontal
            };

            scrollViewer.Content = _jumpWrapPanel;
            Grid.SetRow(scrollViewer, 1);
            jumpGrid.Children.Add(scrollViewer);

            _jumpBorder.Child = jumpGrid;
            _mainGrid.Children.Add(_jumpBorder);

            this.Content = _mainGrid;
        }

        private Border CreateDockButton(string text, MouseButtonEventHandler clickHandler, bool active = false)
        {
            var activeColor = Color.FromRgb(0, 245, 212); // Premium Teal Highlight
            var normalColor = Color.FromRgb(220, 220, 220); // Off-white

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
                // Simple check using current active state to prevent overriding highlight style
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

        private void SetDrawMode(bool isDraw)
        {
            var activeColor = Color.FromRgb(0, 245, 212);
            var normalColor = Color.FromRgb(220, 220, 220);

            if (isDraw)
            {
                if (_isDrawMode && _inkCanvas.EditingMode == InkCanvasEditingMode.Ink)
                {
                    // Repeat click Pen button: toggle visibility
                    if (_penDetailsCard != null)
                    {
                        _penDetailsCard.Visibility = (_penDetailsCard.Visibility == Visibility.Visible) ? Visibility.Collapsed : Visibility.Visible;
                    }
                    if (_eraserDetailsCard != null) _eraserDetailsCard.Visibility = Visibility.Collapsed;
                    if (_jumpBorder != null) _jumpBorder.Visibility = Visibility.Collapsed;
                    return;
                }

                _isDrawMode = true;
                if (_penDetailsCard != null) _penDetailsCard.Visibility = Visibility.Visible;
                if (_eraserDetailsCard != null) _eraserDetailsCard.Visibility = Visibility.Collapsed;
                if (_jumpBorder != null) _jumpBorder.Visibility = Visibility.Collapsed;

                this.Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
                _inkCanvas.EditingMode = InkCanvasEditingMode.Ink;
                
                if (_btnPen != null)
                {
                    _btnPen.Background = new SolidColorBrush(Color.FromArgb(46, 0, 245, 212));
                    _btnPen.BorderBrush = new SolidColorBrush(activeColor);
                    ((TextBlock)_btnPen.Child).Foreground = new SolidColorBrush(activeColor);
                }
                if (_btnInteract != null)
                {
                    _btnInteract.Background = Brushes.Transparent;
                    _btnInteract.BorderBrush = Brushes.Transparent;
                    ((TextBlock)_btnInteract.Child).Foreground = new SolidColorBrush(normalColor);
                }
                if (_btnEraser != null)
                {
                    _btnEraser.Background = Brushes.Transparent;
                    _btnEraser.BorderBrush = Brushes.Transparent;
                    ((TextBlock)_btnEraser.Child).Foreground = new SolidColorBrush(normalColor);
                }
                if (_btnLasso != null)
                {
                    _btnLasso.Background = Brushes.Transparent;
                    _btnLasso.BorderBrush = Brushes.Transparent;
                    ((TextBlock)_btnLasso.Child).Foreground = new SolidColorBrush(normalColor);
                }
            }
            else
            {
                _isDrawMode = false;
                if (_penDetailsCard != null) _penDetailsCard.Visibility = Visibility.Collapsed;
                if (_eraserDetailsCard != null) _eraserDetailsCard.Visibility = Visibility.Collapsed;
                if (_jumpBorder != null) _jumpBorder.Visibility = Visibility.Collapsed;
                
                this.Background = Brushes.Transparent;
                _inkCanvas.EditingMode = InkCanvasEditingMode.None;
                
                if (_btnPen != null)
                {
                    _btnPen.Background = Brushes.Transparent;
                    _btnPen.BorderBrush = Brushes.Transparent;
                    ((TextBlock)_btnPen.Child).Foreground = new SolidColorBrush(normalColor);
                }
                if (_btnInteract != null)
                {
                    _btnInteract.Background = new SolidColorBrush(Color.FromArgb(46, 0, 245, 212));
                    _btnInteract.BorderBrush = new SolidColorBrush(activeColor);
                    ((TextBlock)_btnInteract.Child).Foreground = new SolidColorBrush(activeColor);
                }
                if (_btnEraser != null)
                {
                    _btnEraser.Background = Brushes.Transparent;
                    _btnEraser.BorderBrush = Brushes.Transparent;
                    ((TextBlock)_btnEraser.Child).Foreground = new SolidColorBrush(normalColor);
                }
                if (_btnLasso != null)
                {
                    _btnLasso.Background = Brushes.Transparent;
                    _btnLasso.BorderBrush = Brushes.Transparent;
                    ((TextBlock)_btnLasso.Child).Foreground = new SolidColorBrush(normalColor);
                }
            }
        }

        private void SetEraserMode()
        {
            var activeColor = Color.FromRgb(0, 245, 212);
            var normalColor = Color.FromRgb(220, 220, 220);

            // Repeat click Eraser button: toggle visibility
            if (_inkCanvas.EditingMode == InkCanvasEditingMode.EraseByStroke || 
                _inkCanvas.EditingMode == InkCanvasEditingMode.EraseByPoint)
            {
                if (_eraserDetailsCard != null)
                {
                    _eraserDetailsCard.Visibility = (_eraserDetailsCard.Visibility == Visibility.Visible) ? Visibility.Collapsed : Visibility.Visible;
                }
                if (_penDetailsCard != null) _penDetailsCard.Visibility = Visibility.Collapsed;
                if (_jumpBorder != null) _jumpBorder.Visibility = Visibility.Collapsed;
                return;
            }

            _isDrawMode = true;
            this.Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
            
            // Restore previous mode based on PointEraser selection state
            bool isPoint = (_btnPointEraser != null && _btnPointEraser.Background != Brushes.Transparent);
            _inkCanvas.EditingMode = isPoint ? InkCanvasEditingMode.EraseByPoint : InkCanvasEditingMode.EraseByStroke;

            if (_eraserDetailsCard != null) _eraserDetailsCard.Visibility = Visibility.Visible;
            if (_penDetailsCard != null) _penDetailsCard.Visibility = Visibility.Collapsed;
            if (_jumpBorder != null) _jumpBorder.Visibility = Visibility.Collapsed;

            if (_btnPen != null)
            {
                _btnPen.Background = Brushes.Transparent;
                _btnPen.BorderBrush = Brushes.Transparent;
                ((TextBlock)_btnPen.Child).Foreground = new SolidColorBrush(normalColor);
            }
            if (_btnInteract != null)
            {
                _btnInteract.Background = Brushes.Transparent;
                _btnInteract.BorderBrush = Brushes.Transparent;
                ((TextBlock)_btnInteract.Child).Foreground = new SolidColorBrush(normalColor);
            }
            if (_btnEraser != null)
            {
                _btnEraser.Background = new SolidColorBrush(Color.FromArgb(46, 0, 245, 212));
                _btnEraser.BorderBrush = new SolidColorBrush(activeColor);
                ((TextBlock)_btnEraser.Child).Foreground = new SolidColorBrush(activeColor);
            }
            if (_btnLasso != null)
            {
                _btnLasso.Background = Brushes.Transparent;
                _btnLasso.BorderBrush = Brushes.Transparent;
                ((TextBlock)_btnLasso.Child).Foreground = new SolidColorBrush(normalColor);
            }
        }

        private void SetLassoSelectMode()
        {
            _isDrawMode = true;
            this.Background = new SolidColorBrush(Color.FromArgb(1, 0, 0, 0));
            _inkCanvas.EditingMode = InkCanvasEditingMode.Select;

            if (_penDetailsCard != null) _penDetailsCard.Visibility = Visibility.Collapsed;
            if (_eraserDetailsCard != null) _eraserDetailsCard.Visibility = Visibility.Collapsed;
            if (_jumpBorder != null) _jumpBorder.Visibility = Visibility.Collapsed;

            var activeColor = Color.FromRgb(0, 245, 212);
            var normalColor = Color.FromRgb(220, 220, 220);

            if (_btnPen != null)
            {
                _btnPen.Background = Brushes.Transparent;
                _btnPen.BorderBrush = Brushes.Transparent;
                ((TextBlock)_btnPen.Child).Foreground = new SolidColorBrush(normalColor);
            }
            if (_btnInteract != null)
            {
                _btnInteract.Background = Brushes.Transparent;
                _btnInteract.BorderBrush = Brushes.Transparent;
                ((TextBlock)_btnInteract.Child).Foreground = new SolidColorBrush(normalColor);
            }
            if (_btnEraser != null)
            {
                _btnEraser.Background = Brushes.Transparent;
                _btnEraser.BorderBrush = Brushes.Transparent;
                ((TextBlock)_btnEraser.Child).Foreground = new SolidColorBrush(normalColor);
            }
            if (_btnLasso != null)
            {
                _btnLasso.Background = new SolidColorBrush(Color.FromArgb(46, 0, 245, 212));
                _btnLasso.BorderBrush = new SolidColorBrush(activeColor);
                ((TextBlock)_btnLasso.Child).Foreground = new SolidColorBrush(activeColor);
            }
        }

        private void SetPenThickness(double w)
        {
            _isDrawMode = true;
            SetDrawMode(true);
            _inkCanvas.EditingMode = InkCanvasEditingMode.Ink;
            _inkCanvas.DefaultDrawingAttributes.Width = w;
            _inkCanvas.DefaultDrawingAttributes.Height = w;
            
            if (_thicknessSlider != null && _thicknessSlider.Value != w)
            {
                _thicknessSlider.Value = w;
            }
            if (_txtThicknessVal != null)
            {
                _txtThicknessVal.Text = string.Format("굵기: {0}px", (int)w);
            }
        }

        private Border CreateColorButton(Color color)
        {
            Border circle = new Border
            {
                Width = 20,
                Height = 20,
                CornerRadius = new CornerRadius(10),
                Background = new SolidColorBrush(color),
                BorderBrush = new SolidColorBrush(Color.FromArgb(120, 255, 255, 255)),
                BorderThickness = new Thickness(1.5),
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center
            };

            Border btn = new Border
            {
                Background = Brushes.Transparent,
                CornerRadius = new CornerRadius(14),
                Width = 28,
                Height = 28,
                Margin = new Thickness(4, 2, 4, 2),
                Cursor = Cursors.Hand,
                VerticalAlignment = VerticalAlignment.Center,
                HorizontalAlignment = HorizontalAlignment.Center,
                Child = circle
            };

            btn.MouseDown += (s, e) => SetPenColor(color);

            btn.MouseEnter += (s, e) => {
                btn.Background = new SolidColorBrush(Color.FromArgb(46, 0, 245, 212)); // Premium Mint highlight on hover
                circle.BorderBrush = new SolidColorBrush(Color.FromRgb(0, 245, 212));
            };
            btn.MouseLeave += (s, e) => {
                btn.Background = Brushes.Transparent;
                circle.BorderBrush = new SolidColorBrush(Color.FromArgb(120, 255, 255, 255));
            };

            return btn;
        }

        private Separator CreateSeparator()
        {
            return new Separator
            {
                Background = new SolidColorBrush(Color.FromArgb(20, 255, 255, 255)),
                Width = 1,
                Height = 20,
                Margin = new Thickness(6, 0, 6, 0),
                VerticalAlignment = VerticalAlignment.Center
            };
        }

        private void PopulateSlideButtons()
        {
            if (_jumpWrapPanel == null) return;
            _jumpWrapPanel.Children.Clear();
            for (int i = 1; i <= _slideCount; i++)
            {
                int slideNum = i;
                Button btn = new Button
                {
                    Content = slideNum.ToString(),
                    Width = 42,
                    Height = 42,
                    Margin = new Thickness(4),
                    FontWeight = FontWeights.Bold,
                    FontSize = 13,
                    BorderThickness = new Thickness(1.2),
                    BorderBrush = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255))
                };

                if (slideNum == _lastSlideIndex)
                {
                    btn.Background = new SolidColorBrush(Color.FromArgb(255, 0, 245, 212)); // Teal active
                    btn.Foreground = Brushes.Black;
                    btn.BorderBrush = new SolidColorBrush(Color.FromArgb(255, 0, 245, 212));
                }
                else
                {
                    btn.Background = new SolidColorBrush(Color.FromArgb(30, 255, 255, 255));
                    btn.Foreground = Brushes.White;
                }

                btn.Click += (s, e) =>
                {
                    _jumpBorder.Visibility = Visibility.Collapsed;
                    JumpToSlide(slideNum);
                };
                _jumpWrapPanel.Children.Add(btn);
            }
        }

        private void ExecuteTextBoxJump(string text)
        {
            int pageNum;
            if (int.TryParse(text.Trim(), out pageNum))
            {
                if (pageNum >= 1 && pageNum <= _slideCount)
                {
                    _jumpBorder.Visibility = Visibility.Collapsed;
                    JumpToSlide(pageNum);
                }
                else
                {
                    MessageBox.Show(string.Format("1부터 {0} 사이의 쪽수를 입력하세요.", _slideCount), "알림", MessageBoxButton.OK, MessageBoxImage.Warning);
                }
            }
            else
            {
                MessageBox.Show("올바른 숫자를 입력하세요.", "알림", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
        }

        private void PageLabel_MouseDown(object sender, MouseButtonEventArgs e)
        {
            _jumpBorder.Visibility = (_jumpBorder.Visibility == Visibility.Visible) ? Visibility.Collapsed : Visibility.Visible;
            if (_jumpBorder.Visibility == Visibility.Visible)
            {
                PopulateSlideButtons();
            }
        }

        private void SetPenColor(Color color)
        {
            _inkCanvas.DefaultDrawingAttributes.Color = color;
            _inkCanvas.DefaultDrawingAttributes.IsHighlighter = false;
            SetDrawMode(true);
        }

        private void UpdateEraserButtonsState(bool stroke)
        {
            var activeColor = Color.FromRgb(0, 245, 212);
            var normalColor = Color.FromRgb(220, 220, 220);
            
            if (_btnStrokeEraser != null)
            {
                _btnStrokeEraser.Background = stroke ? new SolidColorBrush(Color.FromArgb(46, 0, 245, 212)) : Brushes.Transparent;
                _btnStrokeEraser.BorderBrush = stroke ? new SolidColorBrush(activeColor) : Brushes.Transparent;
                ((TextBlock)_btnStrokeEraser.Child).Foreground = new SolidColorBrush(stroke ? activeColor : normalColor);
            }
            
            if (_btnPointEraser != null)
            {
                _btnPointEraser.Background = !stroke ? new SolidColorBrush(Color.FromArgb(46, 0, 245, 212)) : Brushes.Transparent;
                _btnPointEraser.BorderBrush = !stroke ? new SolidColorBrush(activeColor) : Brushes.Transparent;
                ((TextBlock)_btnPointEraser.Child).Foreground = new SolidColorBrush(!stroke ? activeColor : normalColor);
            }
        }

        private void InkCanvas_PreviewDrawingStart(object sender, EventArgs e)
        {
            HideFloatingCards();
        }

        private void HideFloatingCards()
        {
            if (_penDetailsCard != null) _penDetailsCard.Visibility = Visibility.Collapsed;
            if (_eraserDetailsCard != null) _eraserDetailsCard.Visibility = Visibility.Collapsed;
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
                _pageLabel.Text = current + " / " + total + " 쪽 (이동)";
                
            // Write slide index (0-based) and total slides to stdout for SharedPreferences dynamic save/restore
            Console.WriteLine("PAGE_UPDATE:" + (current - 1) + "," + total);

            // Save state to AppData JSON
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
                    // pageBefore == pageAfter.
                    // This can happen because:
                    // 1) An animation was played (currentClick was < totalClicks before Next() was called)
                    // 2) We are on the last slide AND all animations on it are completed (currentClick >= totalClicks before Next() was called)
                    int total = _presentation.Slides.Count;
                    if (pageBefore >= total && currentClick >= totalClicks)
                    {
                        // We are at the last slide and finished all animations! Tell Flutter to autoplay the next file.
                        SaveStrokesToStorage(pageBefore);
                        Console.WriteLine("LAST_SLIDE_NEXT:" + _pptPath);
                        this.Close();
                    }
                    else
                    {
                        // Just an animation step played on a slide (last or non-last).
                        // Do not close. Keep the overlay.
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
            if (_pollTimer != null)
            {
                _pollTimer.Stop();
            }

            // Save strokes for current slide on exit
            if (_lastSlideIndex != -1)
            {
                SaveStrokesToStorage(_lastSlideIndex);
                // Print last slide index (0-based) to stdout for Dart/Flutter session integration
                Console.WriteLine("LAST_PAGE:" + (_lastSlideIndex - 1));
            }

            // Close PowerPoint slideshow cleanly
            try
            {
                if (_slideShowView != null)
                {
                    // Exit slide show
                    _slideShowView.Exit();
                }
            }
            catch {}

            // Save and Close Presentation, Quit PowerPoint application to kill the PPT program
            try
            {
                if (_presentation != null)
                {
                    _presentation.Saved = true; // Mark as saved to prevent dialogs
                    _presentation.Close();
                }
            }
            catch {}

            try
            {
                if (_pptApp != null)
                {
                    _pptApp.Quit();
                }
            }
            catch {}

            // Force kill PowerPoint process to ensure it is dead
            try
            {
                if (_pptPid != 0)
                {
                    System.Diagnostics.Process proc = System.Diagnostics.Process.GetProcessById((int)_pptPid);
                    if (proc != null && !proc.HasExited)
                    {
                        proc.Kill();
                    }
                }
            }
            catch {}

            // Release COM references
            try { if (_slideShowView != null) Marshal.ReleaseComObject(_slideShowView); } catch {}
            try { if (_presentation != null) Marshal.ReleaseComObject(_presentation); } catch {}
            try { if (_pptApp != null) Marshal.ReleaseComObject(_pptApp); } catch {}
            
            _slideShowView = null;
            _presentation = null;
            _pptApp = null;
        }

        // ──────────────── 파일 기반 판서 데이터 저장 / 불러오기 (Dart AnnotationStorageService 완벽 호환) ────────────────

        private string GetPPTStrokesFilePath()
        {
            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            string pptDir = Path.Combine(appData, "BstSave", "PPT");
            if (!Directory.Exists(pptDir))
            {
                Directory.CreateDirectory(pptDir);
            }
            string sanitized = Regex.Replace(_fileName, @"[\\/:*?""<>| ]", "_");
            return Path.Combine(pptDir, sanitized + ".iwb");
        }

        private string GetPPTMetadataFilePath()
        {
            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            string pptDir = Path.Combine(appData, "BstSave", "PPT");
            if (!Directory.Exists(pptDir))
            {
                Directory.CreateDirectory(pptDir);
            }
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
                    escapedFileName,
                    escapedFileName,
                    slide0Based,
                    _slideCount,
                    timestamp
                );
                File.WriteAllText(metadataFile, json, Encoding.UTF8);
            }
            catch (Exception ex)
            {
                Console.WriteLine("[SaveMetadataError] " + ex.Message);
            }
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
                        return int.Parse(match.Groups[1].Value) + 1; // Convert 0-based to 1-based
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("[LoadStateError] " + ex.Message);
            }
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
                int openBraceIndex = content.IndexOf("{", pagesStartIndex);
                if (openBraceIndex == -1) return dict;
                
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
                            if (bracketDepth == 0)
                            {
                                endOfArray = i;
                                break;
                            }
                        }
                    }
                    if (endOfArray != -1)
                    {
                        string arrayVal = content.Substring(startOfArray, endOfArray - startOfArray + 1);
                        dict[pageKey] = arrayVal;
                    }
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine("[ParseIwbError] " + ex.Message);
            }
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
            catch (Exception ex)
            {
                Console.WriteLine("[WriteIwbError] " + ex.Message);
            }
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
            catch (Exception ex)
            {
                Console.WriteLine("[SaveError] Failed to save strokes: " + ex.Message);
            }
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
            catch (Exception ex)
            {
                Console.WriteLine("[LoadError] Failed to load strokes: " + ex.Message);
            }
        }
    }
}
