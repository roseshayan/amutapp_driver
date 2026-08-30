import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityGuard {
  static Future<bool> hasInternet() async {
    final res = await Connectivity().checkConnectivity();
    return res != ConnectivityResult.none;
  }

  static Future<bool> isVpnOn() async {
    final res = await Connectivity().checkConnectivity();
    return res == ConnectivityResult.vpn;
  }
}
