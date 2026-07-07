import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:ui';
import '../models/school.dart';
import '../services/comcigan_service.dart';
import '../services/storage_service.dart';
import 'timetable_view.dart';

class SearchView extends StatefulWidget {
  const SearchView({super.key});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final TextEditingController _searchController = TextEditingController();
  final ComciganService _comciganService = ComciganService();
  final StorageService _storageService = StorageService();

  List<School> _searchResults = [];
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await _comciganService.searchSchool(query);
      setState(() {
        _searchResults = results;
        if (results.isEmpty) {
          _errorMessage = '검색 결과가 없습니다.';
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = '네트워크 연결 상태를 확인하고 다시 시도해 주세요.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _selectSchool(School school) async {
    await _storageService.saveSelectedSchool(school);
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, animation, secondaryAnimation) => TimetableView(school: school),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      body: Stack(
        children: [
          // Background Aurora Glows
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2EC4B6).withOpacity(0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2CB67D).withOpacity(0.1),
              ),
            ),
          ),
          Positioned(
            top: 250,
            right: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00F5D4).withOpacity(0.12),
              ),
            ),
          ),
          // Blur layer
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 70.0, sigmaY: 70.0),
            child: Container(color: Colors.transparent),
          ),
          // Main Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  Text(
                    'Boardest',
                    style: GoogleFonts.outfit(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      foreground: Paint()
                        ..shader = const LinearGradient(
                          colors: [Color(0xFF2EC4B6), Color(0xFF00F5D4)],
                        ).createShader(const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '시간표를 조회할 학교를 검색하세요.',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 16,
                      color: const Color(0xFF94A1B2),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Search Bar
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161A).withOpacity(0.6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF2EC4B6).withOpacity(0.3),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2EC4B6).withOpacity(0.1),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: TextField(
                          controller: _searchController,
                          style: GoogleFonts.notoSansKr(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          decoration: InputDecoration(
                            hintText: '예: 광명북고, 상록중',
                            hintStyle: GoogleFonts.notoSansKr(
                              color: const Color(0xFF72757E),
                            ),
                            prefixIcon: const Icon(
                              Icons.search,
                              color: Color(0xFF2EC4B6),
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, color: Color(0xFF72757E)),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 16.0),
                          ),
                          onChanged: (val) => setState(() {}),
                          onSubmitted: (_) => _performSearch(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Search Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2EC4B6),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        shadowColor: const Color(0xFF2EC4B6).withOpacity(0.5),
                      ),
                      onPressed: _performSearch,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              '학교 검색',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Results Title
                  if (_searchResults.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: Text(
                        '검색 결과 (${_searchResults.length}개)',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF94A1B2),
                        ),
                      ),
                    ),
                  // Search Results or Error message
                  Expanded(
                    child: _isLoading
                        ? Container()
                        : _errorMessage != null
                            ? Center(
                                child: Text(
                                  _errorMessage!,
                                  style: GoogleFonts.notoSansKr(
                                    color: const Color(0xFFEF4565),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                physics: const BouncingScrollPhysics(),
                                itemCount: _searchResults.length,
                                itemBuilder: (context, index) {
                                  final school = _searchResults[index];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12.0),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF16161A).withOpacity(0.4),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.08),
                                        width: 1,
                                      ),
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: ListTile(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        title: Text(
                                          school.name,
                                          style: GoogleFonts.notoSansKr(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                        subtitle: Padding(
                                          padding: const EdgeInsets.only(top: 4.0),
                                          child: Text(
                                            '학교코드: ${school.code}',
                                            style: GoogleFonts.notoSansKr(
                                              color: const Color(0xFF94A1B2),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        trailing: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2CB67D).withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(
                                              color: const Color(0xFF2CB67D).withOpacity(0.3),
                                            ),
                                          ),
                                          child: Text(
                                            school.region,
                                            style: GoogleFonts.notoSansKr(
                                              color: const Color(0xFF2CB67D),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        onTap: () => _selectSchool(school),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
