import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppStorage {
  static const _s = FlutterSecureStorage();

  static const _tokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userKey = 'user_json';

  static Future<void> setToken(String token) =>
      _s.write(key: _tokenKey, value: token);

  static Future<String?> getToken() => _s.read(key: _tokenKey);

  static Future<void> clearToken() => _s.delete(key: _tokenKey);

  static Future<void> setRefreshToken(String token) =>
      _s.write(key: _refreshTokenKey, value: token);

  static Future<String?> getRefreshToken() => _s.read(key: _refreshTokenKey);

  static Future<void> clearRefreshToken() => _s.delete(key: _refreshTokenKey);

  static Future<void> setUserJson(String json) =>
      _s.write(key: _userKey, value: json);

  static Future<String?> getUserJson() => _s.read(key: _userKey);

  static Future<void> clearAll() async {
    await _s.delete(key: _tokenKey);
    await _s.delete(key: _refreshTokenKey);
    await _s.delete(key: _userKey);
  }
}
