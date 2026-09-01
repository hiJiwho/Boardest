import '../models/ad_banner.dart';

class AdService {
  List<AdBanner> getSortedBanners(List<AdBanner> banners) {
    final sorted = List<AdBanner>.from(banners);
    sorted.sort((a, b) => a.remainingSeconds.compareTo(b.remainingSeconds));
    return sorted;
  }
}
