import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class WeatherDialog extends StatefulWidget {
  final double scaleFactor;
  const WeatherDialog({super.key, required this.scaleFactor});

  @override
  State<WeatherDialog> createState() => _WeatherDialogState();
}

class _WeatherDialogState extends State<WeatherDialog> {
  bool _isLoading = false;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _dialogBg => _isDark ? const Color(0xFF0F0E17).withOpacity(0.85) : Colors.white.withOpacity(0.95);
  Color get _borderColor => _isDark ? const Color(0xFF2EC4B6).withOpacity(0.3) : const Color(0xFF2EC4B6).withOpacity(0.5);
  Color get _textColor => _isDark ? Colors.white : Colors.black87;
  Color get _textColor70 => _isDark ? Colors.white70 : Colors.black54;
  Color get _textColor54 => _isDark ? Colors.white54 : Colors.black54;
  Color get _textColor38 => _isDark ? Colors.white30 : Colors.black38;
  Color get _cardColor => _isDark ? Colors.white.withOpacity(0.02) : Colors.black.withOpacity(0.02);
  Color get _cardBorderColor => _isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.06);

  // Mock weather data matching typical premium weather apps
  final String _currentTemp = '23°';
  final String _currentStatus = '대체로 맑음';
  final String _location = '우리학교 (교실)';
  final String _humidity = '48%';
  final String _windSpeed = '3.2 m/s';
  final String _pm10 = '18 ㎍/㎥ (좋음)';
  final String _uvIndex = '보통 (4)';

  final List<Map<String, dynamic>> _weeklyForecast = [
    {'day': '오늘', 'temp': '15° / 24°', 'icon': Icons.wb_sunny_rounded, 'color': Colors.amberAccent},
    {'day': '내일', 'temp': '16° / 25°', 'icon': Icons.wb_cloudy_rounded, 'color': Colors.blueGrey},
    {'day': '화요일', 'temp': '14° / 23°', 'icon': Icons.umbrella_rounded, 'color': Colors.blueAccent},
    {'day': '수요일', 'temp': '15° / 26°', 'icon': Icons.wb_sunny_rounded, 'color': Colors.amberAccent},
    {'day': '목요일', 'temp': '17° / 27°', 'icon': Icons.wb_sunny_rounded, 'color': Colors.amberAccent},
  ];

  void _refreshWeather() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scaleFactor;
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: AlertDialog(
        backgroundColor: _dialogBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: _borderColor, width: 1.5),
        ),
        titlePadding: EdgeInsets.fromLTRB(24 * scale, 20 * scale, 16 * scale, 8 * scale),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.wb_sunny_rounded, color: Color(0xFF00F5D4)),
                SizedBox(width: 10 * scale),
                Text(
                  '기상 정보',
                  style: GoogleFonts.notoSansKr(
                    color: _textColor,
                    fontSize: 18 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.refresh_rounded, color: _textColor70, size: 20 * scale),
                  onPressed: _isLoading ? null : _refreshWeather,
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: _textColor54, size: 20 * scale),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ],
        ),
        contentPadding: EdgeInsets.fromLTRB(20 * scale, 8 * scale, 20 * scale, 24 * scale),
        content: SizedBox(
          width: 460 * scale,
          child: _isLoading
              ? SizedBox(
                  height: 280 * scale,
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00F5D4)),
                    ),
                  ),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Main current weather banner
                    Container(
                      padding: EdgeInsets.all(16 * scale),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF2EC4B6).withOpacity(0.15),
                            const Color(0xFF2CB67D).withOpacity(0.05),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _cardBorderColor),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.wb_sunny_rounded,
                            size: 64 * scale,
                            color: Colors.amberAccent,
                          ),
                          SizedBox(width: 20 * scale),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _location,
                                  style: GoogleFonts.notoSansKr(
                                    color: _textColor70,
                                    fontSize: 12 * scale,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _currentTemp,
                                  style: GoogleFonts.outfit(
                                    color: _textColor,
                                    fontSize: 38 * scale,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  _currentStatus,
                                  style: GoogleFonts.notoSansKr(
                                    color: const Color(0xFF00F5D4),
                                    fontSize: 14 * scale,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 16 * scale),

                    // Grid of detailed details
                    Row(
                      children: [
                        Expanded(child: _buildDetailCard('습도', _humidity, Icons.water_drop_rounded, const Color(0xFF00F5D4), scale)),
                        SizedBox(width: 10 * scale),
                        Expanded(child: _buildDetailCard('바람', _windSpeed, Icons.air_rounded, const Color(0xFF2CB67D), scale)),
                      ],
                    ),
                    SizedBox(height: 10 * scale),
                    Row(
                      children: [
                        Expanded(child: _buildDetailCard('미세먼지', _pm10, Icons.grain_rounded, Colors.amberAccent, scale)),
                        SizedBox(width: 10 * scale),
                        Expanded(child: _buildDetailCard('자외선', _uvIndex, Icons.wb_sunny_outlined, Colors.orangeAccent, scale)),
                      ],
                    ),
                    SizedBox(height: 20 * scale),
                    // Divider
                    Container(
                      height: 1,
                      color: _borderColor,
                    ),
                    SizedBox(height: 14 * scale),

                    // Weekly Forecast
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '주간 예보',
                        style: GoogleFonts.notoSansKr(
                          color: _textColor70,
                          fontSize: 13 * scale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(height: 10 * scale),
                    SizedBox(
                      height: 80 * scale,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _weeklyForecast.length,
                        separatorBuilder: (_, __) => SizedBox(width: 8 * scale),
                        itemBuilder: (context, i) {
                          final f = _weeklyForecast[i];
                          return Container(
                            width: 78 * scale,
                            padding: EdgeInsets.symmetric(vertical: 8 * scale),
                            decoration: BoxDecoration(
                              color: _cardColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _cardBorderColor),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  f['day'],
                                  style: GoogleFonts.notoSansKr(
                                    color: _textColor70,
                                    fontSize: 10 * scale,
                                  ),
                                ),
                                SizedBox(height: 4 * scale),
                                Icon(
                                  f['icon'] as IconData,
                                  color: f['color'] as Color,
                                  size: 20 * scale,
                                ),
                                SizedBox(height: 4 * scale),
                                Text(
                                  f['temp'],
                                  style: GoogleFonts.outfit(
                                    color: _textColor70,
                                    fontSize: 9 * scale,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildDetailCard(String title, String val, IconData icon, Color iconColor, double scale) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6 * scale),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 16 * scale),
          ),
          SizedBox(width: 12 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.notoSansKr(color: _textColor38, fontSize: 10 * scale),
                ),
                Text(
                  val,
                  style: GoogleFonts.notoSansKr(
                    color: _textColor,
                    fontSize: 11 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
