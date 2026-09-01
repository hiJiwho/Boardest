import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/cloud_drive_service.dart';
import '../services/bst_cloud_service.dart';

class DriveCastBoardView extends StatefulWidget {
  final double scaleFactor;

  const DriveCastBoardView({super.key, this.scaleFactor = 1.0});

  @override
  State<DriveCastBoardView> createState() => _DriveCastBoardViewState();
}

class _DriveCastBoardViewState extends State<DriveCastBoardView> {
  int _selectedHours = 2; // Default 2 hours
  final List<int> _hourOptions = [1, 2, 4, 8, 12, 24];

  DateTime? _castExpireAt;
  Timer? _countdownTimer;
  String _remainingText = '2시간 00분';

  List<String> _onlineClassrooms = [];
  bool _isLoading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _updateExpireAt();
    _fetchClassrooms();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _fetchClassrooms(),
    );
  }

  Future<void> _fetchClassrooms() async {
    final classrooms = await BstCloudService.instance.getOnlineClassrooms();
    if (mounted) {
      setState(() {
        _onlineClassrooms = classrooms;
        _isLoading = false;
      });
    }
  }

  void _updateExpireAt() {
    _castExpireAt = DateTime.now().add(Duration(hours: _selectedHours));
    _startTimer();
  }

  void _startTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _castExpireAt == null) return;
      final now = DateTime.now();
      final diff = _castExpireAt!.difference(now);
      if (diff.isNegative) {
        _countdownTimer?.cancel();
        setState(() {
          _remainingText = '만료됨';
        });
      } else {
        final hours = diff.inHours;
        final mins = diff.inMinutes.remainder(60);
        final secs = diff.inSeconds.remainder(60);
        setState(() {
          _remainingText =
              '${hours}시간 ${mins.toString().padLeft(2, '0')}분 ${secs.toString().padLeft(2, '0')}초';
        });
      }
    });
  }

  Future<void> _startDriveCastToClassroom(String classroom) async {
    final teacherName = CloudDriveService.instance.userName ?? '선생님';
    final token =
        CloudDriveService.instance.boardestToken ??
        CloudDriveService.instance.accessToken ??
        '';
    final folderId = CloudDriveService.instance.boardestFolderId ?? '';

    if (token.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('구글 드라이브 로그인 정보가 필요합니다.')));
      return;
    }

    final success = await BstCloudService.instance.approveConnectionRequest(
      teacherName: teacherName,
      classroomName: classroom,
      token: token,
      folderId: folderId,
      durationHours: _selectedHours,
    );

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📺 [$classroom] 교실 전자칠판으로 즉시 DriveCast 송출을 성공했습니다!'),
          backgroundColor: const Color(0xFF2EC4B6),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ DriveCast 송출 요청에 실패했습니다.')),
      );
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.scaleFactor;

    return Dialog(
      backgroundColor: const Color(0xFF131418),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20 * scale),
      ),
      insetPadding: EdgeInsets.all(16 * scale),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20 * scale),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.88,
          height: MediaQuery.of(context).size.height * 0.85,
          color: const Color(0xFF131418),
          child: Column(
            children: [
              // Top Bar
              Container(
                height: 52 * scale,
                padding: EdgeInsets.symmetric(horizontal: 16 * scale),
                color: const Color(0xFF1C1D24),
                child: Row(
                  children: [
                    const Icon(
                      Icons.cast_connected_rounded,
                      color: Color(0xFF2EC4B6),
                      size: 22,
                    ),
                    SizedBox(width: 8 * scale),
                    Text(
                      'DriveCast 교사 주도 송출 컨트롤러',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 15 * scale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 12 * scale),

                    // Timer Badge
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10 * scale,
                        vertical: 4 * scale,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2EC4B6).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8 * scale),
                        border: Border.all(
                          color: const Color(0xFF2EC4B6).withOpacity(0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.timer_rounded,
                            color: Color(0xFF2EC4B6),
                            size: 14,
                          ),
                          SizedBox(width: 6 * scale),
                          Text(
                            '유효 시간: $_remainingText',
                            style: GoogleFonts.notoSansKr(
                              color: const Color(0xFF2EC4B6),
                              fontSize: 11 * scale,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // Hours Dropdown
                    Row(
                      children: [
                        Text(
                          '송출 유효 시간: ',
                          style: GoogleFonts.notoSansKr(
                            color: Colors.white70,
                            fontSize: 11 * scale,
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8 * scale),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8 * scale),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _selectedHours,
                              dropdownColor: const Color(0xFF1C1D24),
                              icon: const Icon(
                                Icons.arrow_drop_down,
                                color: Colors.white70,
                              ),
                              style: GoogleFonts.notoSansKr(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12 * scale,
                              ),
                              items: _hourOptions.map((h) {
                                return DropdownMenuItem<int>(
                                  value: h,
                                  child: Text(h == 24 ? '24시간 (최대)' : '$h시간'),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedHours = val);
                                  _updateExpireAt();
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(width: 12 * scale),

                    IconButton(
                      icon: const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                      tooltip: '전자칠판 목록 새로고침',
                      onPressed: _fetchClassrooms,
                    ),

                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Classroom List
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF2EC4B6),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(24),
                        itemCount: _onlineClassrooms.length,
                        itemBuilder: (context, index) {
                          final classroom = _onlineClassrooms[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1D24),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.1),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF2EC4B6,
                                    ).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.cast_connected_rounded,
                                    color: Color(0xFF2EC4B6),
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            classroom,
                                            style: GoogleFonts.notoSansKr(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(
                                                0.2,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: Colors.green,
                                              ),
                                            ),
                                            child: Text(
                                              '🟢 ONLINE',
                                              style: GoogleFonts.outfit(
                                                color: Colors.green,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '현재 교실 전자칠판이 대기 중입니다. 클릭 시 즉시 1초 송출을 시작합니다.',
                                        style: GoogleFonts.notoSansKr(
                                          color: Colors.white60,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () =>
                                      _startDriveCastToClassroom(classroom),
                                  icon: const Icon(
                                    Icons.sensors_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('즉시 DriveCast 송출'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF2EC4B6),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    textStyle: GoogleFonts.notoSansKr(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
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
}
