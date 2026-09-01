import 'dart:async';
import 'package:flutter/material.dart';
import '../models/ad_banner.dart';
import '../services/ad_service.dart';

class AdRollingBanner extends StatefulWidget {
  final List<AdBanner> banners;
  final Duration interval;
  final Function(AdBanner)? onBannerTapped;

  const AdRollingBanner({
    Key? key,
    required this.banners,
    this.interval = const Duration(seconds: 10),
    this.onBannerTapped,
  }) : super(key: key);

  @override
  State<AdRollingBanner> createState() => _AdRollingBannerState();
}

class _AdRollingBannerState extends State<AdRollingBanner> {
  final PageController _pageController = PageController();
  final AdService _adService = AdService();
  Timer? _timer;
  late List<AdBanner> _sortedBanners;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _sortedBanners = _adService.getSortedBanners(widget.banners);
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant AdRollingBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.banners != widget.banners) {
      setState(() {
        _sortedBanners = _adService.getSortedBanners(widget.banners);
      });
    }
    if (oldWidget.interval != widget.interval) {
      _stopTimer();
      _startTimer();
    }
  }

  void _startTimer() {
    if (_sortedBanners.isEmpty) return;
    _timer = Timer.periodic(widget.interval, (Timer timer) {
      if (_pageController.hasClients) {
        _currentPage++;
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_sortedBanners.isEmpty) {
      return const SizedBox.shrink();
    }
    return PageView.builder(
      controller: _pageController,
      itemBuilder: (context, index) {
        final bannerIndex = index % _sortedBanners.length;
        final banner = _sortedBanners[bannerIndex];
        return GestureDetector(
          onTap: () {
            if (widget.onBannerTapped != null) {
              widget.onBannerTapped!(banner);
            }
          },
          child: Image.network(
            banner.imageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const Center(
              child: Icon(Icons.error),
            ),
          ),
        );
      },
    );
  }
}
