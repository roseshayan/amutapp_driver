import 'package:amutbar_driver/core/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int calls = 0;
  void respond(dynamic data, {int status = 200, DioExceptionType? error}) {
    ApiClient.dio.interceptors.clear();
    calls = 0;
    ApiClient.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, h) {
          calls++;
          final response = Response(
            requestOptions: r,
            statusCode: status,
            data: data,
          );
          if (error != null || status >= 400) {
            h.reject(
              DioException(
                requestOptions: r,
                response: error == null ? response : null,
                type: error ?? DioExceptionType.badResponse,
              ),
            );
          } else {
            h.resolve(response);
          }
        },
      ),
    );
  }

  test(
    'provider failures retain safe code, reference and status without retry',
    () async {
      respond({
        'ok': false,
        'message': 'سرویس در دسترس نیست',
        'code': 'provider_credentials_error',
        'request_id': 'abcdef0123456789',
        'retryable': false,
      }, status: 503);
      await expectLater(
        ApiClient.postJson('/api/v1/auth/verify-identity', {}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 503)
              .having((e) => e.code, 'code', 'provider_credentials_error')
              .having(
                (e) => e.displayMessage,
                'support id',
                contains('abcdef0123456789'),
              ),
        ),
      );
      expect(calls, 1);
    },
  );
  test('HTTP 200 failure envelope still fails', () async {
    respond({'ok': false, 'message': 'رد درخواست'});
    await expectLater(
      ApiClient.getJson('/fixture'),
      throwsA(isA<ApiException>()),
    );
  });
  test('HTML and technical details never reach the user', () async {
    respond('<html>upstream failure</html>');
    await expectLater(
      ApiClient.getJson('/fixture'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'invalid_response'),
      ),
    );
    respond({'message': 'SQLSTATE secret database details'}, status: 500);
    await expectLater(
      ApiClient.getJson('/fixture'),
      throwsA(
        isA<ApiException>().having(
          (e) => e.message,
          'redacted',
          isNot(contains('SQLSTATE')),
        ),
      ),
    );
  });
  test('timeout is actionable and does not repeat a paid request', () async {
    respond(null, error: DioExceptionType.receiveTimeout);
    await expectLater(
      ApiClient.postJson('/fixture', {}),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'network_timeout'),
      ),
    );
    expect(calls, 1);
  });
}
