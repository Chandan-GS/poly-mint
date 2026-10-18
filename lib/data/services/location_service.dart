import 'dart:async';

import 'package:geolocator/geolocator.dart';

class GeoPoint {
  final double lat;
  final double lng;
  const GeoPoint(this.lat, this.lng);
}

/// Wraps geolocation permission + fetch so screens never touch Geolocator
/// directly. Failures are non-fatal — a transaction can still be recorded
/// without a location stamp.
class LocationService {
  Future<GeoPoint?> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      // A cold GPS can take minutes (or never answer indoors); never let it
      // block minting. Fall back to the last known fix.
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
        ).timeout(const Duration(seconds: 6));
      } on TimeoutException {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) return null;
      return GeoPoint(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }
}
