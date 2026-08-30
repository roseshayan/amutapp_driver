import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';

class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _categories = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final response = await ApiClient.getJson(AppConstants.faqsEndpoint);
      final rawItems = response['items'];
      final items = rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() => _categories = items);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'دریافت سوالات متداول انجام نشد.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _iconFor(String? key) {
    switch (key) {
      case 'install':
        return Icons.download_for_offline_outlined;
      case 'auth':
        return Icons.login_rounded;
      case 'search_load':
        return Icons.inventory_2_outlined;
      case 'request':
        return Icons.local_shipping_outlined;
      case 'history':
        return Icons.history_rounded;
      case 'transport':
        return Icons.move_to_inbox_outlined;
      case 'insurance':
        return Icons.verified_user_outlined;
      case 'identity':
        return Icons.manage_accounts_outlined;
      case 'support':
        return Icons.support_agent_outlined;
      default:
        return Icons.help_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(title: const Text('سوالات متداول'), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 100),
                  Icon(Icons.cloud_off_rounded, size: 70, color: Colors.grey.shade300),
                  const SizedBox(height: 18),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, height: 1.7),
                  ),
                  const SizedBox(height: 14),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('تلاش دوباره'),
                    ),
                  ),
                ],
              )
            : _categories.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 100),
                  Icon(Icons.question_answer_outlined, size: 72, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'هنوز سوال متداولی برای این اپلیکیشن ثبت نشده است.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = _categories[index];
                  final questions = item['questions'] is List
                      ? List<dynamic>.from(item['questions'])
                      : <dynamic>[];
                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => FaqCategoryScreen(
                            title: (item['title'] ?? 'سوالات متداول').toString(),
                            questions: questions,
                          ),
                        ),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withOpacity(.10),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                _iconFor(item['icon_key']?.toString()),
                                color: AppTheme.primary,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (item['title'] ?? '').toString(),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  if ((item['description'] ?? '').toString().trim().isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      item['description'].toString(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5, height: 1.6),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.chevron_left_rounded, color: Colors.grey.shade600, size: 30),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class FaqCategoryScreen extends StatelessWidget {
  const FaqCategoryScreen({super.key, required this.title, required this.questions});

  final String title;
  final List<dynamic> questions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(title: Text(title), centerTitle: true),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        itemCount: questions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final raw = questions[index];
          if (raw is! Map) return const SizedBox.shrink();
          final item = Map<String, dynamic>.from(raw);
          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => FaqDetailScreen(item: item)),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        (item['question'] ?? '').toString(),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.6),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Icon(Icons.chevron_left_rounded, color: Colors.grey.shade600),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class FaqDetailScreen extends StatelessWidget {
  const FaqDetailScreen({super.key, required this.item});

  final Map<String, dynamic> item;

  Future<void> _open(String raw) async {
    final url = AppConstants.fixUrl(raw);
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final question = (item['question'] ?? '').toString();
    final answer = (item['answer'] ?? '').toString();
    final imageUrl = AppConstants.fixUrl(item['image_url']?.toString());
    final videoUrl = AppConstants.fixUrl(item['video_url']?.toString());
    final rawLink = item['link'];
    final link = rawLink is Map ? Map<String, dynamic>.from(rawLink) : null;
    final linkUrl = link == null ? '' : (link['url'] ?? '').toString();
    final linkLabel = link == null ? '' : (link['label'] ?? 'مشاهده لینک').toString();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(title: const Text('سوالات متداول'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 34),
        children: [
          Text(
            question,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold, height: 1.65),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: SelectableText(
              answer,
              textAlign: TextAlign.justify,
              style: TextStyle(fontSize: 15, height: 2, color: Colors.grey.shade800),
            ),
          ),
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : Container(
                        height: 190,
                        color: Colors.white,
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(),
                      ),
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
          if (linkUrl.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _open(linkUrl),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(linkLabel),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: AppTheme.primary.withOpacity(.45)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
          if (videoUrl.isNotEmpty) ...[
            const SizedBox(height: 14),
            Material(
              color: AppTheme.primary.withOpacity(.08),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _open(videoUrl),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('مشاهده ویدئوی راهنما', style: TextStyle(fontWeight: FontWeight.bold)),
                            SizedBox(height: 3),
                            Text('ویدئو در پخش‌کننده دستگاه باز می‌شود.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                      ),
                      const Icon(Icons.open_in_new_rounded, color: AppTheme.primary),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
