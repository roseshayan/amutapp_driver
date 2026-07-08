import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import 'widgets/load_card.dart';
import 'widgets/filter_badge.dart';

class SearchLoadsScreen extends StatefulWidget {
  const SearchLoadsScreen({super.key});

  @override
  State<SearchLoadsScreen> createState() => _SearchLoadsScreenState();
}

class _SearchLoadsScreenState extends State<SearchLoadsScreen> {
  List<dynamic> _loads = [];
  bool _isLoading = false;
  String _infoMessage = '';

  int? _originProvinceId;
  String _originProvinceName = 'انتخاب استان مبدا';
  int? _destProvinceId;
  String _destProvinceName = 'انتخاب استان مقصد';

  List<Map<String, dynamic>> _provinces = [];
  bool _isLoadingProvinces = false;

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  bool get _filtersReady => _originProvinceId != null && _destProvinceId != null;

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && _filtersReady) {
        _fetchLoads(isBackgroundRefresh: true);
      }
    });
  }

  Future<void> _loadProvinces() async {
    if (_provinces.isNotEmpty || _isLoadingProvinces) return;

    setState(() => _isLoadingProvinces = true);
    try {
      final res = await ApiClient.getJson(AppConstants.provincesEndpoint);
      final items = (res['items'] is List) ? res['items'] as List : <dynamic>[];
      final provinces = items
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => int.tryParse(e['id'].toString()) != null)
          .toList();

      if (mounted) {
        setState(() {
          _provinces = provinces;
          _isLoadingProvinces = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading provinces: $e');
      if (mounted) {
        setState(() => _isLoadingProvinces = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('خطا در دریافت لیست استان‌ها'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _fetchLoads({bool isBackgroundRefresh = false}) async {
    if (!_filtersReady) {
      setState(() {
        _loads = [];
        _infoMessage = '';
      });
      return;
    }

    if (!mounted) return;

    if (!isBackgroundRefresh) {
      setState(() {
        _isLoading = true;
        _infoMessage = '';
      });
    }

    try {
      final url =
          '${AppConstants.driverLoadsEndpoint}?origin_province_id=$_originProvinceId&dest_province_id=$_destProvinceId';
      final res = await ApiClient.getJson(url);

      if (res['ok'] == true && mounted) {
        setState(() {
          _loads = res['items'] ?? [];
          _infoMessage = res['info_message'] ?? '';
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error fetching loads: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showProvinceSelector(bool isOrigin) async {
    await _loadProvinces();
    if (!mounted) return;

    final searchCtrl = TextEditingController();
    List<Map<String, dynamic>> filtered = List<Map<String, dynamic>>.from(_provinces);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          void applyFilter(String value) {
            final q = value.trim();
            setModalState(() {
              filtered = q.isEmpty
                  ? List<Map<String, dynamic>>.from(_provinces)
                  : _provinces
                        .where((p) => p['name'].toString().contains(q))
                        .toList();
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isOrigin ? 'انتخاب استان مبدا' : 'انتخاب استان مقصد',
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
                    hintText: 'نام استان را وارد کنید',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: applyFilter,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 320,
                  child: filtered.isEmpty
                      ? const Center(child: Text('استانی یافت نشد.'))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (c, idx) {
                            final item = filtered[idx];
                            final id = int.tryParse(item['id'].toString());
                            final name = item['name'].toString();

                            return ListTile(
                              title: Text(name),
                              leading: const Icon(Icons.map_rounded),
                              onTap: id == null
                                  ? null
                                  : () {
                                      setState(() {
                                        if (isOrigin) {
                                          _originProvinceId = id;
                                          _originProvinceName = name;
                                        } else {
                                          _destProvinceId = id;
                                          _destProvinceName = name;
                                        }
                                      });
                                      Navigator.pop(ctx);
                                      if (_filtersReady) {
                                        _fetchLoads();
                                      }
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

  @override
  Widget build(BuildContext context) {
    final bool filtersReady = _filtersReady;

    return Scaffold(
      appBar: AppBar(
        title: const Text('جستجوی بار'),
        actions: [
          if (filtersReady)
            IconButton(
              icon: const Icon(Icons.refresh, size: 26),
              onPressed: () => _fetchLoads(),
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
                    onTap: _isLoadingProvinces
                        ? null
                        : () => _showProvinceSelector(true),
                    child: FilterBadge(
                      title: 'مبدا',
                      value: _originProvinceName,
                      showClear: _originProvinceId != null,
                      onClear: () {
                        setState(() {
                          _originProvinceId = null;
                          _originProvinceName = 'انتخاب استان مبدا';
                        });
                        _fetchLoads();
                      },
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded, color: Colors.grey),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _isLoadingProvinces
                        ? null
                        : () => _showProvinceSelector(false),
                    child: FilterBadge(
                      title: 'مقصد',
                      value: _destProvinceName,
                      showClear: _destProvinceId != null,
                      onClear: () {
                        setState(() {
                          _destProvinceId = null;
                          _destProvinceName = 'انتخاب استان مقصد';
                        });
                        _fetchLoads();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isLoadingProvinces) const LinearProgressIndicator(),
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
                : !filtersReady
                ? const Center(
                    child: Text(
                      'برای جستجو، استان مبدا و استان مقصد را انتخاب کنید.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
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
