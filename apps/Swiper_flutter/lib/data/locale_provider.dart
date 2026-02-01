import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../l10n/app_strings.dart';

const String kLocaleKey = 'swiper_locale';

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) => LocaleNotifier());

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('en')) {
    _load();
  }

  Future<void> _load() async {
    try {
      final box = await Hive.openBox('swiper_prefs');
      final code = box.get(kLocaleKey) as String?;
      if (code != null && (code == 'sv' || code == 'en')) {
        state = Locale(code);
      }
    } catch (_) {}
  }

  Future<void> setLocale(Locale locale) async {
    if (state == locale) return;
    final code = locale.languageCode == 'sv' ? 'sv' : 'en';
    try {
      final box = await Hive.openBox('swiper_prefs');
      await box.put(kLocaleKey, code);
      state = Locale(code);
    } catch (_) {}
  }
}

final appStringsProvider = Provider<AppStrings>((ref) {
  final locale = ref.watch(localeProvider);
  return AppStrings(locale);
});
