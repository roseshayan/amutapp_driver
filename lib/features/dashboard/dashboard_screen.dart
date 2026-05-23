import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import 'main_screen.dart';

class DashboardScreen extends StatefulWidget {
  // این کالبک برای تغییر تب اضافه شده است
  final Function(int)? onChangeTab;

  const DashboardScreen({super.key, this.onChangeTab});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Map<String, dynamic>> _banners = [];
  bool _isLoadingBanners = true;

  final PageController _pageController = PageController();
  int _currentBannerIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetchBanners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  String _fixLocalUrl(String url) {
    if (url.isEmpty) return url;
    if (url.contains('amutbar-admin.test')) {
      return url.replaceAll('http://amutbar-admin.test', AppConstants.baseUrl);
    }
    return url;
  }

  Future<void> _fetchBanners() async {
    try {
      final res = await ApiClient.getJson(
        '${AppConstants.bannersEndpoint}?target_app_id=1&placement=dashboard',
      );

      if (res['ok'] == true && res['items'] != null) {
        if (mounted) {
          setState(() {
            _banners = (res['items'] as List).map((b) {
              final banner = Map<String, dynamic>.from(b);
              banner['image_url'] = _fixLocalUrl(
                banner['image_url']?.toString() ?? '',
              );
              return banner;
            }).toList();
            _isLoadingBanners = false;
          });
          _startBannerTimer();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingBanners = false);
      }
    }
  }

  void _startBannerTimer() {
    if (_banners.isEmpty || _banners.length == 1) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_pageController.hasClients) {
        int nextIndex = (_currentBannerIndex + 1) % _banners.length;
        _pageController.animateToPage(
          nextIndex,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _launchBannerUrl(String? url) async {
    if (url == null || url.trim().isEmpty) return;
    final uri = Uri.parse(url.trim());
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'آموت‌بار',
          style: TextStyle(
            color: AppTheme.primary,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: unreadNotificationsCount,
            builder: (context, count, child) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.notifications_none_rounded,
                      color: Colors.black87,
                      size: 26,
                    ),
                    onPressed: () {
                      if (count > 0) {
                        handleNotificationRouting(context);
                      }
                    },
                  ),
                  if (count > 0)
                    Positioned(
                      top: 14,
                      right: 14,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isLoadingBanners)
              const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_banners.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 160,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) =>
                      setState(() => _currentBannerIndex = index),
                  itemCount: _banners.length,
                  itemBuilder: (context, index) {
                    final banner = _banners[index];
                    return GestureDetector(
                      onTap: () => _launchBannerUrl(banner['target_url']),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.grey.shade200,
                          image: DecorationImage(
                            image: NetworkImage(banner['image_url']),
                            fit: BoxFit.cover,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              if (_banners.length > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _banners.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentBannerIndex == index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentBannerIndex == index
                            ? AppTheme.primary
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
            ],

            const SizedBox(height: 32),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'دسترسی سریع',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.secondary,
                ),
              ),
            ),
            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.1,
                children: [
                  // کارت اول: بارهای اطراف من → سوئیچ به تب ۱ (همان LoadsListScreen)
                  _DashboardCard(
                    title: 'بارهای اطراف من',
                    subtitle: 'یافتن بار نزدیک شما',
                    icon: Icons.location_on_rounded,
                    color: Colors.orange,
                    onTap: () =>
                        widget.onChangeTab?.call(1), // سوئیچ به تب اطراف من
                  ),
                  // کارت دوم: جستجوی بار → صفحه جدید جستجو
                  _DashboardCard(
                    title: 'جستجوی بار',
                    subtitle: 'بر اساس مبدا/مقصد',
                    icon: Icons.search_rounded,
                    color: AppTheme.primary,
                    onTap: () => context.push('/search-loads'),
                  ),
                  _DashboardCard(
                    title: 'تماس‌های من',
                    subtitle: 'تاریخچه تماس‌ها',
                    icon: Icons.headset_mic_rounded,
                    color: Colors.green,
                    onTap: () => widget.onChangeTab?.call(2), // رفتن به تب 2
                  ),
                  _DashboardCard(
                    title: 'حساب کاربری',
                    subtitle: 'مدیریت اطلاعات',
                    icon: Icons.person_rounded,
                    color: Colors.purple,
                    onTap: () =>
                        widget.onChangeTab?.call(3), // 🔥 رفتن به تب پروفایل!
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
