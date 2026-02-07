/// App-wide constants.
class AppConstants {
  static const String appName = 'Swiper';
  static const String tagline = 'Swipe your way to the perfect sofa';
  static const bool enableStandaloneOnboarding = bool.fromEnvironment(
    'ENABLE_STANDALONE_ONBOARDING',
    defaultValue: false,
  );

  /// API base URL: from env or default for local emulator.
  static String get apiBaseUrl {
    // In production this would come from Firebase Remote Config or env.
    const env = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:5001',
    );
    return env;
  }

  static const int deckPageSize = 20;
  static const int maxCompareItems = 4;
  static const int minCompareItems = 2;
}
