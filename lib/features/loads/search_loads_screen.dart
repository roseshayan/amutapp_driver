import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/constants.dart';
import 'widgets/load_card.dart';
import 'widgets/filter_badge.dart'; // ویجت مشترک فیلتر

class SearchLoadsScreen extends StatefulWidget {
  const SearchLoadsScreen({super.key});

  @override
  State<SearchLoadsScreen> createState() => _SearchLoadsScreenState();
}

class _SearchLoadsScreenState extends State<SearchLoadsScreen> {
  List<dynamic> _loads = [];
  bool _isLoading = false;
  String _infoMessage = '';

  int? _originCityId;
  String _originCityName = 'انتخاب مبدا';
  int? _destCityId;
  String _destCityName = 'انتخاب مقصد';

  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    // فقط در صورت انتخاب هر دو فیلتر، تایمر رفرش خودکار را فعال می‌کنیم (در صورت نیاز)
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted && _originCityId != null && _destCityId != null) {
        _fetchLoads(isBackgroundRefresh: true);
      }
    });
  }

  Future<void> _fetchLoads({bool isBackgroundRefresh = false}) async {
    if (_originCityId == null || _destCityId == null) {
      // هنوز هر دو انتخاب نشده‌اند
      setState(() => _loads = []);
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
          '${AppConstants.driverLoadsEndpoint}?origin_city_id=$_originCityId&dest_city_id=$_destCityId';
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
      debugPrint("Error fetching loads: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
                    hintText: 'نام استان یا شهر را وارد کنید',
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
                          // فقط وقتی هر دو انتخاب شدند، بارها را بگیر
                          if (_originCityId != null && _destCityId != null) {
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
    final bool filtersReady = _originCityId != null && _destCityId != null;

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
                    onTap: () => _showCitySearchSelector(true),
                    child: FilterBadge(
                      title: 'مبدا',
                      value: _originCityName,
                      showClear: _originCityId != null,
                      onClear: () {
                        setState(() {
                          _originCityId = null;
                          _originCityName = 'انتخاب مبدا';
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
                    onTap: () => _showCitySearchSelector(false),
                    child: FilterBadge(
                      title: 'مقصد',
                      value: _destCityName,
                      showClear: _destCityId != null,
                      onClear: () {
                        setState(() {
                          _destCityId = null;
                          _destCityName = 'انتخاب مقصد';
                        });
                        _fetchLoads();
                      },
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
                : !filtersReady
                ? const Center(
                    child: Text(
                      'برای جستجو، مبدا و مقصد را انتخاب کنید.',
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
