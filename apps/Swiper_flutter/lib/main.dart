import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'url_strategy_stub.dart' if (dart.library.html) 'url_strategy_web.dart' as url_strategy;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  url_strategy.usePathUrlStrategy();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Hive.initFlutter();
  runApp(const ProviderScope(child: SwiperApp()));
}
