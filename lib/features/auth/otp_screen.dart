import 'dart:async';
import 'dart:convert';
import 'dart:io'; // برای تشخیص Platform
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:device_info_plus/device_info_plus.dart'; // پکیج اطلاعات دستگاه
import 'package:sms_autofill/sms_autofill.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';

class OtpScreen extends StatefulWidget {
  final String phone;

  const OtpScreen({super.key, required this.phone});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> with CodeAutoFill {
  static const int _resendCooldownSeconds = 120;

  final _otpCtrl = TextEditingController();
  bool _isLoading = false;

  Timer? _timer;
  int _start = _resendCooldownSeconds;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    startTimer();
    _listenSms();
  }

  @override
  void codeUpdated() {
    // وقتی پیامک دریافت شد، این متد صدا زده می‌شود
    if (code != null && code!.length == 6) {
      setState(() {
        _otpCtrl.text = code!;
      });
      _verify();
    }
  }

  void _listenSms() async {
    await SmsAutoFill().listenForCode();
  }

  void startTimer() {
    _timer?.cancel();
    const oneSec = Duration(seconds: 1);
    _timer = Timer.periodic(oneSec, (Timer timer) {
      if (_start == 0) {
        setState(() {
          timer.cancel();
          _canResend = true;
        });
      } else {
        setState(() {
          _start--;
        });
      }
    });
  }

  String get timerText {
    int minutes = _start ~/ 60;
    int seconds = _start % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  // متد کمکی برای دریافت اطلاعات دستگاه
  Future<Map<String, String>> _getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    String platformName = 'unknown';
    String deviceId = '';

    try {
      if (Platform.isAndroid) {
        platformName = 'android';
        final androidInfo = await deviceInfo.androidInfo;
        // استفاده از id به عنوان شناسه یکتا در اندروید
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        platformName = 'ios';
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? '';
      }
    } catch (e) {
      debugPrint('Error getting device info: $e');
    }

    return {'platform': platformName, 'device_id': deviceId};
  }

  Future<void> _verify() async {
    final code = _otpCtrl.text.trim();
    if (code.length < 6) return;

    setState(() => _isLoading = true);

    try {
      // 1. دریافت اطلاعات دستگاه قبل از ارسال درخواست
      final devInfo = await _getDeviceInfo();

      // 2. ارسال درخواست
      final res = await ApiClient.postJson(AppConstants.verifyOtpEndpoint, {
        'phone': widget.phone,
        'code': code,
        'user_type': 1, // راننده
        'platform': devInfo['platform'], // ارسال پلتفرم
        'device_id': devInfo['device_id'], // ارسال شناسه دستگاه
      });

      String token = '';
      String refreshToken = '';
      if (res['auth'] is Map) {
        token = res['auth']['access_token'] ?? '';
        refreshToken = res['auth']['refresh_token'] ?? '';
      } else if (res['token'] is String) {
        token = res['token'];
      }

      if (token.isNotEmpty) {
        await AppStorage.setToken(token);
        if (refreshToken.isNotEmpty) {
          await AppStorage.setRefreshToken(refreshToken);
        }
        if (res['profile'] != null) {
          await AppStorage.setUserJson(jsonEncode(res['profile']));
        }

        // بررسی وضعیت همه مراحل onboarding، نه فقط احراز هویت.
        bool isIdentityVerified = false;
        bool needsVehicleInfo = false;
        bool needsVideo = false;
        try {
          final driver = res['profile']['driver'];
          if (driver is Map) {
            final vs = driver['verification_status'];
            isIdentityVerified = (vs == 1 || vs == '1');
          }
          final onboarding = res['profile']['onboarding'];
          if (onboarding is Map) {
            needsVehicleInfo = onboarding['needs_vehicle_info'] == true;
            needsVideo = onboarding['needs_verification_video'] == true;
          }
        } catch (_) {}

        if (!mounted) return;

        if (!isIdentityVerified) {
          context.go('/identity');
        } else if (needsVehicleInfo) {
          context.go('/vehicle-setup');
        } else if (needsVideo) {
          context.go('/video-verify');
        } else {
          context.go('/dashboard');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiException ? e.message : 'کد وارد شده صحیح نیست',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resendCode() async {
    setState(() => _isLoading = true);

    try {
      final res = await ApiClient.postJson(AppConstants.sendOtpEndpoint, {
        'phone': widget.phone,
        'user_type': 1,
      });

      // بررسی موفقیت‌آمیز بودن ارسال مجدد
      if (res['ok'] == true) {
        if (mounted) {
          setState(() {
            // تایمر نمایش داده‌شده در اپ باید مثل انقضای OTP همیشه ۲ دقیقه باشد،
            // حتی اگر سرور resend_in_sec را ۶۰ ثانیه برگرداند.
            _start = _resendCooldownSeconds;
            _canResend = false;
          });

          // تایمر فقط زمانی استارت می‌خوره که پیامک واقعاً ارسال شده باشه
          startTimer();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['message'] ?? 'کد تایید ارسال شد'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception(res['message'] ?? 'خطا در ارسال پیامک');
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e is ApiException
            ? e.message
            : 'خطا در ارتباط با سرور. لطفاً دوباره تلاش کنید.';

        // چون خطایی رخ داده، دکمه «ارسال مجدد» هم‌چنان فعال می‌مونه
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpCtrl.dispose();
    SmsAutoFill().unregisterListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تایید شماره همراه'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'کد ارسال شده به ${widget.phone} را وارد کنید',
                style: const TextStyle(fontSize: 16, color: AppTheme.secondary),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => context.pop(),
                child: const Text(
                  'ویرایش شماره',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _otpCtrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  letterSpacing: 8,
                  fontWeight: FontWeight.bold,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: InputDecoration(
                  hintText: '- - - - - -',
                  hintStyle: TextStyle(color: Colors.grey.shade300),
                ),
                onChanged: (val) {
                  if (val.length >= 6)
                    _verify(); // تغییر به ۴ یا ۶ بسته به نیاز
                },
              ),
              const SizedBox(height: 24),
              Center(
                child: _canResend
                    ? TextButton.icon(
                        onPressed: _resendCode,
                        icon: const Icon(Icons.refresh),
                        label: const Text('ارسال مجدد کد'),
                      )
                    : Text(
                        'ارسال مجدد تا $timerText دیگر',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _verify,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('ورود به برنامه'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
