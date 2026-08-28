import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get_it/get_it.dart';

import '../../data/services/auth_service.dart';
import '../../data/services/ble_weight_sensor.dart';
import '../../data/services/connectivity_service.dart';
import '../../data/services/crypto_service.dart';
import '../../data/services/location_service.dart';
import '../../data/services/ml_service.dart';
import '../../data/services/preferences_service.dart';
import '../../data/services/simulated_weight_sensor.dart';
import '../../data/services/transaction_repository.dart';
import '../../data/services/weight_sensor.dart';

final GetIt sl = GetIt.instance;

/// Wires up singletons once at startup. Blocs/Cubits are created per-screen and
/// pull their dependencies from here.
Future<void> configureDependencies() async {
  // Services with async init.
  final prefs = await PreferencesService.create();
  sl.registerSingleton<PreferencesService>(prefs);

  sl.registerLazySingleton<FirebaseFirestore>(() => FirebaseFirestore.instance);
  sl.registerLazySingleton<ConnectivityService>(() => ConnectivityService());
  sl.registerLazySingleton<LocationService>(() => LocationService());
  sl.registerLazySingleton<MlService>(() => MlService());
  sl.registerLazySingleton<CryptoService>(() => CryptoService());
  sl.registerLazySingleton<AuthService>(() => AuthService());

  // Weight sensor: pick BLE vs simulator from settings. Registered as a factory
  // so toggling the mode and re-resolving yields the right implementation.
  sl.registerFactory<WeightSensor>(
    () => prefs.useSimulatedSensor
        ? SimulatedWeightSensor()
        : BleWeightSensor(),
  );

  sl.registerLazySingleton<TransactionRepository>(
    () => TransactionRepository(
      firestore: sl(),
      prefs: sl(),
      connectivity: sl(),
    ),
  );
}
