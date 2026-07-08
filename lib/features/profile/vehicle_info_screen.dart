import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import '../../core/activity_tracker.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/storage.dart';

class VehicleInfoScreen extends StatefulWidget {
  const VehicleInfoScreen({super.key});

  @override
  State<VehicleInfoScreen> createState() => _VehicleInfoScreenState();
}

class _VehicleInfoScreenState extends State<VehicleInfoScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic>? _user;
  Map<String, dynamic>? _driver;
  List<dynamic> _vehicleTypes = [];

  int? _selectedVehicleTypeId;
  String _plateValue = '';

  final _smartCardCtrl = TextEditingController();
  final _modelYearCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _vinCtrl = TextEditingController();
  final _engineCtrl = TextEditingController();
  final _chassisCtrl = TextEditingController();
  final _insuranceNoCtrl = TextEditingController();
  final _insuranceExpiryCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    ActivityTracker.track(
      eventKey: 'vehicle_info_view',
      screenKey: 'vehicle_info',
      screenTitle: 'مشخصات خودرو و بارگیر',
    );
    _loadData();
  }

  @override
  void dispose() {
    _smartCardCtrl.dispose();
    _modelYearCtrl.dispose();
    _colorCtrl.dispose();
    _capacityCtrl.dispose();
    _vinCtrl.dispose();
    _engineCtrl.dispose();
    _chassisCtrl.dispose();
    _insuranceNoCtrl.dispose();
    _insuranceExpiryCtrl.dispose();
    super.dispose();
  }

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  void _hydrateFromProfile(Map<String, dynamic> data) {
    final isProfileShape = data.containsKey('user') || data.containsKey('driver');
    final user = isProfileShape ? data['user'] : null;
    final driver = isProfileShape ? data['driver'] : data;

    _user = user is Map ? Map<String, dynamic>.from(user) : _user;
    _driver = driver is Map ? Map<String, dynamic>.from(driver) : null;

    if (_driver == null) return;

    _selectedVehicleTypeId = _asInt(_driver!['vehicle_type_id']);
    _smartCardCtrl.text = _driver!['smart_card_number']?.toString() ?? '';
    _modelYearCtrl.text = _driver!['model_year']?.toString() ?? '';
    _colorCtrl.text = _driver!['color']?.toString() ?? '';
    _capacityCtrl.text = _driver!['capacity_kg']?.toString() ?? '';
    _vinCtrl.text = _driver!['vin_number']?.toString() ?? '';
    _engineCtrl.text = _driver!['engine_number']?.toString() ?? '';
    _chassisCtrl.text = _driver!['chassis_number']?.toString() ?? '';
    _insuranceNoCtrl.text = _driver!['insurance_number']?.toString() ?? '';
    _insuranceExpiryCtrl.text =
        _driver!['insurance_expiry']?.toString() ?? '';
    _plateValue = _driver!['plate_number']?.toString() ?? '';
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final userJson = await AppStorage.getUserJson();
      if (userJson != null && userJson.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(userJson);
          if (decoded is Map) {
            _hydrateFromProfile(Map<String, dynamic>.from(decoded));
          }
        } catch (e) {
          debugPrint('Invalid cached profile json: $e');
        }
      }

      try {
        final fresh = await ApiClient.getJson(AppConstants.meEndpoint);
        if (fresh['ok'] == true) {
          _hydrateFromProfile(fresh);
          await AppStorage.setUserJson(jsonEncode(fresh));
        }
      } catch (e) {
        debugPrint('Fresh profile load failed: $e');
      }

      try {
        final res = await ApiClient.getJson(AppConstants.vehicleTypesEndpoint);
        if (res['ok'] == true && res['items'] is List) {
          _vehicleTypes = (res['items'] as List)
              .whereType<Map>()
              .map((e) {
                final item = Map<String, dynamic>.from(e);
                item['id'] = _asInt(item['id']);
                return item;
              })
              .where((e) => e['id'] != null)
              .toList();
        }
      } catch (e) {
        debugPrint('Vehicle types load failed: $e');
      }

      final ids = _vehicleTypes
          .map((e) => _asInt(e['id']))
          .whereType<int>()
          .toSet();
      if (_selectedVehicleTypeId != null &&
          !ids.contains(_selectedVehicleTypeId)) {
        _selectedVehicleTypeId = null;
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickInsuranceExpiry() async {
    FocusScope.of(context).unfocus();
    Jalali? picked = await showPersianDatePicker(
      context: context,
      initialDate: Jalali.now(),
      firstDate: Jalali.now(),
      lastDate: Jalali(1450, 1, 1),
    );
    if (picked != null) {
      setState(() {
        _insuranceExpiryCtrl.text =
            '${picked.year}/${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  // گرفتن آیکون بر اساس اسم ماشین
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

  Future<void> _save() async {
    if (_selectedVehicleTypeId == null ||
        _plateValue.isEmpty ||
        _plateValue.split(' ').length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('نوع خودرو و شماره پلاک الزامی است')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final requestData = {
        'full_name': _user?['full_name'] ?? _driver?['full_name'] ?? '',
        'national_code':
            _user?['code_meli'] ??
            _user?['national_code'] ??
            _driver?['national_code'] ??
            '',
        'province_id': _driver?['province_id'] ?? '',
        'city_id': _driver?['city_id'] ?? '',
        'vehicle_type_id': _selectedVehicleTypeId,
        'plate_number': _plateValue,
        'smart_card_number': _smartCardCtrl.text,
        'model_year': _modelYearCtrl.text,
        'color': _colorCtrl.text,
        'capacity_kg': _capacityCtrl.text,
        'vin_number': _vinCtrl.text,
        'engine_number': _engineCtrl.text,
        'chassis_number': _chassisCtrl.text,
        'insurance_number': _insuranceNoCtrl.text,
        'insurance_expiry': _insuranceExpiryCtrl.text,
      };

      final res = await ApiClient.postJson(
        AppConstants.driverProfileEndpoint,
        requestData,
      );

      if (res['ok'] == true) {
        ActivityTracker.track(
          eventKey: 'vehicle_info_update',
          screenKey: 'vehicle_info',
          screenTitle: 'مشخصات خودرو و بارگیر',
          entityType: 'profile',
          payload: {
            'vehicle_type_id': _selectedVehicleTypeId,
            'plate_number': _plateValue,
            'smart_card_filled': _smartCardCtrl.text.trim().isNotEmpty,
            'insurance_filled': _insuranceNoCtrl.text.trim().isNotEmpty,
          },
        );
        if (res['driver'] is Map) {
          final profile = res['driver'] as Map;
          await AppStorage.setUserJson(jsonEncode(profile));
          _hydrateFromProfile(Map<String, dynamic>.from(profile));
        } else {
          try {
            final fresh = await ApiClient.getJson(AppConstants.meEndpoint);
            if (fresh['ok'] == true) {
              await AppStorage.setUserJson(jsonEncode(fresh));
              _hydrateFromProfile(fresh);
            }
          } catch (_) {}
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('اطلاعات با موفقیت بروزرسانی شد'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('خطا در ذخیره اطلاعات (کد ملی یا پلاک تکراری است)'),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('مشخصات خودرو و بارگیر'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'پلاک خودرو (الزامی)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),

                  // فراخوانی ویجت پلاک گرافیکی
                  IranianPlateField(
                    initialValue: _plateValue,
                    onChanged: (v) => _plateValue = v,
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'نوع بارگیر / وسیله نقلیه (الزامی)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: _selectedVehicleTypeId,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: _vehicleTypes.map((v) {
                      final title = v['title']?.toString() ?? 'نامشخص';
                      return DropdownMenuItem<int>(
                        value: _asInt(v['id']),
                        child: Row(
                          children: [
                            Icon(
                              _getVehicleIcon(title),
                              color: Colors.grey.shade600,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(title),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (v) =>
                        setState(() => _selectedVehicleTypeId = v),
                  ),
                  const SizedBox(height: 20),

                  _buildInput('سال ساخت', _modelYearCtrl, isNumber: true),
                  _buildInput('رنگ خودرو', _colorCtrl),
                  _buildInput(
                    'ظرفیت بار (کیلوگرم)',
                    _capacityCtrl,
                    isNumber: true,
                  ),
                  _buildInput('شماره کارت هوشمند ناوگان', _smartCardCtrl),
                  _buildInput('شماره VIN', _vinCtrl),
                  _buildInput('شماره موتور', _engineCtrl),
                  _buildInput('شماره شاسی', _chassisCtrl),
                  _buildInput('شماره بیمه‌نامه', _insuranceNoCtrl),

                  const Text(
                    'تاریخ پایان بیمه‌نامه',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _pickInsuranceExpiry,
                    child: AbsorbPointer(
                      child: TextField(
                        controller: _insuranceExpiryCtrl,
                        decoration: InputDecoration(
                          hintText: 'مثال: 1403/12/29',
                          prefixIcon: const Icon(Icons.calendar_today_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('ذخیره تغییرات'),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildInput(
    String label,
    TextEditingController ctrl, {
    bool isNumber = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            keyboardType: isNumber ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(
              hintText: 'وارد کنید...',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ],
      ),
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
