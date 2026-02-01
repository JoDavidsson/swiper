import 'dart:io' show Platform;

/// Platform label for mobile. Used via conditional import.
String get platform => Platform.isIOS ? 'ios' : 'android';
