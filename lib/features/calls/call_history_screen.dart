import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_client.dart';
import '../../core/theme.dart';

final ValueNotifier<int> callHistoryRefreshNotifier = ValueNotifier<int>(0);

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  List<dynamic> _calls = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    callHistoryRefreshNotifier.addListener(_handleExternalRefresh);
    _fetchHistory();
  }

  @override
  void dispose() {
    callHistoryRefreshNotifier.removeListener(_handleExternalRefresh);
    super.dispose();
  }

  void _handleExternalRefresh() {
    if (mounted) {
      _fetchHistory();
    }
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.getJson('/api/v1/driver/calls/history');
      if (res['ok'] == true && mounted) {
        setState(() {
          _calls = res['items'] ?? [];
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تاریخچه تماس‌ها')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _calls.isEmpty
          ? const Center(
              child: Text(
                'تاکنون تماسی ثبت نشده است.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchHistory,
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
                itemCount: _calls.length,
                itemBuilder: (context, index) {
                  final call = _calls[index];
                  return _CallCard(
                    call: call,
                    onTap: call['is_available'] == true
                        ? () => context.push(
                            '/load-details',
                            extra: call['load_id'],
                          )
                        : null,
                  );
                },
              ),
            ),
    );
  }
}

class _CallCard extends StatelessWidget {
  final Map<String, dynamic> call;
  final VoidCallback? onTap;

  const _CallCard({required this.call, this.onTap});

  @override
  Widget build(BuildContext context) {
    final price = call['proposed_price'];
    final callTime = call['call_time'];

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      call['public_code'] ?? 'کد نامشخص',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  Text(
                    _formatTime(callTime),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _row('شرکت', call['company_name'] ?? 'نامشخص'),
              _row('مبدا', call['origin'] ?? '---'),
              _row('مقصد', call['destination'] ?? '---'),
              _row('نوع کالا', call['cargo_title'] ?? '---'),
              if (price != null) _row('کرایه', _formatPrice(price)),
              const SizedBox(height: 8),
              if (onTap != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: const Text('مشاهده جزئیات'),
                  ),
                ),
              if (call['is_available'] == false && onTap == null)
                const Text(
                  'بار دیگر در دسترس نیست',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              '$label:',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}

String _formatPrice(dynamic price) {
  if (price == null) return 'نامشخص';
  final number = price is int ? price : int.tryParse(price.toString());
  if (number == null) return 'نامشخص';
  final parts = [];
  String numStr = number.toString();
  while (numStr.length > 3) {
    parts.insert(0, numStr.substring(numStr.length - 3));
    numStr = numStr.substring(0, numStr.length - 3);
  }
  parts.insert(0, numStr);
  return '${parts.join('٬')} تومان';
}
