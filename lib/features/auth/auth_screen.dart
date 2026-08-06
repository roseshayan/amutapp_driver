import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/app_info.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../onboarding/terms_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phoneCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _showClear = false; // وضعیت نمایش دکمه ضربدر

  @override
  void initState() {
    super.initState();
    // لیسنر برای نمایش/مخفی کردن دکمه ضربدر
    _phoneCtrl.addListener(() {
      final shouldShow = _phoneCtrl.text.isNotEmpty;
      if (_showClear != shouldShow) {
        setState(() => _showClear = shouldShow);
      }
    });
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    final phone = _phoneCtrl.text.trim();

    try {
      final res = await ApiClient.postJson(AppConstants.sendOtpEndpoint, {
        'phone': phone,
        'user_type': 1,
      });

      // بررسی می‌کنیم که سرور حتماً وضعیت ok رو برگردونده باشه
      if (res['ok'] == true) {
        if (mounted) {
          // فقط در صورت ارسال موفق، کاربر رو به صفحه وارد کردن کد بفرست
          context.push('/otp', extra: phone);
        }
      } else {
        // اگر ok نبود، پیام خطای بک‌اند رو بگیر و به بخش catch پرتاب کن
        throw Exception(res['message'] ?? 'خطا در ارسال پیامک');
      }
    } catch (e) {
      if (mounted) {
        final errorMsg = e is ApiException
            ? e.message
            : 'خطا در ارسال پیامک. لطفاً مجدد تلاش کنید.';

        // نمایش ارور دقیق به کاربر
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

  Future<void> _openTerms() async {
    // نمایش loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await ApiClient.getJson(AppConstants.appInfoEndpoint);
      AppInfoCache.setRaw(response);
    } catch (e) {
      debugPrint('Error fetching terms: $e');
    }

    // بستن loading
    if (mounted) {
      Navigator.pop(context); // حذف dialog loading

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TermsAndConditionsScreen(
            termsText: AppInfoCache.termsText.isNotEmpty
                ? AppInfoCache.termsText
                : "متنی دریافت نشد",
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final logoUrl = AppInfoCache.logoUrl;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),

                    // لوگو
                    Center(
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 15,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(12),
                        child: ClipOval(child: _buildLogoImage(logoUrl)),
                      ),
                    ),

                    const SizedBox(height: 24),
                    const Text(
                      'ورود راننده',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.secondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'برای مشاهده بارها شماره موبایل خود را وارد کنید',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // ورودی شماره موبایل (بدون پرش)
                    const Text(
                      'شماره موبایل',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),

                    // استفاده از Directionality برای ثابت نگه داشتن جهت متن روی LTR (چپ به راست)
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: TextFormField(
                        controller: _phoneCtrl,
                        // همیشه چپ‌چین باشد تا پرش نداشته باشد
                        textAlign: TextAlign.left,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                        decoration: InputDecoration(
                          hintText: 'مثال: 09123456789',
                          // هینت هم چپ‌چین باشد که با اعداد هماهنگ شود
                          hintTextDirection: TextDirection.ltr,
                          prefixIcon: const Icon(Icons.phone_android_rounded),
                          // دکمه ضربدر برای پاک کردن
                          suffixIcon: _showClear
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () => _phoneCtrl.clear(),
                                )
                              : null,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty)
                            return 'شماره موبایل الزامی است';
                          if (value.length < 11 || !value.startsWith('09'))
                            return 'شماره موبایل نامعتبر است';
                          return null;
                        },
                      ),
                    ),

                    const SizedBox(height: 24),

                    // دکمه ورود
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('دریافت کد تایید'),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // بخش لینک قوانین و مقررات
                    Center(
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          Text(
                            "با ورود یا ثبت‌نام، ",
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.6),
                              fontSize: 12,
                            ),
                          ),
                          GestureDetector(
                            onTap: _openTerms, // اینجا تغییر کرد
                            child: Text(
                              "قوانین و مقررات آموت بار",
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                          Text(
                            " را می‌پذیرم.",
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withOpacity(0.6),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoImage(String url) {
    if (url.isEmpty) {
      return const Icon(
        Icons.local_shipping_outlined,
        size: 60,
        color: AppTheme.primary,
      );
    }
    return Image.network(
      url,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const Icon(
        Icons.local_shipping_outlined,
        size: 60,
        color: Colors.grey,
      ),
    );
  }
}
