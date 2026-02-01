import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/router.dart';

class SwiperApp extends ConsumerWidget {
  const SwiperApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Swiper',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('en'),
      supportedLocales: const [
        Locale('en'),
        Locale('sv'),
      ],
      routerConfig: ref.watch(routerProvider),
    );
  }
}
