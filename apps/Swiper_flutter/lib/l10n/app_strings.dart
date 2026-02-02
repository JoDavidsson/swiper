import 'dart:ui';

/// Localized strings for Swedish and English. Used when locale is set in app.
class AppStrings {
  AppStrings(this.locale);

  final Locale locale;

  bool get isSv => locale.languageCode == 'sv';

  String get profile => isSv ? 'Profil' : 'Profile';
  String get language => isSv ? 'Språk' : 'Language';
  String get dataAndPrivacy => isSv ? 'Data och integritet' : 'Data & Privacy';
  String get editPreferences => isSv ? 'Redigera preferenser' : 'Edit preferences';
  String get reRunOnboarding => isSv ? 'Kör om introquiz' : 'Re-run onboarding quiz';
  String get swedish => isSv ? 'Svenska' : 'Swedish';
  String get english => isSv ? 'Engelska' : 'English';
  String get getStarted => isSv ? 'Kom igång' : 'Get started';
  String get skipToSwipe => isSv ? 'Hoppa till swipe' : 'Skip to swipe';
  String get menu => isSv ? 'Meny' : 'Menu';
  String get filters => isSv ? 'Filter' : 'Filters';
  String get preferences => isSv ? 'Preferenser' : 'Preferences';
  String get swipeHint => isSv ? 'Svep höger för att gilla, vänster för att hoppa.' : 'Swipe right to like, left to skip.';
  String get likes => isSv ? 'Gillade' : 'Likes';
  String get compare => isSv ? 'Jämför' : 'Compare';
  String get deck => isSv ? 'Deck' : 'Deck';
  String get noLikesYet => isSv ? 'Inga gillade än' : 'No likes yet';
  String get swipeRightToSave => isSv ? 'Svep höger för att spara här.' : 'Swipe right to save items here.';
  String get backToDeck => isSv ? 'Tillbaka till deck' : 'Back to deck';
  String get compareItems => isSv ? 'Jämför' : 'Compare';
  String get shareShortlist => isSv ? 'Dela shortlist' : 'Share shortlist';
  String get selectItemsToCompare => isSv ? 'Välj 2–4 objekt från Gillade att jämföra.' : 'Select 2–4 items from Likes to compare.';
  String get goToLikes => isSv ? 'Gå till Gillade' : 'Go to Likes';
  String get optOutOfAnalytics => isSv ? 'Avsluta analys' : 'Opt out of analytics';
  String get optOutSubtitle => isSv
      ? 'Sluta skicka icke-nödvändiga händelser (detaljvyer, filter, jämför, onboarding m.m.). Swipes och gillade fungerar fortfarande.'
      : 'Stop sending non-essential events (detail views, filters, compare, onboarding, etc.). Swipes and likes still work.';
  String get connectSocial => isSv ? 'Anslut sociala konton' : 'Connect social accounts';
  String get connectSocialSubtitle => isSv
      ? 'Instagram, Facebook – valfritt, för personlig feed'
      : 'Instagram, Facebook – optional, for personalised feed';
  String get startOver => isSv ? 'Starta om' : 'Start over';
  String get startOverSubtitle => isSv ? 'Ny session, alla kort visas igen' : 'New session, all cards show again';
}
