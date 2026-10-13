import 'dart:async'; // برای تایمر
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../../core/activity_tracker.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import 'widgets/load_card.dart';

class LoadsListScreen extends StatefulWidget {
  const LoadsListScreen({super.key});

  @override
  State<LoadsListScreen> createState() => _LoadsListScreenState();
}

class _LoadsListScreenState extends State<LoadsListScreen> {
  List<dynamic> _loads = [];
  bool _isLoading = true;
  String _infoMessage = '';

  int? _originCityId;
  String _originCityName = 'در حال تعیین موقعیت...';
  int? _destCityId;
  String _destCityName = 'همه مقصدها';

  Timer? _refreshTimer; // 👈 تعریف تایمر برای آپدیت خودکار

  @override
  void initState() {
    super.initState();
    ActivityTracker.track(
      eventKey: 'nearby_loads_view',
      screenKey: 'nearby_loads',
      screenTitle: 'بارهای اطراف من',
    );
    _determineLocalPositionAndFetch();
    _startAutoRefresh(); // 👈 اجرای تایمر در شروع صفحه
  }

  @override
  void dispose() {
    _refreshTimer
        ?.cancel(); // 👈 حتماً باید تایمر را در هنگام خروج از صفحه پاک کنیم تا رم مصرف نشود
    super.dispose();
  }

  // متد راه‌اندازی آپدیت خودکار
  void _startAutoRefresh() {
    // هر ۱۰ ثانیه یکبار اطلاعات را در پس‌زمینه آپدیت می‌کند (بدون لودینگ مزاحم)
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _fetchLoads(isBackgroundRefresh: true);
      }
    });
  }

  static final Map<String, String> _enCityToFa = {
    'tehran': 'تهران',
    'isfahan': 'اصفهان',
    'esfahan': 'اصفهان',
    'mashhad': 'مشهد',
    'karaj': 'کرج',
    'shiraz': 'شیراز',
    'tabriz': 'تبریز',
    'qom': 'قم',
    'ahvaz': 'اهواز',
    'ahwaz': 'اهواز',
    'kermanshah': 'کرمانشاه',
    'urmia': 'ارومیه',
    'orumiyeh': 'ارومیه',
    'rasht': 'رشت',
    'zahedan': 'زاهدان',
    'hamadan': 'همدان',
    'kerman': 'کرمان',
    'yazd': 'یزد',
    'ardabil': 'اردبیل',
    'bandar abbas': 'بندرعباس',
    'arak': 'اراک',
    'zanjan': 'زنجان',
    'sanandaj': 'سنندج',
    'qazvin': 'قزوین',
    'khorramabad': 'خرم آباد',
    'sari': 'ساری',
    'gorgan': 'گرگان',
    'bojnurd': 'بجنورد',
    'birjand': 'بیرجند',
    'ilam': 'ایلام',
    'shahr-e kord': 'شهرکرد',
    'shahrekord': 'شهرکرد',
    'semnan': 'سمنان',
    'bushehr': 'بوشهر',
    'yasuj': 'یاسوج',
    'chabahar': 'چابهار',
    'kashan': 'کاشان',
    'abadan': 'آبادان',
    'dezful': 'دزفول',
    'neyshabur': 'نیشابور',
    'babol': 'بابل',
    'amol': 'آمل',
    'qaem shahr': 'قائم شهر',
    'saveh': 'ساوه',
    'varamin': 'ورامین',
    'shahriar': 'شهریار',
    'qods': 'قدس',
    'malard': 'ملارد',
    'pakdasht': 'پاکدشت',
    'eslamshahr': 'اسلامشهر',
    'rey': 'ری',
    'damavand': 'دماوند',
    'firoozkooh': 'فیروزکوه',
  };

  String _cleanCityName(String raw) {
    var name = raw.trim();
    name = name.replaceAll(RegExp(r'^(شهرستان|شهر|استان)\s+'), '');
    name = name.replaceAll(RegExp(r'\s+(City|Province|County|Shahrestan)$', caseSensitive: false), '');
    name = name.trim();
    final lower = name.toLowerCase();
    if (_enCityToFa.containsKey(lower)) {
      return _enCityToFa[lower]!;
    }
    return name;
  }

  Future<String?> _resolveCityName(Position position) async {
    try {
      await setLocaleIdentifier('fa_IR');
    } catch (_) {}

    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isNotEmpty) {
        for (final p in placemarks) {
          final cand = p.locality ?? p.subAdministrativeArea ?? p.administrativeArea;
          if (cand != null && cand.trim().isNotEmpty) {
            final cleaned = _cleanCityName(cand);
            if (cleaned.isNotEmpty) return cleaned;
          }
        }
      }
    } catch (e) {
      debugPrint('Placemark lookup error: $e');
    }

    return null;
  }

  Future<void> _determineLocalPositionAndFetch() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _fallbackToAllLoads(message: 'موقعیت مکانی دستگاه غیرفعال است. همه بارها نمایش داده شدند.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          _fallbackToAllLoads(message: 'مجوز موقعیت مکانی داده نشد. همه بارها نمایش داده شدند.');
          return;
        }
      }

      // ۱) اول موقعیت کش‌شده قبلی را تست می‌کنیم (بدون مکث)
      Position? position = await Geolocator.getLastKnownPosition();

      // ۲) اگر کش نبود، موقعیت لحظه‌ای را با دقت متوسط دریافت می‌کنیم
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final cityName = await _resolveCityName(position);
      if (cityName != null && cityName.isNotEmpty && mounted) {
        final searchRes = await ApiClient.getJson(
          '${AppConstants.citiesSearchEndpoint}?q=${Uri.encodeComponent(cityName)}',
        );

        if (searchRes['ok'] == true &&
            searchRes['items'] is List &&
            (searchRes['items'] as List).isNotEmpty) {
          final firstCity = searchRes['items'][0];
          final detectedCityId = int.tryParse(firstCity['id'].toString());
          final detectedCityName = firstCity['text'].toString();

          if (mounted && detectedCityId != null) {
            setState(() {
              _originCityId = detectedCityId;
              _originCityName = detectedCityName;
              _infoMessage = 'در حال دریافت بارهای مبدا $detectedCityName...';
            });

            await _fetchLoads();

            // بررسی: اگر باری برای این مبدا نبود، خودکار همه بارها را می‌آوریم
            if (mounted && _loads.isEmpty) {
              setState(() {
                _originCityId = null;
                _originCityName = 'همه مبداها';
                _infoMessage = 'باری از مبدا $detectedCityName یافت نشد. همه بارها نمایش داده شدند.';
              });
              await _fetchLoads();
            } else if (mounted && _loads.isNotEmpty) {
              setState(() {
                _infoMessage = 'بارهای مبدا $detectedCityName (بر اساس موقعیت شما)';
              });
            }
            return;
          }
        }
      }

      _fallbackToAllLoads(message: 'تشخیص شهر انجام نشد. همه بارها نمایش داده شدند.');
    } catch (e) {
      debugPrint('Location detection error: $e');
      _fallbackToAllLoads();
    }
  }

  void _fallbackToAllLoads({String? message}) {
    if (!mounted) return;
    setState(() {
      _originCityName = 'همه مبداها';
      _originCityId = null;
      if (message != null) {
        _infoMessage = message;
      }
    });
    _fetchLoads();
  }

  // 👈 متد دستکاری شده برای پشتیبانی از رفرش پس‌زمینه
  Future<void> _fetchLoads({bool isBackgroundRefresh = false}) async {
    if (!mounted) return;

    // اگر رفرش از سمت تایمر باشد، لودینگ وسط صفحه را نشان نمی‌دهیم
    if (!isBackgroundRefresh) {
      setState(() {
        _isLoading = true;
        _infoMessage = '';
      });
    }

    try {
      final Map<String, dynamic> queryParams = {};

      if (_originCityId != null && _originCityId! > 0) {
        queryParams['origin_city_id'] = _originCityId;
      }
      if (_destCityId != null && _destCityId! > 0) {
        queryParams['dest_city_id'] = _destCityId;
      }

      String url = AppConstants.driverLoadsEndpoint;
      if (queryParams.isNotEmpty) {
        final qs = Uri(
          queryParameters: queryParams.map((k, v) => MapEntry(k, v.toString())),
        ).query;
        url += '?$qs';
      }

      final res = await ApiClient.getJson(url);

      if (res['ok'] == true && mounted) {
        setState(() {
          _loads = res['items'] ?? [];

          if (res['info_message'] != null) {
            _infoMessage = res['info_message'];
          }
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("Error fetching loads: $e");
      if (mounted) {
        if (!isBackgroundRefresh) {
          setState(() {
            _isLoading = false;
            _infoMessage = 'خطا در دریافت اطلاعات. نمایش همه‌ی بارهای فعال...';
          });
        }
        _fetchLoadsWithoutFilters(isBackgroundRefresh: isBackgroundRefresh);
      }
    }
  }

  Future<void> _fetchLoadsWithoutFilters({
    bool isBackgroundRefresh = false,
  }) async {
    try {
      final res = await ApiClient.getJson(AppConstants.driverLoadsEndpoint);
      if (res['ok'] == true && mounted) {
        setState(() {
          _loads = res['items'] ?? [];
          _originCityName = 'همه مبداها (لوکیشن یافت نشد)';
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted && !isBackgroundRefresh) setState(() => _isLoading = false);
    }
  }

  void _clearFilter(bool isOrigin) {
    setState(() {
      if (isOrigin) {
        _originCityId = null;
        _originCityName = 'همه مبداها';
      } else {
        _destCityId = null;
        _destCityName = 'همه مقصدها';
      }
    });
    _fetchLoads();
  }

  void _showCitySearchSelector(bool isOrigin) {
    final searchCtrl = TextEditingController();
    List<dynamic> searchResults = [];
    bool isSearching = false;

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
              children: [
                Text(
                  isOrigin ? 'انتخاب شهر مبدا' : 'انتخاب شهر مقصد',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: searchCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'نام شهر یا استان را وارد کنید',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (val) async {
                    if (val.trim().length < 2) return;
                    setModalState(() => isSearching = true);
                    try {
                      final res = await ApiClient.getJson(
                        '${AppConstants.citiesSearchEndpoint}?q=${val.trim()}',
                      );
                      setModalState(() {
                        searchResults = res['items'] ?? [];
                        isSearching = false;
                      });
                    } catch (_) {
                      setModalState(() => isSearching = false);
                    }
                  },
                ),
                const SizedBox(height: 12),
                if (isSearching) const LinearProgressIndicator(),
                SizedBox(
                  height: 250,
                  child: ListView.builder(
                    itemCount: searchResults.length,
                    itemBuilder: (c, idx) {
                      final item = searchResults[idx];
                      return ListTile(
                        title: Text(item['text'].toString()),
                        leading: const Icon(Icons.location_city_rounded),
                        onTap: () {
                          setState(() {
                            if (isOrigin) {
                              _originCityId = int.tryParse(
                                item['id'].toString(),
                              );
                              _originCityName = item['text'].toString();
                            } else {
                              _destCityId = int.tryParse(item['id'].toString());
                              _destCityName = item['text'].toString();
                            }
                          });
                          Navigator.pop(ctx);
                          _fetchLoads();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showSupportDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.support_agent_rounded, color: AppTheme.primary),
            SizedBox(width: 8),
            Text('راهنمای اعلام بارها'),
          ],
        ),
        content: const Text(
          'لیست بارهای نمایش داده شده به صورت خودکار و زنده آپدیت می‌شود.',
          style: TextStyle(height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'متوجه شدم',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/support');
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text('ثبت پیام'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لیست بارهای موجود'),
        actions: [
          // 👈 یک دکمه رفرش دستی هم اضافه شد تا کاربر حس کنترل داشته باشد
          IconButton(
            icon: const Icon(Icons.refresh, size: 26),
            onPressed: () => _fetchLoads(),
          ),
          IconButton(
            icon: const Icon(Icons.support_agent, size: 26),
            onPressed: _showSupportDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            color: Colors.white,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _showCitySearchSelector(true),
                    child: _FilterBadge(
                      title: 'مبدا',
                      value: _originCityName,
                      showClear: _originCityId != null,
                      onClear: () => _clearFilter(true),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded, color: Colors.grey),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => _showCitySearchSelector(false),
                    child: _FilterBadge(
                      title: 'مقصد',
                      value: _destCityName,
                      showClear: _destCityId != null,
                      onClear: () => _clearFilter(false),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_infoMessage.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.amber.shade50,
              child: Text(
                _infoMessage,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.amber.shade900,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _loads.isEmpty
                ? const Center(child: Text('هیچ باری در این مسیر یافت نشد.'))
                : RefreshIndicator(
                    onRefresh: () async => _fetchLoads(),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(14),
                      itemCount: _loads.length,
                      itemBuilder: (context, index) {
                        final load = _loads[index];
                        return LoadCard(load: load);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterBadge extends StatelessWidget {
  final String title;
  final String value;
  final bool showClear;
  final VoidCallback? onClear;

  const _FilterBadge({
    required this.title,
    required this.value,
    this.showClear = false,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (showClear)
            GestureDetector(
              onTap: onClear,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }
}
