import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';

class LoadDetailsScreen extends StatefulWidget {
  final int loadId;

  const LoadDetailsScreen({super.key, required this.loadId});

  @override
  State<LoadDetailsScreen> createState() => _LoadDetailsScreenState();
}

class _LoadDetailsScreenState extends State<LoadDetailsScreen> {
  Map<String, dynamic>? _loadDetails;
  List<dynamic> _otherActiveLoads = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFullDetails();
  }

  // تابع کمکی برای جدا کردن سه‌رقم سه‌رقم اعداد
  String _formatPrice(dynamic price) {
    if (price == null) return 'نامشخص';
    final number = price is int ? price : int.tryParse(price.toString());
    if (number == null) return 'نامشخص';

    // جدا کردن سه‌رقم سه‌رقم
    final parts = [];
    String numStr = number.toString();
    while (numStr.length > 3) {
      parts.insert(0, numStr.substring(numStr.length - 3));
      numStr = numStr.substring(0, numStr.length - 3);
    }
    parts.insert(0, numStr);
    return '${parts.join('٬')} تومان';
  }

  Future<void> _fetchFullDetails() async {
    try {
      final res = await ApiClient.getJson(
        '${AppConstants.driverLoadsEndpoint}/${widget.loadId}',
      );
      if (res['ok'] == true && mounted) {
        setState(() {
          _loadDetails = res['data'];
        });
        // لود سایر بارهای فعال همین باربری
        _fetchCompanyOtherLoads(_loadDetails?['company_id']);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchCompanyOtherLoads(dynamic compId) async {
    if (compId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final res = await ApiClient.getJson(
        '${AppConstants.companyActiveLoadsEndpoint}?company_id=$compId&exclude_id=${widget.loadId}',
      );
      if (res['ok'] == true && mounted) {
        setState(() {
          _otherActiveLoads = res['items'] ?? [];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initiateCallAndLog(String phone) async {
    if (phone.isEmpty) return;
    try {
      await ApiClient.postJson(AppConstants.logCallEndpoint, {
        'load_id': widget.loadId,
        'company_id': _loadDetails?['company_id'] ?? 0,
        'client_platform': Platform.isIOS ? 'ios' : 'android',
        'client_version': 1,
      });
      final Uri callUri = Uri(scheme: 'tel', path: phone);
      if (await canLaunchUrl(callUri)) {
        await launchUrl(callUri);
      }
    } catch (_) {
      final Uri callUri = Uri(scheme: 'tel', path: phone);
      await launchUrl(callUri);
    }
  }

  // 👈 این تابع جدید برای باز کردن نقشه (مسیریابی) طراحی شده است
  Future<void> _openMapRoute() async {
    if (_loadDetails == null) return;

    final oLat = _loadDetails!['o_lat'];
    final oLng = _loadDetails!['o_lng'];
    final dLat = _loadDetails!['d_lat'];
    final dLng = _loadDetails!['d_lng'];

    if (oLat == null || dLat == null) return;

    // هدایت به لینک یونیورسال گوگل مپ که به طور خودکار نقشه گوشی را باز می‌کند
    final url =
        'https://www.google.com/maps/dir/?api=1&origin=$oLat,$oLng&destination=$dLat,$dLng';
    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('اپلیکیشن نقشه یا مرورگر در گوشی شما یافت نشد.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_loadDetails == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('خطا')),
        body: const Center(child: Text('بار یافت نشد یا حذف شده است.')),
      );
    }

    // متغیر کمکی برای چک کردن وجود لوکیشن
    final bool hasMapRoute =
        _loadDetails?['o_lat'] != null && _loadDetails?['d_lat'] != null;

    return Scaffold(
      appBar: AppBar(title: Text('کد بار: ${_loadDetails!['public_code']}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _loadDetails!['cargo_title'] ?? 'کالا عمومی',
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Text(
                        _loadDetails!['load_type_text'] ?? 'نامشخص',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    'شرکت باربری:',
                    _loadDetails!['company_name'],
                  ),
                  _buildDetailRow(
                    'نوع بارگیر:',
                    _loadDetails!['vehicle_title'],
                  ),
                  _buildDetailRow('وزن بار:', _loadDetails!['weight_text']),
                  _buildDetailRow('نوع کالا:', _loadDetails!['cargo_title'] ?? 'کالا عمومی'),
                  _buildDetailRow('مبدا:', _loadDetails!['origin_full'] ?? _loadDetails!['origin_city']),
                  _buildDetailRow('مقصد:', _loadDetails!['dest_full'] ?? _loadDetails!['dest_city']),
                  _buildDetailRow(
                    'نوع کرایه:',
                    _loadDetails!['price_type_text'],
                  ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('کرایه پیشنهادی', style: TextStyle(color: Colors.grey)),
                      Text(
                        _formatPrice(_loadDetails!['proposed_price']),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppTheme.secondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 👈 اضافه شدن دکمه مسیریابی فقط در صورتی که مختصات وجود داشته باشد
            if (hasMapRoute)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                width: double.infinity,
                height: 55,
                child: OutlinedButton.icon(
                  onPressed: _openMapRoute,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('نمایش مسیر روی نقشه'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue.shade700,
                    side: BorderSide(color: Colors.blue.shade200, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

            if (_loadDetails!['description'] != null &&
                _loadDetails!['description'].toString().isNotEmpty) ...[
              const Text(
                'توضیحات تکمیلی:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_loadDetails!['description']),
              ),
              const SizedBox(height: 16),
            ],

            const Text(
              'سایر بارهای این شرکت:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            if (_otherActiveLoads.isEmpty)
              const Text('بار فعال دیگری از این شرکت یافت نشد.')
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _otherActiveLoads.length,
                itemBuilder: (ctx, i) {
                  final l = _otherActiveLoads[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text('${l['origin']} به ${l['destination']}'),
                      subtitle: Text('${l['cargo_title']} - کرایه: ${l['price']}'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () {
                        // هدایت به صفحه جزئیات بار انتخاب‌شده
                        context.push('/load-details', extra: l['id']);
                      },
                    ),
                  );
                },
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            height: 60,
            child: ElevatedButton.icon(
              onPressed: () =>
                  _initiateCallAndLog(_loadDetails!['phone_coordination'] ?? ''),
              icon: const Icon(Icons.phone_forwarded),
              label: const Text('برقراری تماس'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.left,
            ),
          ),
        ],
      ),
    );
  }
}
