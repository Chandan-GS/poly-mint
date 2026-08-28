import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Thin, typed wrapper over [SharedPreferences]. Owns everything that must
/// survive an app restart: settings, the anonymous user id, the onboarding
/// flag and the offline transaction queue.
class PreferencesService {
  PreferencesService(this._prefs);

  final SharedPreferences _prefs;

  static const _kOnboarded = 'onboarding_complete';
  static const _kThemeMode = 'theme_mode';
  static const _kUserId = 'user_id';
  static const _kDisplayName = 'display_name';
  static const _kPhotoUrl = 'photo_url';
  static const _kAuthSkipped = 'auth_skipped';
  static const _kHighAccuracy = 'high_accuracy_mode';
  static const _kSensorMode = 'sensor_mode';
  static const _kQueue = 'offline_queue';

  static Future<PreferencesService> create() async =>
      PreferencesService(await SharedPreferences.getInstance());

  // --- Onboarding -----------------------------------------------------------
  bool get hasOnboarded => _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboarded() => _prefs.setBool(_kOnboarded, true);

  // --- Theme ('system' | 'light' | 'dark') ----------------------------------
  String get themeMode => _prefs.getString(_kThemeMode) ?? 'system';
  Future<void> setThemeMode(String mode) => _prefs.setString(_kThemeMode, mode);

  // --- Model accuracy toggle (multi-frame averaging) ------------------------
  bool get highAccuracyMode => _prefs.getBool(_kHighAccuracy) ?? true;
  Future<void> setHighAccuracyMode(bool v) =>
      _prefs.setBool(_kHighAccuracy, v);

  // --- Weight-sensor mode ('simulated' | 'ble') -----------------------------
  /// Defaults to 'simulated' so the app is fully usable with no hardware.
  /// Switch to 'ble' once a physical PolyMint node is available.
  String get sensorMode => _prefs.getString(_kSensorMode) ?? 'simulated';
  Future<void> setSensorMode(String mode) =>
      _prefs.setString(_kSensorMode, mode);
  bool get useSimulatedSensor => sensorMode != 'ble';

  // --- Identity -------------------------------------------------------------
  /// Stable anonymous id generated once per install. Ties transactions to a
  /// user without requiring sign-in.
  String get userId {
    var id = _prefs.getString(_kUserId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      _prefs.setString(_kUserId, id);
    }
    return id;
  }

  String get displayName =>
      _prefs.getString(_kDisplayName) ?? 'Eco Contributor';
  Future<void> setDisplayName(String name) =>
      _prefs.setString(_kDisplayName, name.trim());

  String? get photoUrl => _prefs.getString(_kPhotoUrl);

  /// True once the user chose "continue without an account".
  bool get authSkipped => _prefs.getBool(_kAuthSkipped) ?? false;
  Future<void> setAuthSkipped(bool v) => _prefs.setBool(_kAuthSkipped, v);

  /// Bind a signed-in account so the rest of the app (which reads
  /// userId/displayName) is keyed by the real identity.
  Future<void> bindIdentity(
      {required String uid, String? name, String? photo}) async {
    await _prefs.setString(_kUserId, uid);
    if (name != null && name.trim().isNotEmpty) {
      await setDisplayName(name);
    }
    if (photo != null) {
      await _prefs.setString(_kPhotoUrl, photo);
    } else {
      await _prefs.remove(_kPhotoUrl);
    }
    await setAuthSkipped(false);
  }

  /// Drop the bound identity (on sign-out); a fresh anonymous id is minted on
  /// the next [userId] read.
  Future<void> clearIdentity() async {
    await _prefs.remove(_kUserId);
    await _prefs.remove(_kPhotoUrl);
    await _prefs.remove(_kAuthSkipped);
  }

  // --- Offline queue (list of flat JSON maps) -------------------------------
  List<Map<String, dynamic>> get queuedTransactions {
    final raw = _prefs.getStringList(_kQueue) ?? const [];
    return raw
        .map((s) => jsonDecode(s) as Map<String, dynamic>)
        .toList(growable: false);
  }

  Future<void> saveQueue(List<Map<String, dynamic>> items) {
    return _prefs.setStringList(
      _kQueue,
      items.map((m) => jsonEncode(m)).toList(),
    );
  }

  Future<void> enqueue(Map<String, dynamic> tx) async {
    final items = queuedTransactions.toList()..add(tx);
    await saveQueue(items);
  }
}
