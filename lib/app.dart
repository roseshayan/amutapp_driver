import 'package:amutbar_driver/features/auth/identity_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';

import 'core/theme.dart';
import 'features/dashboard/main_screen.dart';
import 'features/loads/load_details_screen.dart';
import 'features/profile/ticket_chat_screen.dart';
import 'features/splash/splash_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/otp_screen.dart';
import 'features/onboarding/vehicle_setup_screen.dart';
import 'features/onboarding/video_verification_screen.dart';
import 'features/profile/support_screen.dart';
import 'features/profile/identity_info_screen.dart';
import 'features/profile/vehicle_info_screen.dart';
import 'features/loads/search_loads_screen.dart';

class AmutBarDriverApp extends StatelessWidget {
  const AmutBarDriverApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
        GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
        GoRoute(
          path: '/otp',
          builder: (_, state) {
            final phone = (state.extra is String) ? state.extra as String : '';
            return OtpScreen(phone: phone);
          },
        ),
        GoRoute(
          path: '/identity',
          builder: (context, state) => const IdentityScreen(),
        ),
        GoRoute(
          path: '/vehicle-setup',
          builder: (_, _) => const VehicleSetupScreen(),
        ),
        GoRoute(
          path: '/video-verify',
          builder: (_, _) => const VideoVerificationScreen(),
        ),
        GoRoute(
          // مسیر داشبورد حالا به MainScreen (پوسته دارای نویگیشن بار) وصل می‌شود
          path: '/dashboard',
          builder: (_, _) => const MainScreen(),
        ),
        GoRoute(path: '/support', builder: (_, _) => const SupportScreen()),
        GoRoute(
          path: '/ticket-chat',
          builder: (_, state) {
            final id = state.extra as int;
            return TicketChatScreen(ticketId: id);
          },
        ),
        GoRoute(
          path: '/identity-info',
          builder: (_, _) => const IdentityInfoScreen(),
        ),
        GoRoute(
          path: '/vehicle-info',
          builder: (_, _) => const VehicleInfoScreen(),
        ),
        GoRoute(
          path: '/load-details',
          builder: (_, state) {
            final id = state.extra as int;
            return LoadDetailsScreen(loadId: id);
          },
        ),
        GoRoute(
          path: '/search-loads',
          builder: (_, _) => const SearchLoadsScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'AmutBar Driver',
      theme: AppTheme.light(),
      locale: const Locale("fa", "IR"),
      supportedLocales: const [Locale("fa", "IR"), Locale("en", "US")],
      localizationsDelegates: const [
        // Add Localization
        PersianMaterialLocalizations.delegate,
        PersianCupertinoLocalizations.delegate,
        // اگر در بعضی ویجت‌های استاندارد فلاتر به مشکل خوردی، این سه خط پایین رو هم در آینده اضافه کن (نیاز به پکیج flutter_localizations داره)
        // GlobalMaterialLocalizations.delegate,
        // GlobalWidgetsLocalizations.delegate,
        // GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      builder: (context, child) {
        return Directionality(textDirection: TextDirection.rtl, child: child!);
      },
    );
  }
}
