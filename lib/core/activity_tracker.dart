import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api_client.dart';
import 'constants.dart';
import 'storage.dart';

/// ثبت جزئی رفتار راننده داخل اپ.
/// این سرویس عمداً best-effort است؛ اگر اینترنت یا API خطا داد، تجربه راننده نباید خراب شود.
class ActivityTracker {
  ActivityTracker._();

  static PackageInfo? _packageInfo;

  static String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  static Future<PackageInfo?> _info() async {
    if (_packageInfo != null) return _packageInfo;
    try {
      _packageInfo = await PackageInfo.fromPlatform();
      return _packageInfo;
    } catch (_) {
      return null;
    }
  }

  static String _clientEventId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final rnd = Random().nextInt(1 << 32).toRadixString(16);
    return '$now-$rnd';
  }

  static void track({
    required String eventKey,
    String? eventTitle,
    String? screenKey,
    String? screenTitle,
    String? entityType,
    int? entityId,
    int? loadId,
    int? companyId,
    int? ticketId,
    Map<String, dynamic>? payload,
  }) {
    unawaited(
      trackNow(
        eventKey: eventKey,
        eventTitle: eventTitle,
        screenKey: screenKey,
        screenTitle: screenTitle,
        entityType: entityType,
        entityId: entityId,
        loadId: loadId,
        companyId: companyId,
        ticketId: ticketId,
        payload: payload,
      ),
    );
  }

  static Future<void> trackNow({
    required String eventKey,
    String? eventTitle,
    String? screenKey,
    String? screenTitle,
    String? entityType,
    int? entityId,
    int? loadId,
    int? companyId,
    int? ticketId,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final info = await _info();
      final deviceId = await AppStorage.getOrCreateDeviceId();
      final versionCode = int.tryParse(info?.buildNumber ?? '');

      final event = <String, dynamic>{
        'event_key': eventKey,
        if (eventTitle != null && eventTitle.trim().isNotEmpty)
          'event_title': eventTitle.trim(),
        if (screenKey != null && screenKey.trim().isNotEmpty)
          'screen_key': screenKey.trim(),
        if (screenTitle != null && screenTitle.trim().isNotEmpty)
          'screen_title': screenTitle.trim(),
        if (entityType != null && entityType.trim().isNotEmpty)
          'entity_type': entityType.trim(),
        if (entityId != null && entityId > 0) 'entity_id': entityId,
        if (loadId != null && loadId > 0) 'load_id': loadId,
        if (companyId != null && companyId > 0) 'company_id': companyId,
        if (ticketId != null && ticketId > 0) 'ticket_id': ticketId,
        'client_event_id': _clientEventId(),
        'occurred_at': DateTime.now().toIso8601String(),
        if (payload != null && payload.isNotEmpty) 'payload': payload,
      };

      await ApiClient.postJson(AppConstants.driverActivityEndpoint, {
        'client_platform': _platform,
        if (versionCode != null) 'client_version_code': versionCode,
        if ((info?.version ?? '').isNotEmpty) 'app_version_name': info!.version,
        'device_id': deviceId,
        'events': [event],
      });
    } catch (_) {
      // ignore: logging must not break UX
    }
  }
}
