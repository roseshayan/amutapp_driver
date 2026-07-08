import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/activity_tracker.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import 'dashboard_screen.dart';
import '../profile/profile_screen.dart';
import '../loads/loads_list_screen.dart';
import '../calls/call_history_screen.dart';

final ValueNotifier<int> unreadNotificationsCount = ValueNotifier<int>(0);
final ValueNotifier<Map<String, dynamic>?> latestNotificationRoute =
    ValueNotifier(null);

void handleNotificationRouting(BuildContext context) {
  final notif = latestNotificationRoute.value;
  if (notif == null) return;

  final String? type = notif['type'];
  final Map<String, dynamic>? data = notif['data'];

  // فراخوانی API برای خوانده شدن اعلان‌ها
  ApiClient.getJson(AppConstants.notificationsEndpoint).catchError((_) {});

  if (type == 'ticket_reply' && data != null && data['ticket_id'] != null) {
    final ticketId = int.tryParse(data['ticket_id'].toString());
    if (ticketId != null) {
      unreadNotificationsCount.value = 0;
      latestNotificationRoute.value = null;
      // هدایت امن به صفحه چت
      GoRouter.of(context).push('/ticket-chat', extra: ticketId);
    }
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  Timer? _notifTimer;
  int _lastNotifiedCount = 0; // برای جلوگیری از تکرار نوتیفیکیشن‌های تکراری
  bool _isExitDialogOpen = false;

  @override
  void initState() {
    super.initState();
    ActivityTracker.track(
      eventKey: 'app_open',
      screenKey: 'dashboard',
      screenTitle: 'داشبورد',
    );
    ActivityTracker.track(
      eventKey: 'dashboard_view',
      screenKey: 'dashboard',
      screenTitle: 'داشبورد',
    );
    _checkUnreadNotifs();
    _notifTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkUnreadNotifs(),
    );
  }

  @override
  void dispose() {
    _notifTimer?.cancel();
    super.dispose();
  }

  void _changeTab(int index) {
    final labels = ['داشبورد', 'بارهای اطراف من', 'تماس‌ها', 'پروفایل'];
    final keys = ['dashboard', 'nearby_loads', 'call_history', 'profile'];
    if (index >= 0 && index < labels.length && index != _currentIndex) {
      ActivityTracker.track(
        eventKey: 'tab_change',
        screenKey: keys[index],
        screenTitle: labels[index],
        payload: {'tab_index': index, 'tab_title': labels[index]},
      );
      if (index == 0) {
        ActivityTracker.track(
          eventKey: 'dashboard_view',
          screenKey: 'dashboard',
          screenTitle: 'داشبورد',
        );
      } else if (index == 1) {
        ActivityTracker.track(
          eventKey: 'nearby_loads_view',
          screenKey: 'nearby_loads',
          screenTitle: 'بارهای اطراف من',
        );
      } else if (index == 2) {
        callHistoryRefreshNotifier.value++;
      } else if (index == 3) {
        ActivityTracker.track(
          eventKey: 'profile_view',
          screenKey: 'profile',
          screenTitle: 'پروفایل',
        );
      }
    }
    setState(() {
      _currentIndex = index;
    });
  }

  Future<void> _checkUnreadNotifs() async {
    try {
      final res = await ApiClient.getJson(
        AppConstants.unreadNotifsCountEndpoint,
      );
      if (res['ok'] == true && mounted) {
        final newCount = res['unread_count'] as int;

        // فقط اگر عدد اعلان‌ها از آخرین باری که پاپ‌آپ دادیم بیشتر شد، دوباره پاپ‌آپ بده
        if (newCount > _lastNotifiedCount && newCount > 0) {
          latestNotificationRoute.value = {
            'type': res['latest_type'],
            'data': res['latest_data'],
          };
          _showInAppNotificationAlert();
          _lastNotifiedCount = newCount;
        } else if (newCount == 0) {
          _lastNotifiedCount = 0;
        }

        unreadNotificationsCount.value = newCount;
      }
    } catch (_) {}
  }

  void _showInAppNotificationAlert() {
    if (!mounted) return;

    // بستن اسنک‌بارهای قبلی
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.chat_bubble_rounded, color: Colors.white),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'پاسخ جدیدی از پشتیبانی دریافت شد.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Vazir',
                  fontSize: 13,
                ),
              ),
            ),
            // اضافه شدن دکمه ضربدر برای بستن
            IconButton(
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white70,
                size: 20,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              },
            ),
          ],
        ),
        backgroundColor: AppTheme.secondary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 20, left: 16, right: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'مشاهده',
          textColor: Colors.amber,
          onPressed: () {
            // جلوگیری از کرش با مخفی کردن دستی اسنک بار
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            handleNotificationRouting(context);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // جلوگیری از خروج ناگهانی با دکمه Back اندروید
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isExitDialogOpen) return;

        if (_currentIndex != 0) {
          // اگر در تبی غیر از داشبورد است، فقط به داشبورد برگردد و از اپ خارج نشود.
          _changeTab(0);
          return;
        }

        _isExitDialogOpen = true;
        final shouldExit = await showDialog<bool>(
          context: context,
          barrierDismissible: true,
          builder: (context) => AlertDialog(
            title: const Text('خروج از برنامه'),
            content: const Text('برای خروج از برنامه مطمئن هستید؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ماندن در برنامه'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('خروج'),
              ),
            ],
          ),
        );
        _isExitDialogOpen = false;

        if (shouldExit == true) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            DashboardScreen(onChangeTab: _changeTab),
            const LoadsListScreen(), // 🔥 تب بارهای اطراف من به صفحه لیست بار متصل شد
            const CallHistoryScreen(),
            const ProfileScreen(),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: NavigationBar(
            selectedIndex: _currentIndex,
          onDestinationSelected: _changeTab,
          backgroundColor: Colors.white,
          indicatorColor: AppTheme.primary.withOpacity(0.15),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: AppTheme.primary),
              label: 'داشبورد',
            ),
            NavigationDestination(
              icon: Icon(Icons.location_on_outlined),
              selectedIcon: Icon(Icons.location_on, color: AppTheme.primary),
              label: 'اطراف من',
            ),
            NavigationDestination(
              icon: Icon(Icons.phone_in_talk_outlined),
              selectedIcon: Icon(Icons.phone_in_talk, color: AppTheme.primary),
              label: 'تماس‌ها',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded, color: AppTheme.primary),
              label: 'پروفایل',
            ),
            ],
          ),
        ),
      ),
    );
  }
}
