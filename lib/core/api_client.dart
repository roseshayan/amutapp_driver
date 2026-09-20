import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'constants.dart';
import 'storage.dart';

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.retryable = false,
    this.requestId,
  });
  final String message;
  final int? statusCode;
  final String? code;
  final bool retryable;
  final String? requestId;
  String get displayMessage =>
      requestId == null ? message : '$message\nکد پیگیری: $requestId';
  @override
  String toString() => displayMessage;
}

class ApiClient {
  ApiClient._();

  static bool _isRefreshing = false;
  static DioException? _refreshFailure;
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
                if (!ok && _refreshFailure != null) {
                  final failure = _refreshFailure!;
                  handler.next(
                    DioException(
                      requestOptions: e.requestOptions,
                      response: failure.response,
                      type: failure.type,
                    ),
                  );
                  return;
                }
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
                  } on DioException catch (retryError) {
                    handler.next(retryError);
                    return;
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
      _refreshFailure = null;
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
    _refreshFailure = null;
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
        if (!succeeded) {
          _refreshFailure = DioException(
            requestOptions: r.requestOptions,
            type: DioExceptionType.unknown,
          );
        }
        return succeeded;
      }
      _refreshFailure = DioException(
        requestOptions: RequestOptions(path: AppConstants.refreshTokenEndpoint),
        type: DioExceptionType.unknown,
      );
      return false;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        await _clearAuthTokens();
      } else {
        _refreshFailure = e;
      }
      return false;
    } catch (_) {
      _refreshFailure = DioException(
        requestOptions: RequestOptions(path: AppConstants.refreshTokenEndpoint),
        type: DioExceptionType.unknown,
      );
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
      final r = await dio.post(
        path,
        data: data,
        options: Options(
          receiveTimeout: path.contains('verify-identity')
              ? const Duration(seconds: 120)
              : const Duration(seconds: 45),
        ),
      );
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
      final r = await dio.post(
        path,
        data: form,
        options: Options(
          sendTimeout: const Duration(seconds: 90),
          receiveTimeout: path.contains('verification-video')
              ? const Duration(seconds: 240)
              : const Duration(seconds: 60),
        ),
      );
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
      final r = await dio.post(
        path,
        data: form,
        options: Options(
          sendTimeout: const Duration(seconds: 90),
          receiveTimeout: path.contains('verification-video')
              ? const Duration(seconds: 240)
              : const Duration(seconds: 60),
        ),
      );
      return _asJsonMap(r.data);
    } on DioException catch (e) {
      throw _asApiException(e);
    }
  }

  static Map<String, dynamic> _asJsonMap(dynamic data) {
    if (data is! Map) {
      throw const ApiException(
        'پاسخ سرور قابل پردازش نبود. دوباره تلاش کنید.',
        code: 'invalid_response',
        retryable: true,
      );
    }
    final map = Map<String, dynamic>.from(data);
    if (map['ok'] == false) throw _responseError(map, null);
    return map;
  }

  static ApiException _responseError(Map data, int? status) {
    final raw = data['message'];
    String message = raw is String && raw.trim().isNotEmpty
        ? raw.trim()
        : 'درخواست انجام نشد. لطفاً دوباره تلاش کنید.';
    final lower = message.toLowerCase();
    if (message.length > 700 ||
        [
          'sqlstate',
          'pdoexception',
          'stack trace',
          'fatal error',
          'warning:',
          '<html',
          '<br',
          'uncaught',
          '.php on line',
          'authorization:',
          'bearer ',
          'curl error',
        ].any(lower.contains)) {
      message =
          'خطایی در پردازش درخواست رخ داد. لطفاً با پشتیبانی تماس بگیرید.';
    }
    final id = data['request_id'];
    final requestId =
        id is String && RegExp(r'^[a-zA-Z0-9-]{8,64}$').hasMatch(id)
        ? id
        : null;
    return ApiException(
      message,
      statusCode: status,
      code: data['code'] is String ? data['code'] as String : null,
      retryable: data['retryable'] == true,
      requestId: requestId,
    );
  }

  static ApiException _asApiException(DioException error) {
    final data = error.response?.data;
    if (data is Map) return _responseError(data, error.response?.statusCode);
    final (message, code, retryable) = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => (
        'پاسخ سرور به‌موقع نرسید. پیش از ارسال دوباره، وضعیت را بررسی کنید.',
        'network_timeout',
        true,
      ),
      DioExceptionType.connectionError => (
        'ارتباط با سرور برقرار نشد. اتصال اینترنت را بررسی کنید.',
        'network_unavailable',
        true,
      ),
      DioExceptionType.badCertificate => (
        'ارتباط امن با سرور برقرار نشد.',
        'tls_error',
        false,
      ),
      DioExceptionType.cancel => (
        'درخواست لغو شد.',
        'request_cancelled',
        false,
      ),
      _ => (
        'خطایی در ارتباط با سرور رخ داد. دوباره تلاش کنید.',
        'server_error',
        true,
      ),
    };
    return ApiException(
      message,
      statusCode: error.response?.statusCode,
      code: code,
      retryable: retryable,
    );
  }

  static Future<void> _clearAuthTokens() async {
    await AppStorage.clearToken();
    await AppStorage.clearRefreshToken();
  }
}
