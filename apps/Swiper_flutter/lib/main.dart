import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'url_strategy_stub.dart' if (dart.library.html) 'url_strategy_web.dart'
    as url_strategy;

Future<void> _configureFirebaseAuthEmulator() async {
  const useAuthEmulator = bool.fromEnvironment(
    'USE_FIREBASE_AUTH_EMULATOR',
    defaultValue: false,
  );
  if (!useAuthEmulator) return;

  const host = String.fromEnvironment(
    'FIREBASE_AUTH_EMULATOR_HOST',
    defaultValue: 'localhost',
  );
  const port = int.fromEnvironment(
    'FIREBASE_AUTH_EMULATOR_PORT',
    defaultValue: 9099,
  );
  await FirebaseAuth.instance.useAuthEmulator(host, port);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  url_strategy.usePathUrlStrategy();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _configureFirebaseAuthEmulator();
  await Hive.initFlutter();
  runApp(const ProviderScope(child: SwiperApp()));
}
