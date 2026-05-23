import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/api_client.dart';
import '../../core/app_info.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';

class VehicleSetupScreen extends StatefulWidget {
  const VehicleSetupScreen({super.key});

  @override
  State<VehicleSetupScreen> createState() => _VehicleSetupScreenState();
}

class _VehicleSetupScreenState extends State<VehicleSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;

  Map<String, dynamic>? _me;
  List<Map<String, dynamic>> _vehicleTypes = [];

  int? _selectedVehicleTypeId;
  String _plateValue = '';

  File? _licenseImage;
  File? _vehicleCardImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<bool> _ensurePermission(ImageSource source) async {
    if (source == ImageSource.camera) {
      final st = await Permission.camera.request();
      return st.isGranted;
    }

    // گالری
    final p1 = await Permission.photos.request();
    if (p1.isGranted) return true;
    final p2 = await Permission.storage.request();
    return p2.isGranted;
  }

  Future<void> _pickFor(String key, ImageSource source) async {
    final ok = await _ensurePermission(source);
    if (!ok) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اجازه دسترسی لازم داده نشد.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final x = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
    );
    if (x == null) return;

    setState(() {
      if (key == 'license') _licenseImage = File(x.path);
      if (key == 'vehicle_card') _vehicleCardImage = File(x.path);
    });
  }

  Future<void> _uploadDocs() async {
    if (_licenseImage == null && _vehicleCardImage == null) return;

    final files = <String, File>{};
    if (_licenseImage != null) files['license_image'] = _licenseImage!;
    if (_vehicleCardImage != null)
      files['vehicle_card_image'] = _vehicleCardImage!;

    final res = await ApiClient.postMultipartFiles(
      AppConstants.driverDocsEndpoint,
      files: files,
    );

    if (res['ok'] != true) {
      final msg = (res['message'] ?? 'خطا در آپلود مدارک').toString();
      throw Exception(msg);
    }
  }

  Future<void> _boot() async {
    setState(() => _loading = true);
    try {
      final me = await ApiClient.getJson(AppConstants.meEndpoint);
      final vt = await ApiClient.getJson(AppConstants.vehicleTypesEndpoint);

      final driver = (me['driver'] is Map) ? me['driver'] as Map : null;
      final vtid = (driver?['vehicle_type_id'] ?? 0);
      final plate = (driver?['plate_number'] ?? '').toString();

      final itemsRaw = (vt['items'] is List)
          ? vt['items'] as List
          : <dynamic>[];
      final items = itemsRaw
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();

      setState(() {
        _me = me;
        _vehicleTypes = items;
        _selectedVehicleTypeId = (vtid is int && vtid > 0) ? vtid : null;
        _plateValue = plate;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('خطا در دریافت اطلاعات خودرو.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // گرفتن آیکون بر اساس اسم ماشین برای جذابیت بصری در لیست
  IconData _getVehicleIcon(String title) {
    if (title.contains('وانت') ||
        title.contains('پیکان') ||
        title.contains('نیسان'))
      return Icons.fire_truck;
    if (title.contains('خاور') || title.contains('کامیونت'))
      return Icons.fire_truck_outlined;
    if (title.contains('تریلی') ||
        title.contains('کامیون') ||
        title.contains('جفت'))
      return Icons.airport_shuttle_outlined;
    return Icons.directions_car_filled_outlined;
  }

  List<DropdownMenuItem<int>> _buildVehicleTypeItems() {
    final byParent = <int?, List<Map<String, dynamic>>>{};
    final childrenCount = <int, int>{};

    for (final it in _vehicleTypes) {
      final id = (it['id'] is int) ? it['id'] as int : 0;
      final pid = (it['parent_id'] is int) ? it['parent_id'] as int : null;
      if (id > 0) {
        byParent.putIfAbsent(pid, () => []).add(it);
        if (pid != null) {
          childrenCount[pid] = (childrenCount[pid] ?? 0) + 1;
        }
      }
    }

    int sortKey(Map<String, dynamic> a) => (a['sort'] is int)
        ? a['sort'] as int
        : ((a['id'] is int) ? a['id'] as int : 0);

    final out = <DropdownMenuItem<int>>[];

    void addGroup(int? parentId, String prefix) {
      final group = (byParent[parentId] ?? [])
        ..sort((a, b) => sortKey(a).compareTo(sortKey(b)));
      for (final it in group) {
        final id = (it['id'] is int) ? it['id'] as int : 0;
        final title = (it['title'] ?? '').toString();
        final hasChild = (childrenCount[id] ?? 0) > 0;
        final pid = (it['parent_id'] is int) ? it['parent_id'] as int : null;

        final selectable = !hasChild;
        final isChild = pid != null;

        // اگر سرگروه است و فرزند دارد، فقط نمایش بده (غیرفعال)
        if (!isChild && hasChild) {
          out.add(
            DropdownMenuItem<int>(
              value: id,
              enabled: false,
              child: Text(
                title,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
          addGroup(id, '   • ');
          continue;
        }

        // اگر برگ است (زیرگروه یا آیتم بدون فرزند) با آیکون اختصاصی نمایش بده
        if (selectable) {
          out.add(
            DropdownMenuItem<int>(
              value: id,
              child: Row(
                children: [
                  Icon(
                    _getVehicleIcon(title),
                    color: Colors.grey.shade600,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(prefix + title),
                ],
              ),
            ),
          );
        } else {
          out.add(
            DropdownMenuItem<int>(
              value: id,
              enabled: false,
              child: Text(
                prefix + title,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
          addGroup(id, '$prefix   • ');
        }
      }
    }

    addGroup(null, '');
    return out;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_me == null) return;

    if (_selectedVehicleTypeId == null ||
        _plateValue.isEmpty ||
        _plateValue.split(' ').length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('نوع خودرو و شماره پلاک الزامی است')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final user = (_me!['user'] is Map)
          ? _me!['user'] as Map
          : <dynamic, dynamic>{};
      final driver = (_me!['driver'] is Map)
          ? _me!['driver'] as Map
          : <dynamic, dynamic>{};
      final fullName = (user['full_name'] ?? '').toString();
      final nationalCode =
          ((user['code_meli'] ??
                      user['national_code'] ??
                      driver['national_code']) ??
                  '')
              .toString();

      final res = await ApiClient.postJson(AppConstants.driverProfileEndpoint, {
        'full_name': fullName,
        'national_code': nationalCode,
        'vehicle_type_id': _selectedVehicleTypeId,
        'plate_number': _plateValue.trim(),
      });

      if (mounted) {
        if (res['ok'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('اطلاعات خودرو ذخیره شد.'),
              backgroundColor: Colors.green,
            ),
          );

          try {
            await _uploadDocs();
            if (!mounted) return;
            if (_licenseImage != null || _vehicleCardImage != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('مدارک با موفقیت آپلود شد.'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(e.toString()),
                backgroundColor: Colors.red,
              ),
            );
            return;
          }

          if (AppInfoCache.requireVerificationVideo) {
            context.go('/video-verify');
          } else {
            context.go('/dashboard');
          }
        } else {
          final msg = (res['message'] ?? 'خطا در ذخیره اطلاعات').toString();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در ذخیره اطلاعات (کد ملی یا پلاک تکراری است)'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ثبت مشخصات خودرو'), centerTitle: true),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _StepHeader(
                        title: 'مرحله ۲ از ۳',
                        subtitle: 'ثبت نوع خودرو و پلاک برای ادامه احراز هویت',
                      ),
                      const SizedBox(height: 16),

                      _NiceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'اطلاعات وسیله نقلیه',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.secondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'فقط زیرگروه‌ها قابل انتخاب هستند. پلاک را دقیقاً مطابق نمونه وارد کنید.',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 18),

                            const Text(
                              'نوع وسیله نقلیه',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              value: _selectedVehicleTypeId,
                              items: _buildVehicleTypeItems(),
                              decoration: InputDecoration(
                                hintText: 'انتخاب کنید',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(
                                      () => _selectedVehicleTypeId = v,
                                    ),
                              validator: (v) => (v == null || v <= 0)
                                  ? 'نوع وسیله نقلیه الزامی است'
                                  : null,
                            ),
                            const SizedBox(height: 18),

                            const Text(
                              'پلاک',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),

                            // استفاده از کلاس پلاک گرافیکی
                            IranianPlateField(
                              initialValue: _plateValue,
                              onChanged: (v) => _plateValue = v,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),

                      _NiceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'مدارک (اختیاری ولی پیشنهاد می‌شود)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _DocPickerCard(
                              title: 'عکس گواهینامه',
                              file: _licenseImage,
                              onCamera: _saving
                                  ? null
                                  : () =>
                                        _pickFor('license', ImageSource.camera),
                              onGallery: _saving
                                  ? null
                                  : () => _pickFor(
                                      'license',
                                      ImageSource.gallery,
                                    ),
                              onClear: _saving
                                  ? null
                                  : () => setState(() => _licenseImage = null),
                            ),
                            const SizedBox(height: 12),
                            _DocPickerCard(
                              title: 'عکس کارت ماشین',
                              file: _vehicleCardImage,
                              onCamera: _saving
                                  ? null
                                  : () => _pickFor(
                                      'vehicle_card',
                                      ImageSource.camera,
                                    ),
                              onGallery: _saving
                                  ? null
                                  : () => _pickFor(
                                      'vehicle_card',
                                      ImageSource.gallery,
                                    ),
                              onClear: _saving
                                  ? null
                                  : () => setState(
                                      () => _vehicleCardImage = null,
                                    ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: _saving
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('ذخیره و ادامه'),
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
            Icons.directions_car_filled_outlined,
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

// ==========================================
// ویجت گرافیکی، واقعی و کاملاً ریسپانسیو پلاک ایرانی
// ==========================================
class IranianPlateField extends StatefulWidget {
  final String initialValue;
  final bool enabled;
  final ValueChanged<String> onChanged;
  final String? Function(String?)? validator;

  const IranianPlateField({
    super.key,
    required this.initialValue,
    this.enabled = true,
    required this.onChanged,
    this.validator,
  });

  @override
  State<IranianPlateField> createState() => _IranianPlateFieldState();
}

class _IranianPlateFieldState extends State<IranianPlateField> {
  final _p1 = TextEditingController(); // 2 digits left
  final _p3 = TextEditingController(); // 3 digits
  final _p4 = TextEditingController(); // 2 digits right (Iran)
  String _letter = 'ب';

  @override
  void initState() {
    super.initState();
    _hydrate(widget.initialValue);
  }

  @override
  void dispose() {
    _p1.dispose();
    _p3.dispose();
    _p4.dispose();
    super.dispose();
  }

  void _hydrate(String raw) {
    final cleaned = raw
        .replaceAll('ایران', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final m = RegExp(
      r'^(\d{2})\s*([آاأبپتثجچحخدذرزژسشصضطظعغفقکگلمنوهی])\s*(\d{3})\s*(\d{2})$',
    ).firstMatch(cleaned);
    if (m != null) {
      _p1.text = m.group(1) ?? '';
      _letter = m.group(2) ?? 'ب';
      _p3.text = m.group(3) ?? '';
      _p4.text = m.group(4) ?? '';
    }
  }

  void _emit() {
    final a = _p1.text;
    final c = _p3.text;
    final d = _p4.text;
    widget.onChanged('$a $_letter $c ایران $d');
  }

  // متد کمکی برای ساخت فیلدهای متنی پلاک
  Widget _buildNumField(
    TextEditingController ctrl,
    int length, {
    bool isIranPart = false,
  }) {
    return TextField(
      controller: ctrl,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: length,
      style: TextStyle(
        fontSize: isIranPart ? 16 : 18, // سایز منعطف‌تر برای جلوگیری از شکستگی
        fontWeight: FontWeight.bold,
        fontFamily: 'Vazir',
        color: Colors.black87,
      ),
      decoration: InputDecoration(
        counterText: '',
        border: InputBorder.none,
        isDense: true, // فشردگی محتوا برای گوشی‌های کوچک
        contentPadding: EdgeInsets.only(bottom: isIranPart ? 4 : 0),
      ),
      onChanged: (_) => _emit(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FormField<String>(
      validator: (_) {
        if (_p1.text.length != 2 ||
            _p3.text.length != 3 ||
            _p4.text.length != 2) {
          return 'لطفاً پلاک را به صورت کامل وارد کنید';
        }
        if (widget.validator != null) {
          return widget.validator!(
            '${_p1.text} $_letter ${_p3.text} ایران ${_p4.text}',
          );
        }
        return null;
      },
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: state.hasError ? Colors.red : Colors.black87,
                  width: 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                textDirection: TextDirection.ltr, // اجبار به چپ‌چین
                children: [
                  // 1. بخش آبی رنگ (پرچم)
                  Container(
                    width: 35, // عرض ثابت و جمع‌وجور
                    decoration: BoxDecoration(
                      color: Colors.blue.shade800,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        bottomLeft: Radius.circular(4),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          height: 12,
                          width: 18,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white70,
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Expanded(child: Container(color: Colors.green)),
                              Expanded(child: Container(color: Colors.white)),
                              Expanded(child: Container(color: Colors.red)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'I.R.\nIRAN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 7, // سایز بهینه
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  // 2. دو رقم سمت چپ (سهم مساوی)
                  Expanded(flex: 3, child: _buildNumField(_p1, 2)),

                  // 3. دراپ‌دان حروف (سهم مساوی)
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      value: _letter,
                      iconSize: 0,
                      // مخفی کردن فلش برای زیبایی
                      isExpanded: true,
                      // بسیار مهم: جلوگیری از خطای Overflow
                      alignment: Alignment.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                        fontFamily: 'Vazir',
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      items:
                          [
                                'الف',
                                'ب',
                                'پ',
                                'ت',
                                'ث',
                                'ج',
                                'چ',
                                'ح',
                                'خ',
                                'د',
                                'ذ',
                                'ر',
                                'ز',
                                'ژ',
                                'س',
                                'ش',
                                'ص',
                                'ض',
                                'ط',
                                'ظ',
                                'ع',
                                'غ',
                                'ف',
                                'ق',
                                'ک',
                                'گ',
                                'ل',
                                'م',
                                'ن',
                                'و',
                                'ه',
                                'ی',
                              ]
                              .map(
                                (l) => DropdownMenuItem(
                                  value: l,
                                  alignment: Alignment.center,
                                  child: Text(l),
                                ),
                              )
                              .toList(),
                      onChanged: widget.enabled
                          ? (v) {
                              setState(() => _letter = v ?? 'ب');
                              _emit();
                            }
                          : null,
                    ),
                  ),

                  // 4. سه رقم وسط (سهم بیشتر چون 3 رقم است)
                  Expanded(flex: 4, child: _buildNumField(_p3, 3)),

                  // 5. خط جداکننده مشکی
                  const VerticalDivider(
                    color: Colors.black87,
                    width: 1,
                    thickness: 1.5,
                  ),

                  // 6. قسمت راست (ایران + 2 رقم) (سهم مساوی)
                  Expanded(
                    flex: 3,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'ایران',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Expanded(
                          child: _buildNumField(_p4, 2, isIranPart: true),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 4),
                child: Text(
                  state.errorText ?? '',
                  style: const TextStyle(color: Colors.red, fontSize: 11),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DocPickerCard extends StatelessWidget {
  final String title;
  final File? file;
  final VoidCallback? onCamera;
  final VoidCallback? onGallery;
  final VoidCallback? onClear;

  const _DocPickerCard({
    required this.title,
    required this.file,
    required this.onCamera,
    required this.onGallery,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (file != null)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.delete_outline_rounded),
                  tooltip: 'حذف',
                ),
            ],
          ),
          if (file == null)
            Text(
              'می‌توانید با دوربین عکس بگیرید یا از گالری انتخاب کنید.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          const SizedBox(height: 10),
          if (file != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                file!,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          if (file != null) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCamera,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('دوربین'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('گالری'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
