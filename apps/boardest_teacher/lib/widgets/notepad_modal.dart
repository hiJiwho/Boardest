import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotepadModal extends StatefulWidget {
  const NotepadModal({super.key});

  @override
  State<NotepadModal> createState() => _NotepadModalState();
}

class _NotepadModalState extends State<NotepadModal> {
  final TextEditingController _controller = TextEditingController();
  bool _isSaving = false;
  Timer? _debounce;
  static const String _prefKey = 'boardest_scratchpad_notes';

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadNote() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final note = prefs.getString(_prefKey) ?? '';
      setState(() {
        _controller.text = note;
      });
    } catch (_) {}
  }

  Future<void> _saveNote(String text) async {
    setState(() {
      _isSaving = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, text);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isSaving = false;
      });
    }
  }

  void _onTextChanged(String text) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      _saveNote(text);
    });
    setState(() {}); // Force counter update
  }

  @override
  Widget build(BuildContext context) {
    final charCount = _controller.text.length;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: 460,
              height: 500,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.4),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  // Notepad Header
                  AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.note_alt, color: Colors.cyanAccent, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '메모장 (자동 저장)',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    centerTitle: true,
                    leading: Container(),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),

                  // Notepad Editor
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.06),
                            width: 1,
                          ),
                        ),
                        child: TextField(
                          controller: _controller,
                          maxLines: null,
                          onChanged: _onTextChanged,
                          keyboardType: TextInputType.multiline,
                          style: GoogleFonts.nanumGothic(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 15,
                            height: 1.6,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: '자유롭게 필기하거나 메모를 남겨보세요...',
                            hintStyle: GoogleFonts.nanumGothic(
                              color: Colors.white38,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Footer Stats / Info
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Autosave micro indicator
                        Row(
                          children: [
                            if (_isSaving)
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.cyanAccent,
                                ),
                              )
                            else
                              const Icon(
                                Icons.cloud_done,
                                color: Colors.cyanAccent,
                                size: 16,
                              ),
                            const SizedBox(width: 6),
                            Text(
                              _isSaving ? '저장 중...' : '자동 저장 완료',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: Colors.white38,
                              ),
                            ),
                          ],
                        ),
                        // Character counter
                        Text(
                          '$charCount자',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
