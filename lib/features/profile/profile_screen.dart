import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/activity_tracker.dart';
import '../../core/api_client.dart';
import '../../core/app_info.dart';
import '../../core/constants.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _driver;
  String _appVersion = '';

  // Banners
  List<Map<String, dynamic>> _banners = [];
  bool _isLoadingBanners = true;
  final PageController _pageController = PageController();
  int _currentBannerIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    ActivityTracker.track(
      eventKey: 'profile_view',
      screenKey: 'profile',
      screenTitle: 'پروفایل',
    );
    _loadLocalData(); // لود سریع و بدون مکث از کش
    _fetchFreshProfile(); // دریافت دیتای زنده از سرور
    _fetchBanners();
    _getAppVersion();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalData() async {
    final userJson = await AppStorage.getUserJson();
    if (userJson != null) {
      try {
        final data = jsonDecode(userJson);
        setState(() {
          _user = data['user'];
          _driver = data['driver'];
        });
      } catch (_) {}
    }
  }

  // دریافت اطلاعات تازه از سرور برای همگام‌سازی لحظه‌ای با پنل ادمین
  Future<void> _fetchFreshProfile() async {
    try {
      final res = await ApiClient.getJson(AppConstants.meEndpoint);
      if (res['ok'] == true && res['user'] != null) {
        // ذخیره در کش تا دفعات بعد سریع لود شود
        await AppStorage.setUserJson(jsonEncode(res));

        if (mounted) {
          setState(() {
            _user = res['user'];
            _driver = res['driver'];
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _getAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = packageInfo.version;
      });
    }
  }

  Future<void> _fetchBanners() async {
    try {
      // دریافت بنرهای پروفایل (placement=profile)
      final res = await ApiClient.getJson(
        '${AppConstants.bannersEndpoint}?target_app_id=1&placement=profile',
      );

      if (res['ok'] == true && res['items'] != null) {
        if (mounted) {
          setState(() {
            _banners = (res['items'] as List).map((b) {
              final banner = Map<String, dynamic>.from(b);
              banner['image_url'] = AppConstants.fixUrl(
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
      if (mounted) setState(() => _isLoadingBanners = false);
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

  void _showRatingInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.star_rounded, color: Colors.amber, size: 28),
            SizedBox(width: 8),
            Text(
              'سیستم امتیازدهی',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRatingBullet(
              'رانندگانی که امتیاز بالاتری دارند، بارها را به صورت آنی و بدون تاخیر مشاهده می‌کنند.',
            ),
            const SizedBox(height: 10),
            _buildRatingBullet(
              'رانندگان با امتیاز کمتر، بارها را با چند دقیقه تاخیر در سیستم می‌بینند.',
            ),
            const SizedBox(height: 10),
            _buildRatingBullet(
              'امتیاز شما بر اساس کیفیت حمل بار و تایید صاحبان بار محاسبه می‌شود.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: const Text(
                '💡 با ارائه خدمات سریع و مطمئن، امتیاز خود را افزایش دهید و بارها را زودتر از رقبا رزرو کنید!',
                style: TextStyle(fontSize: 13, height: 1.6, color: Colors.blue),
                textAlign: TextAlign.justify,
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                minimumSize: const Size(120, 40),
              ),
              child: const Text('متوجه شدم'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingBullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Icon(Icons.circle, size: 8, color: AppTheme.secondary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, height: 1.6),
            textAlign: TextAlign.justify,
          ),
        ),
      ],
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('خروج از حساب'),
        content: const Text('آیا مطمئن هستید که می‌خواهید خارج شوید؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('خروج'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ActivityTracker.trackNow(
        eventKey: 'logout',
        screenKey: 'profile',
        screenTitle: 'پروفایل',
      );
      try {
        await ApiClient.postJson(AppConstants.logoutEndpoint, {});
      } catch (_) {}
      await AppStorage.clearAll();
      if (mounted) context.go('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    final String fullName = _user?['full_name'] ?? 'کاربر';
    final String phone = _user?['phone'] ?? '---';
    final String? avatarKey = _user?['avatar_key'];
    final String avatarUrl = avatarKey != null
        ? AppConstants.fixUrl(avatarKey)
        : '';

    final int vStatus =
        int.tryParse(_driver?['verification_status']?.toString() ?? '0') ?? 0;
    final bool isVerified = vStatus == 1;
    final bool isRejected = vStatus == 2;
    final String rejectReason =
        _driver?['reject_reason']?.toString() ??
        'مدارک یا مشخصات شما تایید نشد. لطفا موارد را اصلاح کرده و یا با پشتیبانی تماس بگیرید.';

    final double rating =
        double.tryParse(_driver?['rating_avg']?.toString() ?? '0') ?? 0.0;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'حساب کاربری',
          style: TextStyle(
            color: AppTheme.secondary,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            // --- بنرهای تبلیغاتی اختصاصی پروفایل ---
            if (!_isLoadingBanners && _banners.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 120,
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _currentBannerIndex = index);
                  },
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
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],

            const SizedBox(height: 16),

            // --- هدر پروفایل جدید، بهینه و بدون فضای خالی مفرط ---
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      children: [
                        // تصویر آواتار با افکت رینگ مدرن
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.primary.withOpacity(0.2),
                              width: 3,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 38,
                            backgroundColor: AppTheme.primary.withOpacity(0.1),
                            backgroundImage: avatarUrl.isNotEmpty
                                ? NetworkImage(avatarUrl)
                                : null,
                            child: avatarUrl.isEmpty
                                ? const Icon(
                                    Icons.person_rounded,
                                    size: 38,
                                    color: AppTheme.primary,
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 16),
                        // نام، شماره همراه و مشخصه راننده
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fullName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                phone,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.5,
                                ),
                                textDirection: TextDirection.ltr,
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.local_shipping_outlined,
                                    size: 14,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'راننده سامانه هوشمند آموت‌بار',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // شبکه پایینی اطلاعات آماری و احراز هویت (پرکننده اصولی فضا)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(28),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      children: [
                        // ستون امتیاز فعال راننده
                        Expanded(
                          child: InkWell(
                            onTap: _showRatingInfoDialog,
                            child: Column(
                              children: [
                                const Text(
                                  'امتیاز کاربری',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.star_rounded,
                                      color: Colors.amber,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      rating > 0 ? rating.toString() : '۵.۰',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 2),
                                    const Icon(
                                      Icons.info_outline_rounded,
                                      color: Colors.grey,
                                      size: 13,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        // خط جداکننده مینیمال میانی
                        Container(
                          height: 28,
                          width: 1,
                          color: Colors.grey.shade200,
                        ),
                        // ستون وضعیت تایید حساب
                        Expanded(
                          child: Column(
                            children: [
                              const Text(
                                'وضعیت احراز هویت',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isVerified ? 'تایید شده' : 'در انتظار بررسی',
                                style: TextStyle(
                                  color: isVerified
                                      ? Colors.green.shade700
                                      : Colors.orange.shade700,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
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

            const SizedBox(height: 24),

            // --- پیغام رد شدن احراز هویت ---
            if (isRejected) ...[
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: Colors.red),
                        SizedBox(width: 8),
                        Text(
                          'احراز هویت رد شد',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      rejectReason,
                      style: const TextStyle(
                        color: Colors.red,
                        height: 1.5,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 45,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          final phone = AppInfoCache.supportPhone;
                          if (phone.isNotEmpty)
                            launchUrl(Uri.parse('tel:$phone'));
                        },
                        icon: const Icon(Icons.support_agent_rounded, size: 20),
                        label: const Text('تماس با پشتیبانی'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // --- لیست منوها ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _buildMenuItem(
                    icon: Icons.person_outline_rounded,
                    title: 'اطلاعات هویتی',
                    subtitle: 'مشاهده مشخصات شخصی',
                    onTap: () {
                      ActivityTracker.track(
                        eventKey: 'identity_info_view',
                        screenKey: 'identity_info',
                        screenTitle: 'اطلاعات هویتی',
                      );
                      context.push('/identity-info');
                    },
                  ),
                  _buildMenuItem(
                    icon: Icons.directions_car_outlined,
                    title: 'مشخصات خودرو',
                    subtitle: 'مدیریت پلاک و نوع بارگیر',
                    onTap: () {
                      ActivityTracker.track(
                        eventKey: 'vehicle_info_view',
                        screenKey: 'vehicle_info',
                        screenTitle: 'مشخصات خودرو',
                      );
                      context.push('/vehicle-info');
                    },
                  ),
                  // _buildMenuItem(
                  //   icon: Icons.account_balance_wallet_outlined,
                  //   title: 'کیف پول و تراکنش‌ها',
                  //   subtitle: 'موجودی و تاریخچه مالی',
                  //   isComingSoon: true,
                  //   onTap: () {},
                  // ),
                  _buildMenuItem(
                    icon: Icons.support_agent_rounded,
                    title: 'پشتیبانی و پیام‌ها',
                    subtitle: 'ارتباط با ما و پیگیری مشکلات',
                    onTap: () {
                      ActivityTracker.track(
                        eventKey: 'support_view',
                        screenKey: 'support',
                        screenTitle: 'پشتیبانی و پیام‌ها',
                      );
                      context.push('/support');
                    },
                  ),
                  _buildMenuItem(
                    icon: Icons.gavel_rounded,
                    title: 'قوانین و مقررات',
                    subtitle: 'شرایط استفاده از خدمات',
                    onTap: () async {
                      final url = AppInfoCache.termsUrl;
                      if (url.isNotEmpty) {
                        await launchUrl(
                          Uri.parse(url),
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                  ),
                  _buildMenuItem(
                    icon: Icons.logout_rounded,
                    title: 'خروج از حساب کاربری',
                    subtitle: 'قطع اتصال از این دستگاه',
                    iconColor: Colors.red,
                    textColor: Colors.red,
                    onTap: _logout,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            // نسخه برنامه
            Text(
              'نسخه $_appVersion',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color iconColor = AppTheme.secondary,
    Color textColor = Colors.black87,
    bool isComingSoon = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: isComingSoon ? null : onTap,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 8,
          ),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isComingSoon
                  ? Colors.grey.shade100
                  : iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: isComingSoon ? Colors.grey : iconColor),
          ),
          title: Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: isComingSoon ? Colors.grey : textColor,
                ),
              ),
              if (isComingSoon) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'به زودی',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          trailing: isComingSoon
              ? null
              : const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: Colors.grey,
                ),
        ),
      ),
    );
  }
}
