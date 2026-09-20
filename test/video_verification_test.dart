import 'package:amutbar_driver/core/api_client.dart';
import 'package:amutbar_driver/core/constants.dart';
import 'package:amutbar_driver/features/onboarding/video_verification_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  bool required = true;
  bool fail = false;
  setUp(() {
    required = true;
    fail = false;
    ApiClient.dio.interceptors.clear();
    ApiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          final data = request.path == AppConstants.appInfoEndpoint
              ? <String, dynamic>{
                  'ok': !fail,
                  'message': 'خطای آزمایشی',
                  'verification': {
                    'video_guide_url': 'storage/uploads/system/guide_test.mp4',
                    'video_guide_text':
                        'ابتدا راهنما را ببینید و سپس ضبط کنید.',
                    'video_phrase_template': 'اینجانب {full_name} موافقم.',
                    'video_max_seconds': 10,
                  },
                }
              : <String, dynamic>{
                  'ok': true,
                  'user': {'full_name': 'کاربر آزمایشی'},
                  'onboarding': {'needs_verification_video': required},
                };
          handler.resolve(
            Response(requestOptions: request, statusCode: 200, data: data),
          );
        },
      ),
    );
  });

  Widget app() => MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: '/video-verify',
      routes: [
        GoRoute(
          path: '/video-verify',
          builder: (_, _) => const VideoVerificationScreen(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const Scaffold(body: Text('dashboard')),
        ),
      ],
    ),
  );

  testWidgets(
    'guide is available before camera access and has a personalized phrase',
    (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(
        find.text('ابتدا راهنما را ببینید و سپس ضبط کنید.'),
        findsOneWidget,
      );
      expect(find.text('مشاهده ویدئوی آموزشی نحوه احراز هویت'), findsOneWidget);
      expect(find.text('اینجانب کاربر آزمایشی موافقم.'), findsOneWidget);
      expect(find.text('فعال کردن دوربین'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('server disabling the step exits without opening camera', (
    tester,
  ) async {
    required = false;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('dashboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'configuration failure is retryable and cannot skip verification',
    (tester) async {
      fail = true;
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('تلاش مجدد'), findsOneWidget);
      expect(find.text('dashboard'), findsNothing);
      fail = false;
      await tester.tap(find.text('تلاش مجدد'));
      await tester.pumpAndSettle();
      expect(find.text('فعال کردن دوربین'), findsOneWidget);
    },
  );
}
