import 'dart:ui';

/// Localized strings with keyed lookup and English fallback.
/// Add a new language by adding one locale map in [_valuesByLocale].
class AppStrings {
  AppStrings(this.locale);

  final Locale locale;

  static const Map<String, Map<String, String>> _valuesByLocale = {
    'en': {
      'profile': 'Profile',
      'language': 'Language',
      'dataAndPrivacy': 'Data & Privacy',
      'editPreferences': 'Edit preferences',
      'reRunOnboarding': 'Re-run onboarding quiz',
      'swedish': 'Swedish',
      'english': 'English',
      'getStarted': 'Get started',
      'skipToSwipe': 'Skip to swipe',
      'menu': 'Menu',
      'filters': 'Filters',
      'preferences': 'Preferences',
      'swipeHint': 'Swipe right to like, left to skip.',
      'likes': 'Likes',
      'compare': 'Compare',
      'deck': 'Deck',
      'noLikesYet': 'No likes yet',
      'swipeRightToSave': 'Swipe right to save items here.',
      'backToDeck': 'Back to deck',
      'compareItems': 'Compare',
      'shareShortlist': 'Share shortlist',
      'selectItemsToCompare': 'Select 2–4 items from Likes to compare.',
      'goToLikes': 'Go to Likes',
      'optOutOfAnalytics': 'Opt out of analytics',
      'optOutSubtitle':
          'Stop sending non-essential events (detail views, filters, compare, onboarding, etc.). Swipes and likes still work.',
      'connectSocial': 'Connect social accounts',
      'connectSocialSubtitle':
          'Instagram, Facebook – optional, for personalised feed',
      'startOver': 'Start over',
      'startOverSubtitle': 'New session, all cards show again',
      'next': 'Next',
      'buildingDeck': 'Building your deck...',
      'chooseYourStyle': 'Choose your style',
      'budgetRangeSek': 'Budget range (SEK)',
      'preferencesTitle': 'Preferences',
      'ecoFriendlyOnly': 'Eco-friendly only',
      'newOnly': 'New only',
      'sizeConstraintSmallSpace': 'Size constraint (small space)',
      'noItemsMatchFilters': 'No items match your filters',
      'noMoreItemsToShow': 'No more items',
      'adjustFiltersOrClear':
          'Try adjusting your filters or clearing them to see more sofas.',
      'checkBackLater': 'Great job! Check back later for new arrivals.',
      'clearFilters': 'Clear Filters',
      'refreshDeck': 'Refresh Deck',
      'filtersTitle': 'Filters',
      'filtersSubtitle': 'Narrow the deck by size, color, and condition.',
      'size': 'Size',
      'color': 'Color',
      'condition': 'Condition',
      'any': 'Any',
      'small': 'Small',
      'medium': 'Medium',
      'large': 'Large',
      'newLabel': 'New',
      'usedLabel': 'Used',
      'clearAll': 'Clear all',
      'apply': 'Apply',
      'listView': 'List view',
      'gridView': 'Grid view',
      'decisionRoom': 'Decision Room',
      'creatingDecisionRoom': 'Creating Decision Room...',
      'decisionRoomCreated': 'Decision Room created!',
      'view': 'View',
      'failedToCreateDecisionRoom': 'Failed to create room',
      'failedToLoadDecisionRoom': 'Failed to load decision room',
      'signIn': 'Sign in',
      'signInRequired': 'Sign in required',
      'signInRequiredDecisionRoom':
          'You need to sign in to create a Decision Room and collaborate with others.',
      'cancel': 'Cancel',
      'nameDecisionRoom': 'Name your Decision Room',
      'roomName': 'Room name',
      'roomNameHint': 'e.g., "Our new sofa" (optional)',
      'skip': 'Skip',
      'create': 'Create',
      'welcomeToSwiper': 'Welcome to Swiper',
      'loginSubtitle':
          'Sign in to create Decision Rooms and collaborate with others',
      'continueWithGoogle': 'Continue with Google',
      'or': 'or',
      'email': 'Email',
      'emailHint': 'your@email.com',
      'password': 'Password',
      'passwordHint': 'Your password',
      'forgotPassword': 'Forgot password?',
      'close': 'Close',
      'dontHaveAccount': "Don't have an account? ",
      'signUp': 'Sign up',
      'continueWithoutAccount': 'Continue without signing in',
      'createAccount': 'Create account',
      'joinSwiper': 'Join Swiper',
      'signupSubtitle':
          'Create an account to save your preferences and collaborate with others',
      'passwordAtLeast6': 'At least 6 characters',
      'confirmPassword': 'Confirm password',
      'confirmPasswordHint': 'Re-enter your password',
      'termsNotice':
          'By creating an account, you agree to our Terms of Service and Privacy Policy.',
      'alreadyHaveAccount': 'Already have an account? ',
      'resetPassword': 'Reset password',
      'resetPasswordMessage':
          "Enter your email address and we'll send you a link to reset your password.",
      'send': 'Send',
      'passwordResetSent': 'Password reset email sent!',
      'failedToSendEmail': 'Failed to send email',
      'decisionRoomTitle': 'Decision Room',
      'roomNotFound': 'Room not found',
      'retry': 'Retry',
      'shareRoom': 'Share room',
      'shareDecisionRoomPrefix': 'Help me decide! Vote on sofas here:',
      'decisionRoomShareSubject': 'Swiper Decision Room',
      'featured': 'Featured',
      'suggestAlternative': 'Suggest alternative',
      'finalist': 'Finalist',
      'suggested': 'Suggested',
      'comments': 'Comments',
      'addComment': 'Add a comment...',
      'signInToComment': 'Sign in to comment',
      'final2Selected': 'Final 2 selected! Vote for your favorite.',
      'pickFinalists': 'Pick finalists',
      'pick2Finalists': 'Pick 2 finalists',
      'confirm': 'Confirm',
      'failedToVote': 'Failed to vote',
      'failedToAddComment': 'Failed to add comment',
      'failedToSuggest': 'Failed to suggest',
      'failedToSetFinalists': 'Failed to set finalists',
      'sharedShortlist': 'Shared shortlist',
      'shortlistEmpty': 'This shortlist is empty.',
      'startSwiping': 'Start swiping',
    },
    'sv': {
      'profile': 'Profil',
      'language': 'Språk',
      'dataAndPrivacy': 'Data och integritet',
      'editPreferences': 'Redigera preferenser',
      'reRunOnboarding': 'Kör om introquiz',
      'swedish': 'Svenska',
      'english': 'Engelska',
      'getStarted': 'Kom igång',
      'skipToSwipe': 'Hoppa till swipe',
      'menu': 'Meny',
      'filters': 'Filter',
      'preferences': 'Preferenser',
      'swipeHint': 'Svep höger för att gilla, vänster för att hoppa.',
      'likes': 'Gillade',
      'compare': 'Jämför',
      'deck': 'Deck',
      'noLikesYet': 'Inga gillade än',
      'swipeRightToSave': 'Svep höger för att spara här.',
      'backToDeck': 'Tillbaka till deck',
      'compareItems': 'Jämför',
      'shareShortlist': 'Dela shortlist',
      'selectItemsToCompare': 'Välj 2–4 objekt från Gillade att jämföra.',
      'goToLikes': 'Gå till Gillade',
      'optOutOfAnalytics': 'Avsluta analys',
      'optOutSubtitle':
          'Sluta skicka icke-nödvändiga händelser (detaljvyer, filter, jämför, onboarding m.m.). Swipes och gillade fungerar fortfarande.',
      'connectSocial': 'Anslut sociala konton',
      'connectSocialSubtitle':
          'Instagram, Facebook – valfritt, för personlig feed',
      'startOver': 'Starta om',
      'startOverSubtitle': 'Ny session, alla kort visas igen',
      'next': 'Nästa',
      'buildingDeck': 'Bygger din deck...',
      'chooseYourStyle': 'Välj din stil',
      'budgetRangeSek': 'Budgetintervall (SEK)',
      'preferencesTitle': 'Preferenser',
      'ecoFriendlyOnly': 'Endast miljövänligt',
      'newOnly': 'Endast nytt',
      'sizeConstraintSmallSpace': 'Storlekskrav (litet utrymme)',
      'noItemsMatchFilters': 'Inga objekt matchar dina filter',
      'noMoreItemsToShow': 'Inga fler objekt att visa',
      'adjustFiltersOrClear':
          'Justera dina filter eller rensa dem för att se fler soffor.',
      'checkBackLater': 'Bra jobbat! Kom tillbaka senare för nya objekt.',
      'clearFilters': 'Rensa filter',
      'refreshDeck': 'Uppdatera deck',
      'filtersTitle': 'Filter',
      'filtersSubtitle': 'Begränsa decken efter storlek, färg och skick.',
      'size': 'Storlek',
      'color': 'Färg',
      'condition': 'Skick',
      'any': 'Alla',
      'small': 'Liten',
      'medium': 'Mellan',
      'large': 'Stor',
      'newLabel': 'Ny',
      'usedLabel': 'Begagnad',
      'clearAll': 'Rensa alla',
      'apply': 'Använd',
      'listView': 'Listvy',
      'gridView': 'Rutnätsvy',
      'decisionRoom': 'Beslutsrum',
      'creatingDecisionRoom': 'Skapar beslutsrum...',
      'decisionRoomCreated': 'Beslutsrum skapat!',
      'view': 'Visa',
      'failedToCreateDecisionRoom': 'Kunde inte skapa rum',
      'failedToLoadDecisionRoom': 'Kunde inte ladda beslutsrum',
      'signIn': 'Logga in',
      'signInRequired': 'Inloggning krävs',
      'signInRequiredDecisionRoom':
          'Du behöver logga in för att skapa ett beslutsrum och samarbeta med andra.',
      'cancel': 'Avbryt',
      'nameDecisionRoom': 'Namnge ditt beslutsrum',
      'roomName': 'Rumsnamn',
      'roomNameHint': 't.ex. "Vår nya soffa" (valfritt)',
      'skip': 'Hoppa över',
      'create': 'Skapa',
      'welcomeToSwiper': 'Välkommen till Swiper',
      'loginSubtitle':
          'Logga in för att skapa beslutsrum och samarbeta med andra',
      'continueWithGoogle': 'Fortsätt med Google',
      'or': 'eller',
      'email': 'E-post',
      'emailHint': 'din@epost.se',
      'password': 'Lösenord',
      'passwordHint': 'Ditt lösenord',
      'forgotPassword': 'Glömt lösenord?',
      'close': 'Stäng',
      'dontHaveAccount': 'Har du inget konto? ',
      'signUp': 'Skapa konto',
      'continueWithoutAccount': 'Fortsätt utan konto',
      'createAccount': 'Skapa konto',
      'joinSwiper': 'Gå med i Swiper',
      'signupSubtitle':
          'Skapa ett konto för att spara preferenser och samarbeta med andra',
      'passwordAtLeast6': 'Minst 6 tecken',
      'confirmPassword': 'Bekräfta lösenord',
      'confirmPasswordHint': 'Skriv lösenordet igen',
      'termsNotice':
          'Genom att skapa ett konto godkänner du våra användarvillkor och vår integritetspolicy.',
      'alreadyHaveAccount': 'Har du redan ett konto? ',
      'resetPassword': 'Återställ lösenord',
      'resetPasswordMessage':
          'Ange din e-postadress så skickar vi en länk för att återställa lösenordet.',
      'send': 'Skicka',
      'passwordResetSent': 'E-post för lösenordsåterställning skickad!',
      'failedToSendEmail': 'Kunde inte skicka e-post',
      'decisionRoomTitle': 'Beslutsrum',
      'roomNotFound': 'Rummet hittades inte',
      'retry': 'Försök igen',
      'shareRoom': 'Dela rum',
      'shareDecisionRoomPrefix': 'Hjälp mig bestämma! Rösta på soffor här:',
      'decisionRoomShareSubject': 'Swiper Beslutsrum',
      'featured': 'Utvald',
      'suggestAlternative': 'Föreslå alternativ',
      'finalist': 'Finalist',
      'suggested': 'Föreslagen',
      'comments': 'Kommentarer',
      'addComment': 'Lägg till en kommentar...',
      'signInToComment': 'Logga in för att kommentera',
      'final2Selected': 'Final 2 valda! Rösta på din favorit.',
      'pickFinalists': 'Välj finalister',
      'pick2Finalists': 'Välj 2 finalister',
      'confirm': 'Bekräfta',
      'failedToVote': 'Kunde inte rösta',
      'failedToAddComment': 'Kunde inte lägga till kommentar',
      'failedToSuggest': 'Kunde inte föreslå',
      'failedToSetFinalists': 'Kunde inte sätta finalister',
      'sharedShortlist': 'Delad shortlist',
      'shortlistEmpty': 'Denna shortlist är tom.',
      'startSwiping': 'Börja swipa',
    },
  };

  String _t(String key) {
    final lang = locale.languageCode;
    final localized = _valuesByLocale[lang];
    if (localized != null && localized.containsKey(key)) {
      return localized[key]!;
    }
    return _valuesByLocale['en']![key] ?? key;
  }

  String onboardingStepOf(int current, int total) => '$current / $total';
  String selectedCount(int count, int total) => '$count/$total';
  String commentsCount(int count) => '${_t('comments')} ($count)';
  String compareCount(int count) => '${_t('compare')} $count';

  String get profile => _t('profile');
  String get language => _t('language');
  String get dataAndPrivacy => _t('dataAndPrivacy');
  String get editPreferences => _t('editPreferences');
  String get reRunOnboarding => _t('reRunOnboarding');
  String get swedish => _t('swedish');
  String get english => _t('english');
  String get getStarted => _t('getStarted');
  String get skipToSwipe => _t('skipToSwipe');
  String get menu => _t('menu');
  String get filters => _t('filters');
  String get preferences => _t('preferences');
  String get swipeHint => _t('swipeHint');
  String get likes => _t('likes');
  String get compare => _t('compare');
  String get deck => _t('deck');
  String get noLikesYet => _t('noLikesYet');
  String get swipeRightToSave => _t('swipeRightToSave');
  String get backToDeck => _t('backToDeck');
  String get compareItems => _t('compareItems');
  String get shareShortlist => _t('shareShortlist');
  String get selectItemsToCompare => _t('selectItemsToCompare');
  String get goToLikes => _t('goToLikes');
  String get optOutOfAnalytics => _t('optOutOfAnalytics');
  String get optOutSubtitle => _t('optOutSubtitle');
  String get connectSocial => _t('connectSocial');
  String get connectSocialSubtitle => _t('connectSocialSubtitle');
  String get startOver => _t('startOver');
  String get startOverSubtitle => _t('startOverSubtitle');
  String get next => _t('next');
  String get buildingDeck => _t('buildingDeck');
  String get chooseYourStyle => _t('chooseYourStyle');
  String get budgetRangeSek => _t('budgetRangeSek');
  String get preferencesTitle => _t('preferencesTitle');
  String get ecoFriendlyOnly => _t('ecoFriendlyOnly');
  String get newOnly => _t('newOnly');
  String get sizeConstraintSmallSpace => _t('sizeConstraintSmallSpace');
  String get noItemsMatchFilters => _t('noItemsMatchFilters');
  String get noMoreItemsToShow => _t('noMoreItemsToShow');
  String get adjustFiltersOrClear => _t('adjustFiltersOrClear');
  String get checkBackLater => _t('checkBackLater');
  String get clearFilters => _t('clearFilters');
  String get refreshDeck => _t('refreshDeck');
  String get filtersTitle => _t('filtersTitle');
  String get filtersSubtitle => _t('filtersSubtitle');
  String get size => _t('size');
  String get color => _t('color');
  String get condition => _t('condition');
  String get any => _t('any');
  String get small => _t('small');
  String get medium => _t('medium');
  String get large => _t('large');
  String get newLabel => _t('newLabel');
  String get usedLabel => _t('usedLabel');
  String get clearAll => _t('clearAll');
  String get apply => _t('apply');
  String get listView => _t('listView');
  String get gridView => _t('gridView');
  String get decisionRoom => _t('decisionRoom');
  String get creatingDecisionRoom => _t('creatingDecisionRoom');
  String get decisionRoomCreated => _t('decisionRoomCreated');
  String get view => _t('view');
  String get failedToCreateDecisionRoom => _t('failedToCreateDecisionRoom');
  String get failedToLoadDecisionRoom => _t('failedToLoadDecisionRoom');
  String get signIn => _t('signIn');
  String get signInRequired => _t('signInRequired');
  String get signInRequiredDecisionRoom => _t('signInRequiredDecisionRoom');
  String get cancel => _t('cancel');
  String get nameDecisionRoom => _t('nameDecisionRoom');
  String get roomName => _t('roomName');
  String get roomNameHint => _t('roomNameHint');
  String get skip => _t('skip');
  String get create => _t('create');
  String get welcomeToSwiper => _t('welcomeToSwiper');
  String get loginSubtitle => _t('loginSubtitle');
  String get continueWithGoogle => _t('continueWithGoogle');
  String get or => _t('or');
  String get email => _t('email');
  String get emailHint => _t('emailHint');
  String get password => _t('password');
  String get passwordHint => _t('passwordHint');
  String get forgotPassword => _t('forgotPassword');
  String get close => _t('close');
  String get dontHaveAccount => _t('dontHaveAccount');
  String get signUp => _t('signUp');
  String get continueWithoutAccount => _t('continueWithoutAccount');
  String get createAccount => _t('createAccount');
  String get joinSwiper => _t('joinSwiper');
  String get signupSubtitle => _t('signupSubtitle');
  String get passwordAtLeast6 => _t('passwordAtLeast6');
  String get confirmPassword => _t('confirmPassword');
  String get confirmPasswordHint => _t('confirmPasswordHint');
  String get termsNotice => _t('termsNotice');
  String get alreadyHaveAccount => _t('alreadyHaveAccount');
  String get resetPassword => _t('resetPassword');
  String get resetPasswordMessage => _t('resetPasswordMessage');
  String get send => _t('send');
  String get passwordResetSent => _t('passwordResetSent');
  String get failedToSendEmail => _t('failedToSendEmail');
  String get decisionRoomTitle => _t('decisionRoomTitle');
  String get roomNotFound => _t('roomNotFound');
  String get retry => _t('retry');
  String get shareRoom => _t('shareRoom');
  String get shareDecisionRoomPrefix => _t('shareDecisionRoomPrefix');
  String get decisionRoomShareSubject => _t('decisionRoomShareSubject');
  String get featured => _t('featured');
  String get suggestAlternative => _t('suggestAlternative');
  String get finalist => _t('finalist');
  String get suggested => _t('suggested');
  String get comments => _t('comments');
  String get addComment => _t('addComment');
  String get signInToComment => _t('signInToComment');
  String get final2Selected => _t('final2Selected');
  String get pickFinalists => _t('pickFinalists');
  String get pick2Finalists => _t('pick2Finalists');
  String get confirm => _t('confirm');
  String get failedToVote => _t('failedToVote');
  String get failedToAddComment => _t('failedToAddComment');
  String get failedToSuggest => _t('failedToSuggest');
  String get failedToSetFinalists => _t('failedToSetFinalists');
  String get sharedShortlist => _t('sharedShortlist');
  String get shortlistEmpty => _t('shortlistEmpty');
  String get startSwiping => _t('startSwiping');
}
