import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/router.dart';
import 'data/event_tracker_lifecycle.dart';
import 'data/locale_provider.dart';

class SwiperApp extends ConsumerWidget {
  const SwiperApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return EventTrackerLifecycleObserver(
      child: MaterialApp.router(
        title: 'Swiper',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        locale: locale,
        supportedLocales: const [
          Locale('en'),
          Locale('sv'),
        ],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        localeResolutionCallback: (locale, supportedLocales) {
          for (final supported in supportedLocales) {
            if (locale != null && supported.languageCode == locale.languageCode) {
              return supported;
            }
          }
          return supportedLocales.first;
        },
        routerConfig: ref.watch(routerProvider),
      ),
    );
  }
}
