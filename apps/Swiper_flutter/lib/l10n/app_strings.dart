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
      'details': 'Details',
      'save': 'Save',
      'undo': 'Undo',
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
      'filtersSubtitle': 'Narrow the deck by type, size, color, and more.',
      'sofaType': 'Sofa Type',
      'roomType': 'Room',
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
      // Sub-category labels
      'subcat_2_seater': '2-Seater',
      'subcat_3_seater': '3-Seater',
      'subcat_4_seater': '4-Seater',
      'subcat_corner_sofa': 'Corner Sofa',
      'subcat_u_sofa': 'U-Shaped',
      'subcat_chaise_sofa': 'Chaise',
      'subcat_modular_sofa': 'Modular',
      'subcat_sleeper_sofa': 'Sleeper',
      // Room type labels
      'room_living_room': 'Living Room',
      'room_bedroom': 'Bedroom',
      'room_outdoor': 'Outdoor',
      'room_office': 'Office',
      'room_hallway': 'Hallway',
      'room_kids_room': 'Kids Room',
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
      // Golden Card v2
      'goldV2IntroTitle': "Let's find your style direction",
      'goldV2IntroSubtitle':
          'Pick a few visuals and we will tune your deck in under 20 seconds.',
      'goldV2IntroTrust': 'No account needed. You can refine this anytime.',
      'goldV2Start': 'Start',
      'goldV2Continue': 'Continue',
      'goldV2SeeDeck': 'See my deck',
      'goldV2LooksRight': 'Looks right',
      'goldV2AdjustPicks': 'Adjust picks',
      'goldV2StartFresh': 'Start fresh',
      'goldV2RoomTitle': 'Pick 2 rooms you would love to live in',
      'goldV2RoomSubtitle': 'Trust your gut. There is no wrong answer.',
      'goldV2SofaTitle': 'Pick 2 sofa vibes',
      'goldV2SofaSubtitle': 'Choose the shapes and textures that feel right.',
      'goldV2ConstraintsTitle': 'Set practical boundaries',
      'goldV2ConstraintsSubtitle':
          'This helps us avoid options that do not fit your home.',
      'goldV2SummaryTitle': 'Your style direction is ready',
      'goldV2SummaryWeGotYou': 'We got you',
      'goldV2PickTwoRequired': '2 of 2 required',
      'goldV2RoomCalmTitle': 'Calm Minimal',
      'goldV2RoomCalmSubtitle': 'Light, airy, quiet',
      'goldV2RoomWarmTitle': 'Warm Organic',
      'goldV2RoomWarmSubtitle': 'Natural tones, soft textures',
      'goldV2RoomBoldTitle': 'Bold Eclectic',
      'goldV2RoomBoldSubtitle': 'Expressive, curated contrast',
      'goldV2RoomUrbanTitle': 'Urban Industrial',
      'goldV2RoomUrbanSubtitle': 'Raw edges, structured forms',
      'goldV2SofaRoundedTitle': 'Rounded Boucle',
      'goldV2SofaRoundedSubtitle': 'Soft curves, cozy look',
      'goldV2SofaLowTitle': 'Low Linen',
      'goldV2SofaLowSubtitle': 'Relaxed, grounded profile',
      'goldV2SofaStructuredTitle': 'Structured Leather',
      'goldV2SofaStructuredSubtitle': 'Tailored, defined lines',
      'goldV2SofaModularTitle': 'Modular Cloud',
      'goldV2SofaModularSubtitle': 'Flexible, deep comfort',
      'goldV2BudgetHeading': 'Budget',
      'goldV2SeatsHeading': 'Seats',
      'goldV2BudgetLt5k': '< 5k SEK',
      'goldV2Budget5k15k': '5k-15k SEK',
      'goldV2Budget15k30k': '15k-30k SEK',
      'goldV2Budget30kPlus': '30k+ SEK',
      'goldV2Seats2': '2 seats',
      'goldV2Seats3': '3 seats',
      'goldV2Seats4Plus': '4+ seats',
      'goldV2ConstraintModularOnly': 'Modular only',
      'goldV2ConstraintKidsPets': 'Kids or pets at home',
      'goldV2ConstraintSmallSpace': 'Small space',
      'goldV2SummaryFallback': 'We will start broad and adapt quickly.',
      'goldV2SummaryNoConstraints':
          'No practical limits selected. We will keep options broad.',
      'goldV2ConfidenceHigh': 'High confidence',
      'goldV2ConfidenceMedium': 'Medium confidence',
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
      'details': 'Detaljer',
      'save': 'Spara',
      'undo': 'Ångra',
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
      'filtersSubtitle': 'Begränsa decken efter typ, storlek, färg och mer.',
      'sofaType': 'Sofftyp',
      'roomType': 'Rum',
      'size': 'Storlek',
      'color': 'Färg',
      'condition': 'Skick',
      'any': 'Alla',
      // Sub-category labels
      'subcat_2_seater': '2-sits',
      'subcat_3_seater': '3-sits',
      'subcat_4_seater': '4-sits',
      'subcat_corner_sofa': 'Hörnsoffa',
      'subcat_u_sofa': 'U-soffa',
      'subcat_chaise_sofa': 'Divansoffa',
      'subcat_modular_sofa': 'Modulsoffa',
      'subcat_sleeper_sofa': 'Bäddsoffa',
      // Room type labels
      'room_living_room': 'Vardagsrum',
      'room_bedroom': 'Sovrum',
      'room_outdoor': 'Utomhus',
      'room_office': 'Kontor',
      'room_hallway': 'Hall',
      'room_kids_room': 'Barnrum',
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
      // Golden Card v2
      'goldV2IntroTitle': 'Lat oss hitta din stilriktning',
      'goldV2IntroSubtitle':
          'Valj nagra visuella alternativ sa anpassar vi din deck pa under 20 sekunder.',
      'goldV2IntroTrust': 'Inget konto kravs. Du kan alltid justera senare.',
      'goldV2Start': 'Starta',
      'goldV2Continue': 'Fortsatt',
      'goldV2SeeDeck': 'Visa min deck',
      'goldV2LooksRight': 'Detta stammer',
      'goldV2AdjustPicks': 'Justera val',
      'goldV2StartFresh': 'Borja om',
      'goldV2RoomTitle': 'Valj 2 rum du skulle vilja bo i',
      'goldV2RoomSubtitle': 'Ga pa kansla. Det finns inget fel svar.',
      'goldV2SofaTitle': 'Valj 2 soffvibbar',
      'goldV2SofaSubtitle': 'Valj former och texturer som kanns ratt.',
      'goldV2ConstraintsTitle': 'Satt praktiska ramar',
      'goldV2ConstraintsSubtitle':
          'Detta hjalper oss undvika alternativ som inte passar ditt hem.',
      'goldV2SummaryTitle': 'Din stilriktning ar klar',
      'goldV2SummaryWeGotYou': 'Vi forstar dig',
      'goldV2PickTwoRequired': '2 av 2 kravs',
      'goldV2RoomCalmTitle': 'Lugn Minimal',
      'goldV2RoomCalmSubtitle': 'Ljust, luftigt, stilla',
      'goldV2RoomWarmTitle': 'Varm Organisk',
      'goldV2RoomWarmSubtitle': 'Naturliga toner, mjuka texturer',
      'goldV2RoomBoldTitle': 'Bold Eklektisk',
      'goldV2RoomBoldSubtitle': 'Uttrycksfull, kuraterad kontrast',
      'goldV2RoomUrbanTitle': 'Urban Industriell',
      'goldV2RoomUrbanSubtitle': 'Raa kanter, strukturerade former',
      'goldV2SofaRoundedTitle': 'Rundad Boucle',
      'goldV2SofaRoundedSubtitle': 'Mjuka kurvor, mysigt uttryck',
      'goldV2SofaLowTitle': 'Lag Linne',
      'goldV2SofaLowSubtitle': 'Avslappnad, jordad profil',
      'goldV2SofaStructuredTitle': 'Strukturerad Lader',
      'goldV2SofaStructuredSubtitle': 'Skraddad, tydlig linje',
      'goldV2SofaModularTitle': 'Modular Cloud',
      'goldV2SofaModularSubtitle': 'Flexibel, djup komfort',
      'goldV2BudgetHeading': 'Budget',
      'goldV2SeatsHeading': 'Sittplatser',
      'goldV2BudgetLt5k': '< 5k SEK',
      'goldV2Budget5k15k': '5k-15k SEK',
      'goldV2Budget15k30k': '15k-30k SEK',
      'goldV2Budget30kPlus': '30k+ SEK',
      'goldV2Seats2': '2 sittplatser',
      'goldV2Seats3': '3 sittplatser',
      'goldV2Seats4Plus': '4+ sittplatser',
      'goldV2ConstraintModularOnly': 'Endast modulsoffa',
      'goldV2ConstraintKidsPets': 'Barn eller husdjur hemma',
      'goldV2ConstraintSmallSpace': 'Litet utrymme',
      'goldV2SummaryFallback': 'Vi startar brett och anpassar snabbt.',
      'goldV2SummaryNoConstraints':
          'Inga praktiska gränser valda. Vi håller alternativen breda.',
      'goldV2ConfidenceHigh': 'Hog sakerhet',
      'goldV2ConfidenceMedium': 'Medel sakerhet',
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
  String get details => _t('details');
  String get save => _t('save');
  String get undo => _t('undo');
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
  String get sofaType => _t('sofaType');
  String get roomType => _t('roomType');
  String get size => _t('size');
  String get color => _t('color');
  String get condition => _t('condition');
  String get any => _t('any');
  String get small => _t('small');
  String get medium => _t('medium');
  String subCatLabel(String id) => _t('subcat_$id');
  String roomTypeLabel(String id) => _t('room_$id');
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
  String get goldV2IntroTitle => _t('goldV2IntroTitle');
  String get goldV2IntroSubtitle => _t('goldV2IntroSubtitle');
  String get goldV2IntroTrust => _t('goldV2IntroTrust');
  String get goldV2Start => _t('goldV2Start');
  String get goldV2Continue => _t('goldV2Continue');
  String get goldV2SeeDeck => _t('goldV2SeeDeck');
  String get goldV2LooksRight => _t('goldV2LooksRight');
  String get goldV2AdjustPicks => _t('goldV2AdjustPicks');
  String get goldV2StartFresh => _t('goldV2StartFresh');
  String get goldV2RoomTitle => _t('goldV2RoomTitle');
  String get goldV2RoomSubtitle => _t('goldV2RoomSubtitle');
  String get goldV2SofaTitle => _t('goldV2SofaTitle');
  String get goldV2SofaSubtitle => _t('goldV2SofaSubtitle');
  String get goldV2ConstraintsTitle => _t('goldV2ConstraintsTitle');
  String get goldV2ConstraintsSubtitle => _t('goldV2ConstraintsSubtitle');
  String get goldV2SummaryTitle => _t('goldV2SummaryTitle');
  String get goldV2SummaryWeGotYou => _t('goldV2SummaryWeGotYou');
  String get goldV2PickTwoRequired => _t('goldV2PickTwoRequired');
  String get goldV2ConstraintModularOnly => _t('goldV2ConstraintModularOnly');
  String get goldV2ConstraintKidsPets => _t('goldV2ConstraintKidsPets');
  String get goldV2ConstraintSmallSpace => _t('goldV2ConstraintSmallSpace');
  String get goldV2SummaryFallback => _t('goldV2SummaryFallback');
  String get goldV2SummaryNoConstraints => _t('goldV2SummaryNoConstraints');
  String get goldV2ConfidenceHigh => _t('goldV2ConfidenceHigh');
  String get goldV2ConfidenceMedium => _t('goldV2ConfidenceMedium');
  String get goldV2BudgetHeading => _t('goldV2BudgetHeading');
  String get goldV2SeatsHeading => _t('goldV2SeatsHeading');
  String localize(String key) => _t(key);
  String goldV2StepProgress(int step, int total) => locale.languageCode == 'sv'
      ? 'Steg $step av $total'
      : 'Step $step of $total';
  String goldV2BudgetLabel(String id) {
    switch (id) {
      case 'lt_5k':
        return _t('goldV2BudgetLt5k');
      case '5k_15k':
        return _t('goldV2Budget5k15k');
      case '15k_30k':
        return _t('goldV2Budget15k30k');
      case '30k_plus':
        return _t('goldV2Budget30kPlus');
      default:
        return id;
    }
  }

  String goldV2SeatsLabel(String id) {
    switch (id) {
      case '2':
        return _t('goldV2Seats2');
      case '3':
        return _t('goldV2Seats3');
      case '4_plus':
        return _t('goldV2Seats4Plus');
      default:
        return id;
    }
  }

  String goldV2SummaryLine(String room, String sofa) {
    if (locale.languageCode == 'sv') {
      return 'Du lutar at $room med soffvibb $sofa.';
    }
    return 'You lean $room with a $sofa sofa vibe.';
  }

  String goldV2SummaryRoomOnly(String room) {
    if (locale.languageCode == 'sv') {
      return 'Din rumsstil pekar mot $room.';
    }
    return 'Your room style leans $room.';
  }

  String goldV2SummarySofaOnly(String sofa) {
    if (locale.languageCode == 'sv') {
      return 'Din soffvibb pekar mot $sofa.';
    }
    return 'Your sofa vibe leans $sofa.';
  }

  String goldV2SummaryConstraintLine(String line) {
    if (locale.languageCode == 'sv') {
      return 'Vi prioriterar: $line.';
    }
    return 'We will prioritize: $line.';
  }

  String goldV2ConfidenceLabel(String confidence) {
    if (locale.languageCode == 'sv') {
      return 'Stilmatch: $confidence';
    }
    return 'Style confidence: $confidence';
  }
}
