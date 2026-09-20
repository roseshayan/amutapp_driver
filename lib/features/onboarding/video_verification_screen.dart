import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../core/api_client.dart';
import '../../core/app_info.dart';
import '../../core/constants.dart';

class VideoVerificationScreen extends StatefulWidget {
  const VideoVerificationScreen({super.key});
  @override
  State<VideoVerificationScreen> createState() =>
      _VideoVerificationScreenState();
}

class _VideoVerificationScreenState extends State<VideoVerificationScreen> {
  CameraController? _camera;
  Timer? _timer;
  bool _loading = true, _busy = false, _recording = false;
  String? _error;
  String _phrase = '', _guideText = '', _guideUrl = '';
  int _maxSeconds = 10, _remaining = 10;
  final _serial = TextEditingController();
  String _challengeToken = '';
  DateTime? _challengeExpires;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _camera?.dispose();
    _serial.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = await ApiClient.getJson(AppConstants.appInfoEndpoint);
      if (config['ok'] == false) {
        throw ApiException(
          (config['message'] ?? 'دریافت تنظیمات انجام نشد.').toString(),
        );
      }
      AppInfoCache.setRaw(config);
      final me = await ApiClient.getJson(AppConstants.meEndpoint);
      if (me['ok'] == false) {
        throw ApiException(
          (me['message'] ?? 'دریافت وضعیت انجام نشد.').toString(),
        );
      }
      if (!mounted) return;
      final onboarding = me['onboarding'] as Map? ?? {};
      if (onboarding['needs_verification_video'] == false) {
        context.go('/dashboard');
        return;
      }
      final verification = config['verification'] as Map? ?? {};
      _guideText = (verification['video_guide_text'] ?? '').toString();
      _guideUrl = AppConstants.fixUrl(
        verification['video_guide_url']?.toString(),
      );
      _maxSeconds = (int.tryParse('${verification['video_max_seconds']}') ?? 10)
          .clamp(1, 30);
      _remaining = _maxSeconds;
      _phrase = '';
    } catch (e) {
      _error = e is ApiException
          ? e.message
          : 'دریافت راهنمای احراز هویت انجام نشد.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _fetchChallenge() async {
    if (_busy || _recording) return;
    setState(() {
      _busy = true;
      _challengeToken = '';
    });
    try {
      final result = await ApiClient.postJson('/api/v1/auth/video-challenge', {
        if (_serial.text.trim().isNotEmpty) 'card_serial': _serial.text.trim(),
      });
      if (!mounted) return;
      if (result['skipped'] == true) {
        context.go('/dashboard');
        return;
      }
      final token = result['challenge_token'];
      final phrase = result['speech_text'];
      if (token is! String || phrase is! String || phrase.length < 10) {
        throw const ApiException('متن ضبط معتبر دریافت نشد؛ دوباره تلاش کنید.');
      }
      setState(() {
        _challengeToken = token;
        _phrase = phrase;
        _challengeExpires = DateTime.now().add(
          Duration(seconds: int.tryParse('${result['expires_in']}') ?? 600),
        );
      });
    } catch (e) {
      _message(
        e is ApiException ? e.displayMessage : 'دریافت متن ضبط انجام نشد.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepareCamera() async {
    if (_busy) return;
    setState(() => _busy = true);
    CameraController? controller;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera');
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: true,
      );
      // The camera plugin requests camera and microphone access on initialization.
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _camera = controller;
    } catch (_) {
      await controller?.dispose();
      _message(
        'دوربین آماده نشد. دسترسی دوربین و میکروفون را در تنظیمات گوشی فعال کنید.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_busy || _recording || _camera == null) return;
    if (_challengeToken.isEmpty ||
        _challengeExpires == null ||
        DateTime.now().isAfter(_challengeExpires!)) {
      setState(() => _challengeToken = '');
      _message('متن جدید دریافت کنید و پیش از ضبط آن را بخوانید.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _camera!.startVideoRecording();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _remaining = _maxSeconds;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _remaining--);
        if (_remaining <= 0) {
          _timer?.cancel();
          _stopAndUpload();
        }
      });
    } catch (_) {
      _message('ضبط شروع نشد. دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopAndUpload() async {
    if (_busy || !_recording) return;
    _timer?.cancel();
    setState(() => _busy = true);
    XFile? file;
    try {
      file = await _camera!.stopVideoRecording();
      if (!mounted) return;
      setState(() => _recording = false);
      final response = await ApiClient.postMultipart(
        AppConstants.verificationVideoEndpoint,
        fields: <String, dynamic>{'challenge_token': _challengeToken},
        fileFieldName: 'verification_video',
        filePath: file.path,
      );
      if (!mounted) return;
      // Upload success alone does not mean biometric verification succeeded.
      if (response['verified'] == true || response['skipped'] == true) {
        final me = await ApiClient.getJson(AppConstants.meEndpoint);
        if (!mounted) return;
        if (me['onboarding']?['needs_verification_video'] == false) {
          _message(
            response['skipped'] == true
                ? 'این مرحله الزامی نیست.'
                : 'احراز هویت ویدئویی تأیید شد.',
          );
          context.go('/dashboard');
          return;
        }
      }
      _message(
        (response['message'] ??
                'ویدئو تأیید نشد. چهره را واضح نشان دهید و جمله را کامل بخوانید؛ سپس دوباره تلاش کنید.')
            .toString(),
      );
    } catch (e) {
      _message(
        e is ApiException
            ? e.displayMessage
            : 'ارسال ویدئو انجام نشد. دوباره تلاش کنید.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _recording = _camera?.value.isRecordingVideo ?? false;
          _remaining = _maxSeconds;
          _challengeToken = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_recording,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('احراز هویت ویدئویی'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(onPressed: _load, child: const Text('تلاش مجدد')),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'پیش از ضبط',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  _guideText.isEmpty
                      ? 'در محیط روشن و آرام قرار بگیرید، چهره را کامل در کادر نگه دارید و جملهٔ زیر را با صدای واضح بخوانید.'
                      : _guideText,
                  style: const TextStyle(height: 1.8),
                ),
                if (_guideUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: OutlinedButton.icon(
                      onPressed: _busy || _recording
                          ? null
                          : () => showDialog<void>(
                              context: context,
                              builder: (_) =>
                                  VerificationGuideDialog(url: _guideUrl),
                            ),
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('مشاهده ویدئوی آموزشی نحوه احراز هویت'),
                    ),
                  ),
                TextField(
                  controller: _serial,
                  enabled: !_busy && !_recording,
                  decoration: const InputDecoration(
                    labelText: 'سریال پشت کارت ملی یا کد رهگیری رسید',
                    helperText:
                        'اگر قبلاً ثبت کرده‌اید، می‌توانید خالی بگذارید.',
                  ),
                ),
                OutlinedButton(
                  onPressed: _busy || _recording ? null : _fetchChallenge,
                  child: const Text('دریافت متن جدید ضبط'),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      _phrase,
                      style: const TextStyle(fontSize: 18, height: 1.9),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_camera?.value.isInitialized == true)
                  SizedBox(
                    height: 300,
                    child: ClipRect(child: CameraPreview(_camera!)),
                  ),
                const SizedBox(height: 14),
                Text(
                  _recording
                      ? 'زمان باقی‌مانده: $_remaining ثانیه'
                      : 'حداکثر زمان ضبط: $_maxSeconds ثانیه',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                if (_busy) const Center(child: CircularProgressIndicator()),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : _camera == null
                      ? _prepareCamera
                      : _recording
                      ? _stopAndUpload
                      : _start,
                  icon: Icon(_recording ? Icons.stop : Icons.videocam),
                  label: Text(
                    _camera == null
                        ? 'فعال کردن دوربین'
                        : _recording
                        ? 'پایان ضبط و ارسال'
                        : 'شروع ضبط',
                  ),
                ),
              ],
            ),
    ),
  );
}

class VerificationGuideDialog extends StatefulWidget {
  const VerificationGuideDialog({super.key, required this.url});
  final String url;
  @override
  State<VerificationGuideDialog> createState() =>
      _VerificationGuideDialogState();
}

class _VerificationGuideDialogState extends State<VerificationGuideDialog> {
  VideoPlayerController? _controller;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final uri = Uri.parse(widget.url);
      if (!['http', 'https'].contains(uri.scheme)) {
        throw const FormatException('Invalid video URL');
      }
      _controller = VideoPlayerController.networkUrl(uri);
      await _controller!.initialize().timeout(const Duration(seconds: 20));
      if (!mounted) return;
      setState(() {});
      await _controller!.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Expanded(child: Text('ویدئوی آموزشی')),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (_failed)
            const Text(
              'پخش ویدئو ممکن نشد. می‌توانید لینک را در مرورگر باز کنید.',
            ),
          if (!_failed && _controller?.value.isInitialized != true)
            const Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          if (!_failed && _controller?.value.isInitialized == true) ...[
            AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
            VideoProgressIndicator(_controller!, allowScrubbing: true),
            IconButton(
              onPressed: () {
                setState(() {
                  _controller!.value.isPlaying
                      ? _controller!.pause()
                      : _controller!.play();
                });
              },
              icon: Icon(
                _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            ),
          ],
          TextButton(
            onPressed: () async {
              final uri = Uri.tryParse(widget.url);
              if (uri == null || !['http', 'https'].contains(uri.scheme)) {
                return;
              }
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (_) {
                /* Inline error remains visible. */
              }
            },
            child: const Text('باز کردن لینک در مرورگر'),
          ),
        ],
      ),
    ),
  );
}
