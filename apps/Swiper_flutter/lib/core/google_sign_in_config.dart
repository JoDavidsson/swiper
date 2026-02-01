/// Web client ID for Google Sign-In (required on web).
/// Set via: flutter run -d chrome --dart-define=GOOGLE_SIGN_IN_WEB_CLIENT_ID=YOUR_CLIENT_ID.apps.googleusercontent.com
/// Get it from: Google Cloud Console > APIs & Services > Credentials > OAuth 2.0 Client IDs (Web application).
const String kGoogleSignInWebClientId = String.fromEnvironment(
  'GOOGLE_SIGN_IN_WEB_CLIENT_ID',
  defaultValue: '',
);

bool get hasGoogleSignInWebClientId => kGoogleSignInWebClientId.isNotEmpty;
