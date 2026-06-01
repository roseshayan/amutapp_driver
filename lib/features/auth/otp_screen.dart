import 'dart:async';
import 'dart:convert';
import 'dart:io'; // برای تشخیص Platform
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:device_info_plus/device_info_plus.dart'; // پکیج اطلاعات دستگاه
import 'package:alt_sms_autofill/alt_sms_autofill.dart';
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

class _OtpScreenState extends State<OtpScreen> {
  final _otpCtrl = TextEditingController();
  bool _isLoading = false;

  Timer? _timer;
  int _start = 120;
  bool _canResend = false;
  String? _comingSms;

  @override
  void initState() {
    super.initState();
    startTimer();
    _initSmsListener();
  }

  Future<void> _initSmsListener() async {
    if (!Platform.isAndroid) return;

    try {
      AltSmsAutofill().listenForSms.then((value) {
        if (value != null && mounted) {
          debugPrint("SMS Received: $value");
          // استخراج کد ۶ رقمی با ریجکس
          // قالب: code : 123456
          final RegExp regExp = RegExp(r"code\s*:\s*(\d{6})");
          final match = regExp.firstMatch(value);
          if (match != null) {
            final code = match.group(1);
            if (code != null) {
              setState(() {
                _otpCtrl.text = code;
              });
              // ارسال خودکار برای تایید
              _verify();
            }
          }
        }
      });
    } catch (e) {
      debugPrint("Sms listener error: $e");
    }
  }

  void startTimer() {
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

        // بررسی وضعیت احراز هویت
        bool isIdentityVerified = false;
        try {
          // وضعیت احراز از پروفایل راننده
          final driver = res['profile']['driver'];
          if (driver is Map) {
            final vs = driver['verification_status'];
            isIdentityVerified = (vs == 1 || vs == '1');
          }
        } catch (_) {}

        if (!mounted) return;

        if (isIdentityVerified) {
          // اگر قبلا احراز شده، برو داشبورد
          context.go('/dashboard');
        } else {
          // اگر جدید است یا احراز نشده، برو صفحه احراز هویت
          context.go('/identity');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('کد وارد شده صحیح نیست')));
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
          // گرفتن زمان انتظار از سرور (اگر نداد همون 120 ثانیه پیش‌فرض)
          final int resendTime = res['resend_in_sec'] ?? 120;

          setState(() {
            _start = resendTime;
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
        String errorMsg = 'خطا در ارتباط با سرور. لطفاً دوباره تلاش کنید.';
        String errStr = e.toString();

        if (errStr.contains('message:')) {
          errorMsg = errStr
              .split('message:')[1]
              .split(',')[0]
              .replaceAll('}', '')
              .trim();
        } else if (errStr.contains('Exception:')) {
          errorMsg = errStr.replaceAll('Exception:', '').trim();
        }

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
    if (Platform.isAndroid) {
      AltSmsAutofill().unregisterListener();
    }
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
