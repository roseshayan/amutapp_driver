import 'package:amutbar_driver/core/constants.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConstants.fixUrl', () {
    test('keeps an external absolute URL', () {
      const url = 'https://cdn.example.com/banner.png';
      expect(AppConstants.fixUrl(url), url);
    });

    test('resolves a relative storage URL against the API base', () {
      expect(
        AppConstants.fixUrl('/storage/uploads/avatar.jpg'),
        '${AppConstants.baseUrl}/storage/uploads/avatar.jpg',
      );
    });

    test('replaces legacy emulator and test hosts', () {
      expect(
        AppConstants.fixUrl(
          'http://10.0.2.2/amutbar-admin/storage/uploads/avatar.jpg',
        ),
        '${AppConstants.baseUrl}/storage/uploads/avatar.jpg',
      );
      expect(
        AppConstants.fixUrl(
          'http://amutbar-admin.test/storage/uploads/avatar.jpg',
        ),
        '${AppConstants.baseUrl}/storage/uploads/avatar.jpg',
      );
    });
  });
}
