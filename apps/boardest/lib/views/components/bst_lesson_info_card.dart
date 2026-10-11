import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Boardest 전자칠판 수업 정보 카드 (교과서 크게 + 과목명 + 남은 시간 표시)
class BstLessonInfoCard extends StatelessWidget {
  final String currentSubject;
  final String subjectDescription;
  final String nextSubject;
  final String nextSubjectRoom;
  final String subjectIcon;
  final String? textbookImagePath;
  final Uint8List? textbookBytes;
  final String? remainingTimeText;
  final VoidCallback? onTap;

  const BstLessonInfoCard({
    super.key,
    required this.currentSubject,
    this.subjectDescription = '',
    required this.nextSubject,
    this.nextSubjectRoom = '',
    this.subjectIcon = '📘',
    this.textbookImagePath,
    this.textbookBytes,
    this.remainingTimeText,
    this.onTap,
  });

  Widget _buildTextbookVisual() {
    if (textbookBytes != null && textbookBytes!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.memory(
          textbookBytes!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => _buildFallbackVisual(),
        ),
      );
    }
    if (textbookImagePath != null && textbookImagePath!.isNotEmpty) {
      if (!kIsWeb && File(textbookImagePath!).existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.file(
            File(textbookImagePath!),
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => _buildFallbackVisual(),
          ),
        );
      } else if (textbookImagePath!.startsWith('http://') || textbookImagePath!.startsWith('https://')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            textbookImagePath!,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, __, ___) => _buildFallbackVisual(),
          ),
        );
      }
    }
    return _buildFallbackVisual();
  }

  Widget _buildFallbackVisual() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1E293B),
            Color(0xFF0F172A),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(subjectIcon, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 4),
            Text(
              '교과서',
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.6),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0F1D),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 1. 상단 바: 타이틀 + 남은 시간(분) 뱃지
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00F5D4).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.school_rounded, color: Color(0xFF00F5D4), size: 16),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      '수업 정보',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                // 남은 시간 뱃지 (예: ⏳ 18분 남음)
                if (remainingTimeText != null && remainingTimeText!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5470).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFFF5470).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, size: 13, color: Color(0xFFFF5470)),
                        const SizedBox(width: 5),
                        Text(
                          remainingTimeText!,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFFF5470),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F5D4).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF00F5D4).withValues(alpha: 0.3)),
                    ),
                    child: const Text(
                      '교과서 열기 ›',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF00F5D4),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // 2. 중앙 & 하단 전면: 대형 교과서 표지 + 시계보다 약간 작은 대형 과목명
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 카드를 가득 채우는 초대형 교과서 책
                  AspectRatio(
                    aspectRatio: 1 / 1.45,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.6),
                            blurRadius: 18,
                            offset: const Offset(4, 6),
                          ),
                        ],
                      ),
                      child: _buildTextbookVisual(),
                    ),
                  ),

                  const SizedBox(width: 22),

                  // 과목명 + 수업 안내 (시계와 동급 수준의 초대형 표시)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.contain,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                currentSubject.isNotEmpty ? currentSubject : '수업 준비',
                                style: const TextStyle(
                                  fontSize: 110, // 초대형 시계급 폰트
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -2.0,
                                  height: 1.0,
                                ),
                                maxLines: 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subjectDescription.isNotEmpty ? subjectDescription : '수업 진행 중',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF94A3B8),
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
