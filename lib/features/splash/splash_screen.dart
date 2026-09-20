import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart'; // پکیج اطلاعات نسخه
import 'package:url_launcher/url_launcher.dart';
import '../../core/app_info.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // وضعیت‌های صفحه
  String _statusText = 'در حال راه‌اندازی...';
  bool _hasError = false;
  bool _isVpnConnected = false;
  bool _isOffline = false;
  bool _isMaintenance = false;

  // وضعیت آپدیت
  bool _updateAvailable = false;
  bool _forceUpdate = false;
  String? _updateUrl;

  // نگهداری نسخه فعلی برنامه
  String _appVersionLabel = '';

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  bool _isBooting = false;
  bool _dataLoaded = false;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);

    _initConnectivityListener();
    _bootApplication();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _animController.dispose();
    super.dispose();
  }

  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      _checkNetworkAndProceed(results);
    });
  }

  void _checkNetworkAndProceed(List<ConnectivityResult> results) {
    final hasNet = !results.contains(ConnectivityResult.none);
    final isVpn = results.contains(ConnectivityResult.vpn);

    if (mounted) {
      setState(() {
        _isOffline = !hasNet;
        _isVpnConnected = isVpn;
      });
    }

    if (_isOffline) {
      _setError('اتصال اینترنت برقرار نیست.');
    } else if (_isVpnConnected) {
      _setError('لطفاً فیلترشکن (VPN) را خاموش کنید.');
    } else {
      if (_hasError) {
        setState(() {
          _hasError = false;
          _statusText = 'در حال ارتباط با سرور...';
        });
        if (!_isBooting && !_dataLoaded) {
          _bootApplication();
        }
      }
    }
  }

  void _setError(String msg) {
    if (mounted) {
      setState(() {
        _statusText = msg;
        _hasError = true;
      });
      if (_animController.status == AnimationStatus.dismissed) {
        _animController.forward();
      }
    }
  }

  Future<void> _bootApplication() async {
    if (_isBooting || _dataLoaded) return;
    _isBooting = true;
    final startTime = DateTime.now();

    try {
      // 1. دریافت اطلاعات نسخه نصب شده روی گوشی
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 1;
      _appVersionLabel = packageInfo.version; // مثلا 1.0.0

      // 2. دریافت تنظیمات از سرور
      final info = await ApiClient.getJson(AppConstants.appInfoEndpoint);

      // اصلاح لینک‌ها (لوگو و فاوآیکون)
      if (info['logo_url'] != null) {
        info['logo_url'] = AppConstants.fixUrl(info['logo_url'].toString());
      }
      if (info['favicon_url'] != null) {
        info['favicon_url'] = AppConstants.fixUrl(
          info['favicon_url'].toString(),
        );
      }

      AppInfoCache.setRaw(info);
      _dataLoaded = true;

      if (!mounted) return;

      // 3. بررسی آپدیت با استفاده از نسخه واقعی گوشی
      _checkVersion(info, currentVersionCode);

      // 4. بررسی حالت تعمیرات
      if (AppInfoCache.maintenanceEnabled) {
        setState(() {
          _isMaintenance = true;
          _statusText = AppInfoCache.maintenanceMessage.isNotEmpty
              ? AppInfoCache.maintenanceMessage
              : 'سامانه در حال به‌روزرسانی است.';
          _hasError = true;
        });
        _animController.forward();
        return;
      }

      setState(() {});
      _animController.forward();

      if (_forceUpdate) {
        setState(() => _statusText = 'نسخه جدید الزامی است.');
        return;
      }

      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      final remain = 3000 - elapsed;
      if (remain > 0) await Future.delayed(Duration(milliseconds: remain));

      if (!mounted) return;

      await _checkLoginState();
    } catch (e) {
      debugPrint('Boot Error: $e');
      _setError('خطا در دریافت اطلاعات.');
    } finally {
      _isBooting = false;
    }
  }

  void _checkVersion(Map<String, dynamic> info, int currentCode) {
    try {
      final android = info['app']?['android'];
      if (android != null) {
        final int latestCode =
            int.tryParse(android['latest_version_code']?.toString() ?? '0') ??
            0;
        final int minCode =
            int.tryParse(android['min_supported_code']?.toString() ?? '0') ?? 0;

        // اصلاح لینک دانلود با AppConstants.fixUrl
        String url = android['update_url']?.toString() ?? '';
        url = AppConstants.fixUrl(url);

        setState(() {
          _updateUrl = url;
          if (currentCode < minCode) {
            _forceUpdate = true;
            _updateAvailable = true;
          } else if (currentCode < latestCode) {
            _forceUpdate = false;
            _updateAvailable = true;
          }
        });
      }
    } catch (e) {
      debugPrint('Version check error: $e');
    }
  }

  Future<void> _launchUpdateUrl() async {
    if (_updateUrl == null || _updateUrl!.isEmpty) return;

    final uri = Uri.parse(_updateUrl!);
    try {
      // استفاده از mode externalApplication برای باز شدن در مرورگر کروم/...
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        debugPrint('Could not launch url: $uri');
        // تلاش دوم با مد پیش‌فرض
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Launch Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final logoUrl = AppInfoCache.logoUrl;
    final appName = AppInfoCache.appName.isEmpty
        ? 'آموت‌بار'
        : AppInfoCache.appName;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF00BFFE), Color(0xFF0055B3)],
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 130,
                        height: 130,
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 25,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipOval(child: _buildLogoImage(logoUrl)),
                      ),
                      const SizedBox(height: 30),
                      Text(
                        appName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontFamily: 'Vazir',
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'سامانه هوشمند حمل‌ونقل',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                          fontFamily: 'Vazir',
                        ),
                      ),
                      const SizedBox(height: 50),
                      if (_isMaintenance) ...[
                        const Icon(
                          Icons.build_circle_outlined,
                          color: Colors.orangeAccent,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                      ] else if (_hasError) ...[
                        Icon(
                          _isOffline
                              ? Icons.wifi_off_rounded
                              : Icons.vpn_lock_rounded,
                          color: Colors.orangeAccent,
                          size: 40,
                        ),
                        const SizedBox(height: 10),
                      ] else if (!_forceUpdate) ...[
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      Text(
                        _statusText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: (_hasError || _isMaintenance)
                              ? Colors.orangeAccent
                              : Colors.white70,
                          fontSize: 14,
                          fontFamily: 'Vazir',
                          fontWeight: (_hasError || _isMaintenance)
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 30,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  children: [
                    if (_updateAvailable) ...[
                      Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 10,
                        ),
                        width: double.infinity,
                        height: 55,
                        child: ElevatedButton.icon(
                          onPressed: _launchUpdateUrl,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF007AFF),
                            elevation: 5,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          icon: const Icon(Icons.system_update),
                          label: Text(
                            _forceUpdate
                                ? 'دانلود نسخه جدید (اجباری)'
                                : 'دانلود نسخه جدید',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        // نمایش نسخه خوانده شده از pubspec
                        'نسخه $_appVersionLabel',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12,
                          fontFamily: 'Vazir',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkLoginState() async {
    final token = await AppStorage.getToken();
    if (token != null && token.isNotEmpty) {
      try {
        // پینگ به سرور برای دریافت وضعیت دقیق مراحل ثبت‌نام کاربر
        final meResponse = await ApiClient.getJson(AppConstants.meEndpoint);

        // ذخیره لوکال برای استفاده‌های بعدی در اپلیکیشن
        await AppStorage.setUserJson(jsonEncode(meResponse));

        // بک‌اند یک آرایه onboarding برمی‌گرداند که وضعیت دقیق مراحل در آن است
        final onboarding = meResponse['onboarding'];

        if (mounted && onboarding != null) {
          // وضعیت احراز هویت رو از سرور می‌خونیم (0=در انتظار، 1=تایید، 2=رد شده)
          final int vStatus =
              int.tryParse(
                onboarding['verification_status']?.toString() ?? '0',
              ) ??
              0;

          final bool profileCompleted =
              onboarding['profile_completed'] ?? false;
          final bool needsVehicleInfo =
              onboarding['needs_vehicle_info'] ?? false;
          final bool needsVideo =
              onboarding['needs_verification_video'] ?? false;

          // رد هویت همیشه کاربر را به فرم اصلاح اطلاعات برمی‌گرداند.
          if (vStatus == 2) {
            context.go('/identity');
          } else if (!profileCompleted || vStatus != 1) {
            context.go('/identity');
          } else if (needsVehicleInfo) {
            context.go('/vehicle-setup');
          } else if (needsVideo) {
            context.go('/video-verify');
          } else {
            // فقط پس از تکمیل همه‌ی مراحل وارد داشبورد می‌شود.
            context.go('/dashboard');
          }
        } else if (mounted) {
          context.go('/identity');
        }
      } catch (e) {
        if (e is ApiException && e.statusCode == 401) {
          await AppStorage.clearAll();
          if (mounted) context.go('/auth');
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(minutes: 5),
              content: Text(
                e is ApiException
                    ? e.displayMessage
                    : 'دریافت وضعیت حساب انجام نشد؛ اتصال را بررسی کنید.',
              ),
              action: SnackBarAction(
                label: 'تلاش مجدد',
                onPressed: _checkLoginState,
              ),
            ),
          );
        }
      }
    } else {
      if (mounted) context.go('/auth');
    }
  }

  Widget _buildLogoImage(String url) {
    if (url.isEmpty) {
      return const Icon(
        Icons.local_shipping_rounded,
        size: 70,
        color: AppTheme.primary,
      );
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return const Icon(
          Icons.local_shipping_rounded,
          size: 70,
          color: Colors.grey,
        );
      },
    );
  }
}
