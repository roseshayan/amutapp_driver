import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/api_client.dart';
import '../../core/app_info.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import 'package:video_player/video_player.dart';

class VideoVerificationScreen extends StatefulWidget {
  const VideoVerificationScreen({super.key});

  @override
  State<VideoVerificationScreen> createState() =>
      _VideoVerificationScreenState();
}

class _VideoVerificationScreenState extends State<VideoVerificationScreen> {
  CameraController? _cam;
  bool _loading = true;
  bool _recording = false;
  int _remaining = 10;
  Timer? _timer;

  String _phrase = '';
  String _guideText = '';
  String _guideUrl = '';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cam?.dispose();
    super.dispose();
  }

  // محاسبه هوشمند تعداد کل مراحل
  int get _totalSteps {
    return AppInfoCache.requireNationalSerial
        ? 3
        : 3; // با توجه به ساختار پروژه شما مرحله نهایی ۳ از ۳ است
  }

  Future<void> _boot() async {
    setState(() => _loading = true);

    try {
      final raw = _AppInfoCachePriv._rawJsonToMap();
      final v = (raw['verification'] is Map)
          ? raw['verification'] as Map
          : <dynamic, dynamic>{};
      final tpl = (v['video_phrase_template'] ?? '').toString().trim();
      final maxSec =
          int.tryParse((v['video_max_seconds'] ?? '10').toString()) ?? 10;
      _remaining = maxSec;
      _guideText = (v['video_guide_text'] ?? '').toString();
      _guideUrl = (v['video_guide_url'] ?? '').toString();

      final me = await ApiClient.getJson(AppConstants.meEndpoint);
      final user = (me['user'] is Map)
          ? me['user'] as Map
          : <dynamic, dynamic>{};
      final fullName = (user['full_name'] ?? '').toString().trim();
      final companyName = AppInfoCache.appName;

      _phrase = tpl.isNotEmpty
          ? tpl
                .replaceAll('{full_name}', fullName)
                .replaceAll('{company_name}', companyName)
          : 'اینجانب $fullName با قوانین $companyName موافقت می‌کنم.';

      // بررسی مجوزهای دسترسی
      final camOk = await Permission.camera.request().isGranted;
      final micOk = await Permission.microphone.request().isGranted;
      if (!camOk || !micOk) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'برای ضبط ویدئو، دسترسی دوربین و میکروفون لازم است.',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _loading = false);
        return;
      }

      final cams = await availableCameras();
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );

      final ctrl = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      await ctrl.initialize();
      if (!mounted) return;
      setState(() {
        _cam = ctrl;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در آماده‌سازی دوربین: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startRecording() async {
    if (_cam == null || _recording) return;

    try {
      await _cam!.prepareForVideoRecording();
      await _cam!.startVideoRecording();

      setState(() {
        _recording = true;
      });

      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) async {
        if (!mounted) return;
        if (_remaining <= 1) {
          t.cancel();
          await _stopRecording();
          return;
        }
        setState(() => _remaining -= 1);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در شروع ضبط: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    if (_cam == null || !_recording) return;

    _timer?.cancel();
    XFile file;
    try {
      file = await _cam!.stopVideoRecording();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطا در پایان ضبط: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _recording = false;
    });

    await _uploadVideo(File(file.path));
  }

  Future<void> _uploadVideo(File f) async {
    try {
      final res = await ApiClient.postMultipart(
        AppConstants.driverVerificationVideoEndpoint,
        fields: <String, dynamic>{},
        fileFieldName: 'verification_video',
        filePath: f.path,
      );

      if (!mounted) return;

      if (res['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ویدئو احراز هویت با موفقیت ارسال و تایید شد.'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/dashboard');
        return;
      }

      final msg = (res['message'] ?? 'خطا در ارسال ویدئو').toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      final raw = _AppInfoCachePriv._rawJsonToMap();
      final v = (raw['verification'] is Map)
          ? raw['verification'] as Map
          : <dynamic, dynamic>{};
      final maxSec =
          int.tryParse((v['video_max_seconds'] ?? '10').toString()) ?? 10;
      if (mounted) setState(() => _remaining = maxSec);
    }
  }

  Future<void> _openGuideUrl() async {
    if (_guideUrl.trim().isEmpty) return;

    // باز کردن دیالوگ (پاپ‌آپ) پخش ویدئو
    showDialog(
      context: context,
      builder: (context) =>
          _InlineVideoPlayerDialog(videoUrl: _guideUrl.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('احراز هویت ویدئویی'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StepHeader(
                      title: 'مرحله $_totalSteps از $_totalSteps',
                      subtitle: 'ضبط ویدئوی کوتاه جهت تطبیق چهره و زنده سنجی',
                    ),
                    const SizedBox(height: 20),

                    // بخش دوربین همراه با فیکس کردن مشکل قرینه و قرارگیری ساختار لایه‌ها
                    _NiceCard(
                      padding: EdgeInsets.zero,
                      child: Container(
                        height: 240,
                        width: double.infinity,
                        color: Colors.black,
                        child: _cam != null && _cam!.value.isInitialized
                            ? Stack(
                                fit: StackFit.expand,
                                children: [
                                  // معکوس کردن افقی پیش‌نمایش جهت رفع حالت ناهمگون دوربین سلفی
                                  Transform.flip(
                                    flipX: true,
                                    child: CameraPreview(_cam!),
                                  ),

                                  // نمایش وضعیت ضبط و شمارشگر معکوس روی تصویر دوربین
                                  if (_recording)
                                    Positioned(
                                      top: 12,
                                      right: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.7),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const _BlinkingRedDot(),
                                            const SizedBox(width: 8),
                                            Text(
                                              'در حال ضبط: $_remaining ثانیه',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              )
                            : const Center(
                                child: Text(
                                  'دوربین آماده نیست',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _NiceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'لطفاً جمله زیر را به صورت واضح قرائت کنید:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.secondary,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Text(
                              _phrase,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.8,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // باکس راهنما همراه با دکمه پخش ویدئوی آموزشی پنل ادمین
                    _NiceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.info_outline_rounded,
                                color: AppTheme.primary,
                                size: 20,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'توصیه‌های امنیتی و راهنما',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _guideText.trim().isEmpty
                                ? 'صورت شما باید کاملاً داخل کادر قرار داشته باشد. در مدت زمان مشخص شده جمله بالا را شمرده بگویید. از عدم پوشش چهره و کیفیت نور محیط مطمئن شوید.'
                                : _guideText,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.7,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          if (_guideUrl.trim().isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Divider(),
                            ),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton.icon(
                                onPressed: _openGuideUrl,
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.primary,
                                  alignment: Alignment.centerRight,
                                  padding: EdgeInsets.zero,
                                ),
                                icon: const Icon(Icons.ondemand_video_rounded),
                                label: const Text(
                                  'مشاهده ویدئوی آموزشی نحوه احراز هویت',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // دکمه کنترل فرآیند ضبط
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _recording
                            ? _stopRecording
                            : _startRecording,
                        icon: Icon(
                          _recording
                              ? Icons.stop_circle_rounded
                              : Icons.videocam_rounded,
                        ),
                        label: Text(
                          _recording
                              ? 'پایان و ارسال ویدئو'
                              : 'شروع ضبط ویدئو ($_remaining ثانیه)',
                          style: const TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _recording
                              ? Colors.red
                              : AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ویجت اختصاصی دایره چشمک‌زن ضبط (رویکرد انیمیشن بومی فلاتر)
class _BlinkingRedDot extends StatefulWidget {
  const _BlinkingRedDot();

  @override
  State<_BlinkingRedDot> createState() => _BlinkingRedDotState();
}

class _BlinkingRedDotState extends State<_BlinkingRedDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.red,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// هماهنگ‌سازی ساختار لایه‌های کارت‌ها و هدر گام‌ها
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
            Icons.video_camera_front_outlined,
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
  final EdgeInsetsGeometry? padding;

  const _NiceCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
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

// ============================================================================
// ویجت‌های اختصاصی برای پخش ویدئو داخل اپلیکیشن
// ============================================================================

class _InlineVideoPlayerDialog extends StatefulWidget {
  final String videoUrl;

  const _InlineVideoPlayerDialog({required this.videoUrl});

  @override
  State<_InlineVideoPlayerDialog> createState() =>
      _InlineVideoPlayerDialogState();
}

class _InlineVideoPlayerDialogState extends State<_InlineVideoPlayerDialog> {
  late VideoPlayerController _controller;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize()
          .then((_) {
            setState(() {}); // وقتی ویدئو لود شد، صفحه رو رفرش کن
            _controller.play(); // پخش خودکار
          })
          .catchError((e) {
            setState(() => _isError = true);
          });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // بخش هدر دیالوگ
          Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ویدئوی آموزشی',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close_rounded, color: Colors.black54),
                ),
              ],
            ),
          ),

          // بخش پخش ویدئو
          Container(
            color: Colors.black,
            child: AspectRatio(
              aspectRatio: _controller.value.isInitialized
                  ? _controller.value.aspectRatio
                  : 16 / 9,
              child: _isError
                  ? const Center(
                      child: Text(
                        'خطا در بارگذاری ویدئو\nلطفاً اینترنت خود را بررسی کنید.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : _controller.value.isInitialized
                  ? Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        VideoPlayer(_controller),
                        _ControlsOverlay(controller: _controller),
                        VideoProgressIndicator(
                          _controller,
                          allowScrubbing: true,
                          colors: VideoProgressColors(
                            playedColor: AppTheme.primary,
                            bufferedColor: Colors.white24,
                            backgroundColor: Colors.white12,
                          ),
                        ),
                      ],
                    )
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlsOverlay extends StatelessWidget {
  const _ControlsOverlay({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        controller.value.isPlaying ? controller.pause() : controller.play();
      },
      child: Container(
        color: Colors.transparent, // برای دریافت کلیک روی کل ویدئو
        child: Center(
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, child) {
              if (!value.isPlaying && !value.isBuffering) {
                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(12),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 40.0,
                  ),
                );
              } else if (value.isBuffering) {
                return const CircularProgressIndicator(color: Colors.white);
              }
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}

extension _AppInfoCachePriv on AppInfoCache {
  static Map<String, dynamic> _rawJsonToMap() {
    try {
      final raw = AppInfoCache.rawJson;
      if (raw.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
