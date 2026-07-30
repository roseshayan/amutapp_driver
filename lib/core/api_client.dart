import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'constants.dart';
import 'storage.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();

  static bool _isRefreshing = false;
  static final List<Completer<bool>> _refreshWaiters = [];

  static final Dio _refreshDio = Dio(
    BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 25),
      receiveTimeout: const Duration(seconds: 25),
    ),
  );

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
              if (kDebugMode) {
                debugPrint(
                  'API ${response.statusCode}: '
                  '${response.requestOptions.method} '
                  '${response.requestOptions.uri.path}',
                );
              }
              handler.next(response);
            },
            onError: (DioException e, handler) async {
              if (kDebugMode) {
                debugPrint(
                  'API error ${e.response?.statusCode ?? '-'}: '
                  '${e.requestOptions.method} ${e.requestOptions.uri.path}',
                );
              }

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
                    final original = e.requestOptions;
                    final retryData = original.data is FormData
                        ? (original.data as FormData).clone()
                        : original.data;
                    final opts = original.copyWith(
                      data: retryData,
                      extra: {...original.extra, '__retried': true},
                      headers: Map<String, dynamic>.from(original.headers),
                    );
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
    if (refresh == null || refresh.isEmpty) {
      await AppStorage.clearToken();
      return false;
    }

    // اگر رفرش در حال انجام است، منتظر بمان
    if (_isRefreshing) {
      final completer = Completer<bool>();
      _refreshWaiters.add(completer);
      return completer.future;
    }

    _isRefreshing = true;
    var succeeded = false;
    try {
      final r = await _refreshDio.post(
        AppConstants.refreshTokenEndpoint,
        data: {'refresh_token': refresh},
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
        succeeded = accessToken.isNotEmpty;
        return succeeded;
      }
      await _clearAuthTokens();
      return false;
    } catch (_) {
      await _clearAuthTokens();
      return false;
    } finally {
      for (final waiter in _refreshWaiters) {
        if (!waiter.isCompleted) waiter.complete(succeeded);
      }
      _refreshWaiters.clear();
      _isRefreshing = false;
    }
  }

  static Future<Map<String, dynamic>> getJson(String path) async {
    try {
      final r = await dio.get(path);
      return _asJsonMap(r.data);
    } on DioException catch (e) {
      throw _asApiException(e);
    }
  }

  static Future<Map<String, dynamic>> postJson(
    String path,
    Map<String, dynamic> data,
  ) async {
    try {
      final r = await dio.post(path, data: data);
      return _asJsonMap(r.data);
    } on DioException catch (e) {
      throw _asApiException(e);
    }
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

    try {
      final r = await dio.post(path, data: form);
      return _asJsonMap(r.data);
    } on DioException catch (e) {
      throw _asApiException(e);
    }
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
    try {
      final r = await dio.post(path, data: form);
      return _asJsonMap(r.data);
    } on DioException catch (e) {
      throw _asApiException(e);
    }
  }

  static Map<String, dynamic> _asJsonMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{'data': data, '_non_json': true};
  }

  static ApiException _asApiException(DioException error) {
    final data = error.response?.data;
    String? message;
    if (data is Map) {
      final raw = data['message'] ?? data['error'];
      if (raw != null && raw.toString().trim().isNotEmpty) {
        message = raw.toString().trim();
      }
    }
    message ??= switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => 'زمان اتصال به سرور به پایان رسید.',
      DioExceptionType.connectionError => 'ارتباط با سرور برقرار نشد.',
      _ => 'خطایی در ارتباط با سرور رخ داد.',
    };
    return ApiException(message, statusCode: error.response?.statusCode);
  }

  static Future<void> _clearAuthTokens() async {
    await AppStorage.clearToken();
    await AppStorage.clearRefreshToken();
  }
}
