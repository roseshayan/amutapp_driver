import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';
import '../../core/app_info.dart';

class IdentityScreen extends StatefulWidget {
  const IdentityScreen({super.key});

  @override
  State<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends State<IdentityScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _nationalCodeCtrl = TextEditingController();
  final _birthDateCtrl = TextEditingController();
  final _serialCtrl = TextEditingController();
  bool _isRejected = false;
  String _rejectReason = '';
  int? _selectedYear;
  int? _selectedMonth;
  int? _selectedDay;

  final List<String> _persianMonths = [
    'فروردین',
    'اردیبهشت',
    'خرداد',
    'تیر',
    'مرداد',
    'شهریور',
    'مهر',
    'آبان',
    'آذر',
    'دی',
    'بهمن',
    'اسفند',
  ];
  List<int> get _years =>
      List<int>.generate(106, (i) => (DateTime.now().year - 621) - i);
  List<int> get _days {
    if (_selectedYear == null || _selectedMonth == null) {
      return List<int>.generate(31, (i) => i + 1);
    }

    final count = Jalali(_selectedYear!, _selectedMonth!, 1).monthLength;

    return List<int>.generate(count, (i) => i + 1);
  }

  bool _isLoading = false;

  bool get _requireSerial {
    return AppInfoCache.requireNationalSerial;
  }

  // محاسبه هوشمند تعداد مراحل
  int get _totalSteps {
    return AppInfoCache.requireVerificationVideo ? 3 : 2;
  }

  @override
  void initState() {
    super.initState();
    _checkRejection();
  }

  Future<void> _checkRejection() async {
    final userJson = await AppStorage.getUserJson();
    if (userJson != null) {
      try {
        final data = jsonDecode(userJson);
        final driver = data['driver'];
        if (driver != null) {
          final int vs =
              int.tryParse(driver['verification_status']?.toString() ?? '0') ??
              0;
          if (vs == 2) {
            // 2 = Rejected
            setState(() {
              _isRejected = true;
              _rejectReason =
                  driver['reject_reason'] ??
                  'مدارک شما تایید نشد. لطفا مشخصات را اصلاح کرده و یا با پشتیبانی تماس بگیرید.';
            });
          }
        }
      } catch (_) {}
    }
  }

  void _showSerialGuideDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'راهنمای سریال کارت ملی',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'سریال کارت ملی یک کد ۹ یا ۱۰ رقمی (شامل حروف و اعداد) است که در پشت کارت ملی هوشمند شما درج شده است.',
              textAlign: TextAlign.justify,
              textDirection: TextDirection.rtl,
              style: TextStyle(height: 1.6, fontSize: 13),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: double.infinity,
                height: 160,
                color: Colors.grey.shade200,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.credit_card_rounded,
                      size: 50,
                      color: Colors.grey,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'تصویر پشت کارت ملی',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Image.asset(
                      'assets/images/SerialCardMeliHelp.png',
                      fit: BoxFit.cover,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                minimumSize: const Size(120, 40),
              ),
              child: const Text('متوجه شدم'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_selectedYear == null ||
        _selectedMonth == null ||
        _selectedDay == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لطفاً تاریخ تولد خود را کامل انتخاب کنید.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final String formattedDate =
          '$_selectedYear/${_selectedMonth.toString().padLeft(2, '0')}/${_selectedDay.toString().padLeft(2, '0')}';

      Map<String, dynamic> requestData = {
        'full_name': _nameCtrl.text.trim(),
        'national_code': _nationalCodeCtrl.text.trim(),
        'birth_date': formattedDate,
      };

      if (_requireSerial) requestData['card_serial'] = _serialCtrl.text.trim();

      final res = await ApiClient.postJson(
        AppConstants.verifyIdentityEndpoint,
        requestData,
      );

      if (res['me'] != null)
        await AppStorage.setUserJson(jsonEncode(res['me']));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('احراز هویت با موفقیت انجام شد.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/vehicle-setup');
      }
    } catch (e) {
      if (mounted) {
        final apiError = e is ApiException ? e : null;
        final errorMsg = apiError?.displayMessage ?? 'خطا در احراز هویت';

        if (apiError?.statusCode == 401) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('نشست کاربری منقضی شده. لطفا مجدد وارد شوید.'),
              backgroundColor: Colors.orange,
            ),
          );
          context.go('/auth');
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('احراز هویت'), centerTitle: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isRejected) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              color: Colors.red,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'احراز هویت رد شد',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _rejectReason,
                          style: const TextStyle(
                            color: Colors.red,
                            height: 1.5,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              final phone = AppInfoCache.supportPhone;
                              if (phone.isNotEmpty)
                                launchUrl(Uri.parse('tel:$phone'));
                            },
                            icon: const Icon(
                              Icons.support_agent_rounded,
                              size: 20,
                            ),
                            label: const Text('تماس با پشتیبانی'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                _StepHeader(
                  title: 'مرحله ۱ از $_totalSteps',
                  subtitle: 'تکمیل اطلاعات فردی و شناسنامه‌ای',
                ),
                const SizedBox(height: 16),

                _NiceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'اطلاعات هویتی',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.secondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'لطفاً اطلاعات زیر را دقیقاً مطابق کارت ملی وارد کنید.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // نام
                      const Text(
                        'نام و نام خانوادگی',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                          hintText: 'مثال: محمد محمدی',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (v) =>
                            (v?.isEmpty ?? true) ? 'نام الزامی است' : null,
                      ),
                      const SizedBox(height: 20),

                      // کد ملی
                      const Text(
                        'کد ملی',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nationalCodeCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        decoration: const InputDecoration(
                          hintText: 'مثال: 0012345678',
                          prefixIcon: Icon(Icons.credit_card_rounded),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty)
                            return 'کد ملی الزامی است';
                          if (v.length != 10) return 'کد ملی باید ۱۰ رقم باشد';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // تاریخ تولد
                      const Text(
                        'تاریخ تولد',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<int>(
                              isExpanded: true,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                              ),
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 16,
                                ),
                                hintText: 'روز',
                                hintStyle: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              value: _selectedDay,
                              items: _days
                                  .map(
                                    (d) => DropdownMenuItem(
                                      value: d,
                                      child: Text(
                                        '$d',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _selectedDay = val),
                              validator: (v) => v == null ? 'انتخاب' : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 5,
                            child: DropdownButtonFormField<int>(
                              isExpanded: true,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                              ),
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 16,
                                ),
                                hintText: 'ماه',
                                hintStyle: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              value: _selectedMonth,
                              items: _persianMonths
                                  .asMap()
                                  .entries
                                  .map(
                                    (m) => DropdownMenuItem(
                                      value: m.key + 1,
                                      child: Text(
                                        m.value,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _selectedMonth = val),
                              validator: (v) => v == null ? 'الزامی' : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 4,
                            child: DropdownButtonFormField<int>(
                              isExpanded: true,
                              icon: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                              ),
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 16,
                                ),
                                hintText: 'سال',
                                hintStyle: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              value: _selectedYear,
                              items: _years
                                  .map(
                                    (y) => DropdownMenuItem(
                                      value: y,
                                      child: Text(
                                        '$y',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => _selectedYear = val),
                              validator: (v) => v == null ? 'انتخاب' : null,
                            ),
                          ),
                        ],
                      ),

                      if (_requireSerial) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'سریال پشت کارت ملی (یا کد رهگیری)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _serialCtrl,
                          keyboardType: TextInputType.text,
                          decoration: InputDecoration(
                            hintText: 'A123456789 یا کد رهگیری',
                            prefixIcon: const Icon(
                              Icons.confirmation_number_outlined,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(
                                Icons.help_outline_rounded,
                                color: AppTheme.primary,
                              ),
                              tooltip: 'راهنمای پیدا کردن سریال کارت',
                              onPressed: () => _showSerialGuideDialog(context),
                            ),
                            helperText:
                                'شماره سریال (حرف انگلیسی + عدد) یا کد رهگیری رسید',
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty)
                              return 'سریال کارت الزامی است';
                            if (v.length < 5) return 'سریال معتبر نیست';
                            return null;
                          },
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _submit,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: _isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'تایید و ادامه',
                            style: TextStyle(fontSize: 16),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// اضافه کردن کلاس‌های کمکی برای استایل مشابه
class _StepHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _StepHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.secondary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.person_outline_rounded,
            color: AppTheme.secondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NiceCard extends StatelessWidget {
  final Widget child;

  const _NiceCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: child,
    );
  }
}
