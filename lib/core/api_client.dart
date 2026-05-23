import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'constants.dart';
import 'storage.dart';

class ApiClient {
  ApiClient._();

  static bool _isRefreshing = false;
  static final List<void Function(String)> _refreshWaiters = [];

  static final Dio dio =
      Dio(
          BaseOptions(
            baseUrl: AppConstants.baseUrl,
            connectTimeout: const Duration(seconds: 25),
            receiveTimeout: const Duration(seconds: 25),
          ),
        )
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) async {
              try {
                if (options.path != AppConstants.refreshTokenEndpoint) {
                  final token = await AppStorage.getToken();
                  if (token != null && token.isNotEmpty) {
                    options.headers['Authorization'] = 'Bearer $token';
                  }
                }
              } catch (_) {}
              handler.next(options);
            },
            onResponse: (response, handler) {
              debugPrint(
                'Dio Response: ${response.statusCode} ${response.requestOptions.uri}',
              );
              if (response.data != null) {
                final dataStr = response.data.toString();
                debugPrint(
                  'Response preview: ${dataStr.length > 300 ? dataStr.substring(0, 300) : dataStr}',
                );
              }
              handler.next(response);
            },
            onError: (DioException e, handler) async {
              debugPrint('Dio Error: ${e.message}');
              if (e.response != null) {
                debugPrint('Status code: ${e.response?.statusCode}');
                debugPrint('Response data: ${e.response?.data}');
              }
              debugPrint('Dio Error URL: ${e.requestOptions.uri}');

              // رفرش توکن در صورت 401 (فقط یکبار برای هر درخواست)
              final status = e.response?.statusCode;
              final alreadyRetried =
                  e.requestOptions.extra['__retried'] == true;
              final isRefreshCall =
                  e.requestOptions.path == AppConstants.refreshTokenEndpoint;

              if (status == 401 && !alreadyRetried && !isRefreshCall) {
                final ok = await _refreshIfNeeded();
                if (ok) {
                  try {
                    final newToken = await AppStorage.getToken();
                    final opts = e.requestOptions;
                    opts.extra['__retried'] = true;
                    if (newToken != null && newToken.isNotEmpty) {
                      opts.headers['Authorization'] = 'Bearer $newToken';
                    }
                    final clone = await dio.fetch(opts);
                    handler.resolve(clone);
                    return;
                  } catch (_) {
                    // اگر retry هم شکست خورد، خطای اصلی برگردد
                  }
                }
              }

              handler.next(e);
            },
          ),
        );

  static Future<bool> _refreshIfNeeded() async {
    final refresh = await AppStorage.getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;

    // اگر رفرش در حال انجام است، منتظر بمان
    if (_isRefreshing) {
      final completer = Completer<bool>();
      _refreshWaiters.add((t) => completer.complete(t.isNotEmpty));
      return completer.future;
    }

    _isRefreshing = true;
    try {
      final r = await dio.post(
        AppConstants.refreshTokenEndpoint,
        data: {'refresh_token': refresh},
        options: Options(headers: {'Authorization': null}),
      );
      final data = r.data;
      if (data is Map && data['ok'] == true && data['auth'] is Map) {
        final auth = data['auth'] as Map;
        final accessToken = (auth['access_token'] ?? '').toString();
        final refreshToken = (auth['refresh_token'] ?? '').toString();
        if (accessToken.isNotEmpty) {
          await AppStorage.setToken(accessToken);
        }
        if (refreshToken.isNotEmpty) {
          await AppStorage.setRefreshToken(refreshToken);
        }
        for (final w in _refreshWaiters) {
          try {
            w(accessToken);
          } catch (_) {}
        }
        _refreshWaiters.clear();
        return accessToken.isNotEmpty;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _isRefreshing = false;
    }
  }

  static Future<Map<String, dynamic>> getJson(String path) async {
    final r = await dio.get(path);
    final data = r.data;
    if (data is Map<String, dynamic>) return data;
    return <String, dynamic>{'raw': data?.toString() ?? '', '_non_json': true};
  }

  static Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> data,
  ) async {
    final r = await dio.post(path, data: data);
    return (r.data is Map<String, dynamic>)
        ? r.data
        : <String, dynamic>{'data': r.data};
  }

  static Future<Map<String, dynamic>> postMultipart(
    String path, {
    required String fileFieldName,
    required String filePath,
    Map<String, dynamic>? fields,
  }) async {
    final form = FormData.fromMap({
      ...(fields ?? <String, dynamic>{}),
      fileFieldName: await MultipartFile.fromFile(filePath),
    });

    final r = await dio.post(path, data: form);
    return (r.data is Map<String, dynamic>)
        ? r.data
        : <String, dynamic>{'data': r.data};
  }

  static Future<Map<String, dynamic>> postMultipartFiles(
    String path, {
    required Map<String, File> files,
    Map<String, dynamic>? fields,
  }) async {
    final map = <String, dynamic>{...(fields ?? <String, dynamic>{})};
    for (final e in files.entries) {
      map[e.key] = await MultipartFile.fromFile(e.value.path);
    }
    final form = FormData.fromMap(map);
    final r = await dio.post(path, data: form);
    return (r.data is Map<String, dynamic>)
        ? r.data
        : <String, dynamic>{'data': r.data};
  }
}
