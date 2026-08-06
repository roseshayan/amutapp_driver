class AppConstants {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://amutapp.com/amutadmin',
  );

  static const String appInfoEndpoint =
      '/api/v1/meta/app-config?target_app_id=1';
  static const String sendOtpEndpoint = '/api/v1/auth/request-otp';
  static const String verifyOtpEndpoint = '/api/v1/auth/verify-otp';

  // Auth & Profile
  static const String refreshTokenEndpoint = '/api/v1/auth/refresh';
  static const String logoutEndpoint = '/api/v1/auth/logout';
  static const String verifyIdentityEndpoint = '/api/v1/auth/verify-identity';
  static const String meEndpoint = '/api/v1/me';
  static const String vehicleTypesEndpoint = '/api/v1/meta/vehicle-types';
  static const String provincesEndpoint = '/api/v1/meta/provinces';
  static const String driverProfileEndpoint = '/api/v1/driver/profile';
  static const String driverDocsEndpoint = '/api/v1/driver/docs';
  static const String driverVerificationVideoEndpoint =
      '/api/v1/driver/verification-video';

  // --- اندپوینت‌های جدید حمل و نقل و باربری رانندگان ---
  static const String driverLoadsEndpoint = '/api/v1/driver/loads';
  static const String citiesSearchEndpoint = '/api/v1/meta/cities/search';
  static const String logCallEndpoint = '/api/v1/driver/calls/log';
  static const String driverActivityEndpoint = '/api/v1/driver/activity';
  static const String companyActiveLoadsEndpoint =
      '/api/v1/companies/active-loads';

  // سایر موارد قبلی
  static const String bannersEndpoint = '/api/v1/banners';
  static const String ticketsEndpoint = '/api/v1/support/tickets';
  static const String unreadNotifsCountEndpoint =
      '/api/v1/me/notifications/unread-count';
  static const String notificationsEndpoint = '/api/v1/me/notifications';

  /// متد کمکی برای اصلاح لینک‌هایی که ممکن است نسبی باشند یا هنوز دامنه‌ی تستی داشته باشند
  static String fixUrl(String? url) {
    final raw = url?.trim() ?? '';
    if (raw.isEmpty) return '';

    var fixed = raw;
    for (final localBase in const [
      'http://amutbar-admin.test',
      'https://amutbar-admin.test',
      'http://10.0.2.2/amutbar-admin',
      'https://10.0.2.2/amutbar-admin',
    ]) {
      if (fixed.startsWith(localBase)) {
        fixed = '$baseUrl${fixed.substring(localBase.length)}';
        break;
      }
    }

    final uri = Uri.tryParse(fixed);
    if (uri != null && uri.hasScheme && uri.host.isNotEmpty) {
      return fixed;
    }

    if (fixed.startsWith('//')) {
      return 'https:$fixed';
    }

    if (fixed.startsWith('/')) {
      return '$baseUrl$fixed';
    }

    return '$baseUrl/$fixed';
  }
}
