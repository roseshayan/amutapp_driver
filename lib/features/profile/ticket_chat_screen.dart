import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:persian_datetime_picker/persian_datetime_picker.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/storage.dart';

class TicketChatScreen extends StatefulWidget {
  final int ticketId;

  const TicketChatScreen({super.key, required this.ticketId});

  @override
  State<TicketChatScreen> createState() => _TicketChatScreenState();
}

class _TicketChatScreenState extends State<TicketChatScreen> {
  Map<String, dynamic>? _ticket;
  List<dynamic> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  final _msgCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  int? _myUserId;
  Timer? _pollTimer;

  // وضعیت فایل انتخاب‌شده
  String? _attachedFilePath;
  String? _attachedFileName;

  @override
  void initState() {
    super.initState();
    _initSetup();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _msgCtrl.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // 👈 تابع جدید برای تبدیل دامین لوکال به آی‌پی قابل فهم برای امولاتور
  String _fixLocalUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.contains('amutbar-admin.test')) {
      return url.replaceAll(
        'http://amutbar-admin.test',
        'http://10.0.2.2/amutbar-admin',
      );
    }
    return url;
  }

  Future<void> _initSetup() async {
    final userJson = await AppStorage.getUserJson();
    if (userJson != null) {
      try {
        final data = jsonDecode(userJson);
        _myUserId = data['user']['id'];
      } catch (_) {}
    }
    await _fetchData();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetchData(isPolling: true);
    });
  }

  String _formatDateTime(String? rawDate) {
    if (rawDate == null || rawDate.isEmpty) return '';
    try {
      final dt = DateTime.parse(rawDate).toLocal();
      final j = Jalali.fromDateTime(dt);
      final time =
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      return '${j.formatter.yyyy}/${j.formatter.mm}/${j.formatter.dd}  $time';
    } catch (_) {
      return '';
    }
  }

  Future<void> _playInAppNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('audio/pop.mp3'));
    } catch (e) {
      debugPrint('Error playing sound: $e');
    }
  }

  Future<void> _fetchData({bool isPolling = false}) async {
    if (!isPolling && _messages.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final res = await ApiClient.getJson(
        '${AppConstants.ticketsEndpoint}/${widget.ticketId}/messages',
      );
      if (res['ok'] == true && mounted) {
        final oldLength = _messages.length;
        setState(() {
          _ticket = res['ticket'];
          _messages = res['messages'] ?? [];
          _isLoading = false;
        });
        if (oldLength != 0 && oldLength < _messages.length) {
          _scrollToBottom();
          final lastMsg = _messages.last;
          if (lastMsg['sender_user_id'].toString() != _myUserId.toString()) {
            _playInAppNotificationSound();
          }
        } else if (!isPolling) {
          _scrollToBottom();
        }
      }
    } catch (_) {
      if (mounted && !isPolling) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // انتخاب فایل از گالری یا فایل‌منیجر
  Future<void> _pickAttachment() async {
    try {
      // 👈 تغییر این خط از FilePicker.pickFiles به ساختار جدید
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'pdf'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.path != null && file.path!.isNotEmpty) {
          setState(() {
            _attachedFilePath = file.path;
            _attachedFileName = file.name;
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطا در انتخاب فایل: $e')));
      }
    }
  }

  void _removeAttachment() {
    setState(() {
      _attachedFilePath = null;
      _attachedFileName = null;
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if ((text.isEmpty && _attachedFilePath == null) || _isSending) return;

    setState(() => _isSending = true);

    try {
      if (_attachedFilePath != null) {
        // ارسال به صورت multipart با فایل
        await ApiClient.postMultipart(
          '${AppConstants.ticketsEndpoint}/${widget.ticketId}/messages',
          fields: {'message': text},
          filePath: _attachedFilePath!,
          fileFieldName: 'attachment',
        );
        _removeAttachment();
      } else {
        // ارسال فقط متن
        await ApiClient.postJson(
          '${AppConstants.ticketsEndpoint}/${widget.ticketId}/messages',
          {'message': text},
        );
      }
      _msgCtrl.clear();
      await _fetchData();
      _scrollToBottom();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('خطا در ارسال پیام')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isClosed = (_ticket?['status']?.toString() == '3');

    return Scaffold(
      backgroundColor: const Color(0xFFE5E5E5),
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              _ticket?['subject'] ?? 'گفتگو',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            if (_ticket != null)
              Text(
                isClosed ? 'پایان یافته' : 'پشتیبانی آموت‌بار',
                style: TextStyle(
                  fontSize: 12,
                  color: isClosed ? Colors.red.shade300 : Colors.white70,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 20,
                    ),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) =>
                        _buildMessageBubble(_messages[index]),
                  ),
                ),
                if (isClosed)
                  Container(
                    width: double.infinity,
                    color: Colors.grey.shade300,
                    padding: const EdgeInsets.all(16),
                    child: const Text(
                      'این تیکت بسته شده است.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  _buildComposer(),
              ],
            ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          if (_attachedFileName != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.attach_file, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _attachedFileName!,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: _removeAttachment,
                    child: const Icon(Icons.close, size: 18, color: Colors.red),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _msgCtrl,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: 'پیام خود را بنویسید...',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.attach_file, color: Colors.grey),
                onPressed: _pickAttachment,
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _sendMessage,
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: AppTheme.primary,
                  child: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(dynamic m) {
    final isMe = m['sender_user_id'].toString() == _myUserId.toString();
    final timeStr = _formatDateTime(m['created_at']);
    final msgType = m['message_type'] is int
        ? m['message_type']
        : int.parse(m['message_type'].toString());
    final msgText = m['message'] ?? '';

    // 👈 اعمال تابع فیکس کننده آدرس روی لینک دریافتی از سرور
    final attachmentUrl = _fixLocalUrl(m['attachment_url'] as String?);

    final attachmentName = m['attachment_name'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.support_agent_rounded,
                size: 18,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.only(
                left: 14,
                right: 14,
                top: 10,
                bottom: 8,
              ),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFFE1F5FE) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    isMe ? 'شما' : 'پشتیبانی',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isMe ? AppTheme.primary : Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (msgType == 1) ...[
                    Text(
                      msgText,
                      style: const TextStyle(
                        color: Colors.black87,
                        height: 1.5,
                        fontSize: 14,
                      ),
                    ),
                  ] else if (msgType == 2) ...[
                    if (msgText.isNotEmpty)
                      Text(
                        msgText,
                        style: const TextStyle(
                          color: Colors.black87,
                          height: 1.5,
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(height: 6),
                    if (attachmentUrl
                        .isNotEmpty) // 👈 استفاده از متغیر فیکس شده
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          attachmentUrl,
                          fit: BoxFit.cover,
                          width: 200,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image, size: 60),
                        ),
                      ),
                  ] else if (msgType == 3) ...[
                    if (msgText.isNotEmpty)
                      Text(
                        msgText,
                        style: const TextStyle(
                          color: Colors.black87,
                          height: 1.5,
                          fontSize: 14,
                        ),
                      ),
                    const SizedBox(height: 6),
                    if (attachmentUrl.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          // باز کردن فایل PDF با اپلیکیشن‌های خارجی (اختیاری)
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.picture_as_pdf,
                              color: Colors.red,
                              size: 28,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              attachmentName ?? 'فایل PDF',
                              style: const TextStyle(
                                fontSize: 13,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    timeStr,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 32),
        ],
      ),
    );
  }
}
