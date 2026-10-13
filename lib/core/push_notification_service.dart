import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'constants.dart';
import 'storage.dart';

class PushNotificationService {
  /// ثبت توکن دستگاه در سرور جهت دریافت پوش‌نوتیفیکیشن
  static Future<bool> registerDeviceToken({
    String appType = 'driver',
    String? token,
  }) async {
    try {
      final authToken = await AppStorage.getToken();
      if (authToken == null || authToken.isEmpty) return false;

      final deviceInfo = DeviceInfoPlugin();
      String platformName = 'unknown';
      String deviceId = '';

      try {
        if (Platform.isAndroid) {
          platformName = 'android';
          final androidInfo = await deviceInfo.androidInfo;
          deviceId = androidInfo.id;
        } else if (Platform.isIOS) {
          platformName = 'ios';
          final iosInfo = await deviceInfo.iosInfo;
          deviceId = iosInfo.identifierForVendor ?? '';
        } else if (kIsWeb) {
          platformName = 'web';
        }
      } catch (e) {
        debugPrint('Error obtaining device info for push: $e');
      }

      if (deviceId.isEmpty) {
        deviceId = await AppStorage.getOrCreateDeviceId();
      }

      final effectiveToken = (token != null && token.isNotEmpty)
          ? token
          : 'device_$deviceId';

      final res = await ApiClient.postJson(AppConstants.devicePushTokenEndpoint, {
        'push_token': effectiveToken,
        'platform': platformName,
        'app_type': appType,
        'device_id': deviceId,
      });

      if (res['ok'] == true) {
        await AppStorage.setPushToken(effectiveToken);
        return true;
      }
    } catch (e) {
      debugPrint('Register push token failed: $e');
    }
    return false;
  }

  /// غیرفعال کردن توکن هنگام خروج
  static Future<void> unregisterDeviceToken() async {
    try {
      final currentToken = await AppStorage.getPushToken();
      if (currentToken != null && currentToken.isNotEmpty) {
        await ApiClient.deleteJson(AppConstants.devicePushTokenEndpoint, {
          'push_token': currentToken,
        });
        await AppStorage.clearPushToken();
      }
    } catch (e) {
      debugPrint('Unregister push token failed: $e');
    }
  }
}
