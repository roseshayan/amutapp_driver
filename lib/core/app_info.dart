import 'dart:convert';

/// نگهداری اطلاعات عمومی اپ (نام/ورژن/لوگو/لینک‌ها/پشتیبانی/نگهداری) که از API دریافت می‌شود.
class AppInfoCache {
  static Map<String, dynamic>? _raw;

  static String? _appName;
  static String? _version;
  static String? _siteUrl;

  static String? _logoUrl;
  static String? _faviconUrl;

  static String? _termsUrl;
  static String? _termsText;
  static String? _appDownloadUrl;

  static String? _supportPhone;
  static String? _supportWhatsapp;
  static String? _supportTelegram;

  static bool _maintenanceEnabled = false;
  static String? _maintenanceMessage;

  /// اگر API شما لینک‌ها را با دامنه‌ی لوکال مثل amutbar-admin.test برگرداند
  /// روی موبایل resolve نمی‌شود. اینجا می‌توانیم host را force کنیم.
  /// مثال: http://amutbar-admin.test/...  -> http://192.168.100.3/...
  static String? _forcedBaseHost; // مثل: http://192.168.100.3

  /// ست کردن host اجباری برای نرمال‌سازی URL (اختیاری)
  /// مثال: AppInfoCache.setForcedBaseHost('http://192.168.100.3');
  static void setForcedBaseHost(String? host) {
    if (host == null || host.trim().isEmpty) {
      _forcedBaseHost = null;
      return;
    }
    _forcedBaseHost = host.trim().replaceAll(RegExp(r'\/+$'), '');
  }

  static void setRaw(Map<String, dynamic> raw) {
    _raw = raw;

    _appName = _pickString(raw, const [
      'company_name',
      'site_name',
      'name',
      'app_name',
      'appName',
      'data.company_name',
      'data.site_name',
      'data.name',
      'data.app_name',
      'data.appName',
    ]);

    // اگر نسخه string در آینده اضافه شد، این مسیرها اولویت دارند
    final versionStr = _pickString(raw, const [
      'version',
      'app_version',
      'appVersion',
      'data.version',
      'data.app_version',
      'data.appVersion',
    ]);

    // چون الان در خروجی شما نسخه string نداریم، version_code اندروید رو نمایش می‌دیم
    final vCode = _getByPath(raw, 'app.android.latest_version_code');
    final vCodeStr = (vCode == null) ? null : vCode.toString().trim();

    _version = (versionStr != null && versionStr.trim().isNotEmpty)
        ? versionStr.trim()
        : ((vCodeStr == null || vCodeStr.isEmpty) ? '-' : vCodeStr);

    _siteUrl = _pickString(raw, const ['site_url', 'data.site_url']);

    _logoUrl = _pickString(raw, const ['logo_url', 'data.logo_url']);
    _faviconUrl = _pickString(raw, const ['favicon_url', 'data.favicon_url']);

    _termsUrl = _pickString(raw, const [
      'links.terms_url',
      'data.links.terms_url',
    ]);

    _termsText = _pickString(raw, const [
      'links.terms_text',
      'data.links.terms_text',
    ]);

    _appDownloadUrl = _pickString(raw, const [
      'links.app_download_url',
      'data.links.app_download_url',
    ]);

    _supportPhone = _pickString(raw, const [
      'support.phone',
      'data.support.phone',
    ]);
    _supportWhatsapp = _pickString(raw, const [
      'support.whatsapp',
      'data.support.whatsapp',
    ]);
    _supportTelegram = _pickString(raw, const [
      'support.telegram',
      'data.support.telegram',
    ]);

    final mEnabled = _getByPath(raw, 'maintenance.enabled');
    _maintenanceEnabled = (mEnabled == true) || (mEnabled.toString() == '1');

    _maintenanceMessage = _pickString(raw, const [
      'maintenance.message',
      'data.maintenance.message',
    ]);
  }

  // ---------- Getters ----------
  static String get appName => (_appName == null || _appName!.trim().isEmpty)
      ? 'آموت‌بار رانندگان'
      : _appName!.trim();

  static String get version =>
      (_version == null || _version!.trim().isEmpty) ? '-' : _version!.trim();

  static bool get maintenanceEnabled => _maintenanceEnabled;

  static String get maintenanceMessage =>
      (_maintenanceMessage == null || _maintenanceMessage!.trim().isEmpty)
      ? ''
      : _maintenanceMessage!.trim();

  static String get siteUrl => _normalizeUrl(_siteUrl ?? '');

  static String get logoUrl => _normalizeUrl(_logoUrl ?? '');

  static String get faviconUrl => _normalizeUrl(_faviconUrl ?? '');

  static String get termsUrl => _normalizeUrl(_termsUrl ?? '');

  static String get termsText => (_termsText ?? '').trim();

  static String get appDownloadUrl => _normalizeUrl(_appDownloadUrl ?? '');

  static String get supportPhone => (_supportPhone ?? '').trim();

  static String get supportWhatsapp => (_supportWhatsapp ?? '').trim();

  static String get supportTelegram => (_supportTelegram ?? '').trim();

  static String get rawJson => jsonEncode(_raw ?? <String, dynamic>{});

  static bool get requireNationalSerial {
    // اگر دیتایی از سرور نیومده بود، برای امنیت بیشتر پیش‌فرض رو true می‌ذاریم
    if (_raw == null || _raw!['auth'] == null) return true;

    // مقدار require_national_serial رو از سرور می‌خونیم
    return _raw!['auth']['require_national_serial'] == true ||
        _raw!['auth']['require_national_serial'] == '1';
  }

  static bool get requireVerificationVideo {
    if (_raw == null || _raw!['onboarding'] == null) return false;
    return _raw!['onboarding']['require_verification_video'] == true;
  }

  // ---------- Helpers ----------
  static String? _pickString(Map<String, dynamic> raw, List<String> paths) {
    for (final p in paths) {
      final v = _getByPath(raw, p);
      if (v is String && v.trim().isNotEmpty) return v;
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return null;
  }

  static dynamic _getByPath(Map<String, dynamic> raw, String path) {
    if (!path.contains('.')) return raw[path];
    dynamic cur = raw;
    for (final part in path.split('.')) {
      if (cur is Map<String, dynamic>) {
        cur = cur[part];
      } else {
        return null;
      }
    }
    return cur;
  }

  /// نرمال‌سازی URL:
  /// - اگر forced host تنظیم شده باشد، host URLهای .test را به آن تبدیل می‌کند.
  /// - همچنین اگر site_url شامل .test باشد، و forced host داریم، replace می‌کند.
  static String _normalizeUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return u;

    // اگر URL نسبی بود و siteUrl داشتیم (در خروجی شما معمولا absolute است، ولی محکم کاری)
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      final base = (_forcedBaseHost ?? _siteUrl ?? '').trim().replaceAll(
        RegExp(r'\/+$'),
        '',
      );
      if (base.isEmpty) return u;
      final p = u.startsWith('/') ? u : '/$u';
      return '$base$p';
    }

    // اگر forcedBaseHost داریم و URL روی دامنه‌ی .test یا host دیگری است که روی موبایل resolve نمی‌شود
    if (_forcedBaseHost != null && _forcedBaseHost!.isNotEmpty) {
      // host از site_url
      final s = (_siteUrl ?? '').trim();
      if (s.isNotEmpty) {
        final from = s.replaceAll(RegExp(r'\/+$'), '');
        if (from.isNotEmpty && u.startsWith(from)) {
          return u.replaceFirst(from, _forcedBaseHost!);
        }
      }

      // جایگزینی دامنه‌ی رایج پروژه شما
      // اگر لوگو/fav با amutbar-admin.test برگشته باشد
      return u
          .replaceAll('http://amutbar-admin.test', _forcedBaseHost!)
          .replaceAll('https://amutbar-admin.test', _forcedBaseHost!);
    }

    return u;
  }
}
