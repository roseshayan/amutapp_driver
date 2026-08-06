import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/activity_tracker.dart';
import '../../core/api_client.dart';
import '../../core/app_info.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  List<dynamic> _tickets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    ActivityTracker.track(
      eventKey: 'support_view',
      screenKey: 'support',
      screenTitle: 'پشتیبانی و پیام‌ها',
    );
    _fetchTickets();
  }

  Future<void> _fetchTickets() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.getJson(AppConstants.ticketsEndpoint);
      if (res['ok'] == true && mounted) {
        setState(() {
          _tickets = res['items'] ?? [];
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  String _formatDate(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(rawDate).toLocal();
      final j = Jalali.fromDateTime(dt);
      return '${j.formatter.yyyy}/${j.formatter.mm}/${j.formatter.dd}';
    } catch (_) {
      return '';
    }
  }

  void _openUrl(String url) async {
    if (url.isEmpty) return;
    ActivityTracker.track(
      eventKey: 'support_contact_tap',
      screenKey: 'support',
      screenTitle: 'پشتیبانی و پیام‌ها',
      entityType: 'support',
      payload: {'url_scheme': Uri.tryParse(url)?.scheme ?? ''},
    );
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _showCreateTicketDialog() {
    final subjectCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom:
                  MediaQuery.of(ctx).viewInsets.bottom +
                  MediaQuery.of(ctx).padding.bottom +
                  16,
              left: 20,
              right: 20,
              top: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ثبت پیام جدید',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: subjectCtrl,
                  decoration: const InputDecoration(
                    hintText: 'موضوع پیام (مثال: مشکل در احراز هویت)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: msgCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'متن پیام خود را بنویسید...',
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            if (subjectCtrl.text.isEmpty ||
                                msgCtrl.text.isEmpty)
                              return;
                            setModalState(() => isSaving = true);
                            try {
                              final ticketRes = await ApiClient.postJson(
                                AppConstants.ticketsEndpoint,
                                {
                                  'subject': subjectCtrl.text,
                                  'message': msgCtrl.text,
                                },
                              );
                              ActivityTracker.track(
                                eventKey: 'ticket_create',
                                screenKey: 'support',
                                screenTitle: 'پشتیبانی و پیام‌ها',
                                entityType: 'ticket',
                                entityId: int.tryParse(
                                  (ticketRes['ticket_id'] ?? '').toString(),
                                ),
                                ticketId: int.tryParse(
                                  (ticketRes['ticket_id'] ?? '').toString(),
                                ),
                                payload: {'subject': subjectCtrl.text.trim()},
                              );
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                _fetchTickets();
                                final createdId = int.tryParse(
                                  (ticketRes['ticket_id'] ?? '').toString(),
                                );
                                if (createdId != null && mounted) {
                                  this.context
                                      .push('/ticket-chat', extra: createdId)
                                      .then((_) => _fetchTickets());
                                }
                              }
                            } catch (_) {
                              setModalState(() => isSaving = false);
                            }
                          },
                    child: isSaving
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('ارسال پیام'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = AppInfoCache.supportPhone;
    final wa = AppInfoCache.supportWhatsapp;
    final tg = AppInfoCache.supportTelegram;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('پشتیبانی و پیام‌ها'),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // اطلاعات تماس
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ارتباط سریع با پشتیبانی',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (phone.isNotEmpty)
                      Expanded(
                        child: _ContactBox(
                          icon: Icons.call,
                          color: Colors.blue,
                          title: 'تماس',
                          onTap: () => _openUrl('tel:$phone'),
                        ),
                      ),
                    if (phone.isNotEmpty) const SizedBox(width: 12),
                    if (wa.isNotEmpty)
                      Expanded(
                        child: _ContactBox(
                          icon: Icons.chat_bubble_outline,
                          color: Colors.green,
                          title: 'واتساپ',
                          onTap: () => _openUrl('https://wa.me/$wa'),
                        ),
                      ),
                    if (wa.isNotEmpty) const SizedBox(width: 12),
                    if (tg.isNotEmpty)
                      Expanded(
                        child: _ContactBox(
                          icon: Icons.send_rounded,
                          color: Colors.lightBlue,
                          title: 'تلگرام',
                          onTap: () => _openUrl('https://t.me/$tg'),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // هدر پیام‌ها
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'پیام‌های من',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                TextButton.icon(
                  onPressed: _showCreateTicketDialog,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('ثبت پیام'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                  ),
                ),
              ],
            ),
          ),
          // لیست پیام‌ها
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _tickets.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.support_agent_rounded,
                          size: 80,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'پیامی ثبت نکرده‌اید',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: _tickets.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final t = _tickets[index];
                      final int status =
                          int.tryParse(t['status'].toString()) ?? 1;
                      final isClosed = status == 3;
                      final isAnswered = status == 2;

                      return InkWell(
                        onTap: () {
                          final ticketId =
                              int.tryParse(t['id'].toString()) ?? 0;
                          ActivityTracker.track(
                            eventKey: 'ticket_view',
                            screenKey: 'support',
                            screenTitle: 'پشتیبانی و پیام‌ها',
                            entityType: 'ticket',
                            entityId: ticketId,
                            ticketId: ticketId,
                            payload: {'subject': t['subject']},
                          );
                          context
                              .push('/ticket-chat', extra: ticketId)
                              .then((_) => _fetchTickets());
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isClosed
                                      ? Colors.grey.shade100
                                      : (isAnswered
                                            ? Colors.green.shade50
                                            : Colors.orange.shade50),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isClosed
                                      ? Icons.lock_outline
                                      : Icons.chat_outlined,
                                  color: isClosed
                                      ? Colors.grey
                                      : (isAnswered
                                            ? Colors.green
                                            : Colors.orange),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            t['subject'] ?? 'بدون موضوع',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Text(
                                          _formatDate(t['updated_at']),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      isClosed
                                          ? 'بسته شده'
                                          : (isAnswered
                                                ? 'پاسخ داده شده'
                                                : 'در انتظار پاسخ'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Colors.grey,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ContactBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;

  const _ContactBox({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
