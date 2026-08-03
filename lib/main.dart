import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'app/app.dart';
import 'app/app_bloc_observer.dart';
import 'core/di/injector.dart';
import 'firebase_options.dart';

/// Cameras discovered at startup, shared with the scan feature.
List<CameraDescription> availableCameraList = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Bloc.observer = const AppBlocObserver();

  // Firebase & cameras can fail on misconfigured devices — never block launch.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {/* app still works offline / read-only */}

  try {
    availableCameraList = await availableCameras();
  } catch (_) {/* no camera — scan screen shows a graceful message */}

  await configureDependencies();

  runApp(const PolyMintApp());
}
