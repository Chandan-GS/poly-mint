import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Reports online/offline status and emits changes so the repository can flush
/// its offline queue the moment connectivity returns.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  Future<bool> get isOnline async {
    final results = await _connectivity.checkConnectivity();
    return _isOnline(results);
  }

  /// Emits `true` when the device (re)gains a network connection.
  Stream<bool> get onStatusChange =>
      _connectivity.onConnectivityChanged.map(_isOnline);

  bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}
