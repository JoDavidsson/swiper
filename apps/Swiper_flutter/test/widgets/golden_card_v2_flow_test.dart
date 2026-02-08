import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiper_flutter/data/onboarding_v2_provider.dart';
import 'package:swiper_flutter/features/deck/widgets/golden_card_v2_flow.dart';
import 'package:swiper_flutter/l10n/app_strings.dart';

void main() {
  final strings = AppStrings(const Locale('en'));

  Future<void> pumpFlow(
    WidgetTester tester, {
    OnboardingV2State initialState = const OnboardingV2State(),
    Future<void> Function(List<String>)? onSceneArchetypesChanged,
    Future<void> Function(String, String, bool)? onOptionToggled,
    Future<void> Function(int)? onStepChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GoldenCardV2Flow(
            strings: strings,
            initialState: initialState,
            onMarkInProgress: () async {},
            onSceneArchetypesChanged:
                onSceneArchetypesChanged ?? (values) async {},
            onSofaVibesChanged: (values) async {},
            onConstraintsChanged: ({
              String? budgetBand,
              bool clearBudgetBand = false,
              String? seatCount,
              bool clearSeatCount = false,
              bool? modularOnly,
              bool clearModularOnly = false,
              bool? kidsPets,
              bool clearKidsPets = false,
              bool? smallSpace,
              bool clearSmallSpace = false,
            }) async {},
            onOptionToggled:
                onOptionToggled ?? (stepName, optionId, selected) async {},
            onStepChanged: onStepChanged ?? (step) async {},
            onSkip: () async {},
            onComplete: (submission) async {},
            onStartFresh: () async {},
            onAdjust: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('room vibes requires exactly two picks before continue',
      (tester) async {
    final capturedSelections = <List<String>>[];

    await pumpFlow(
      tester,
      onSceneArchetypesChanged: (values) async {
        capturedSelections.add(List<String>.from(values));
      },
    );

    await tester.tap(find.widgetWithText(ElevatedButton, strings.goldV2Start));
    await tester.pumpAndSettle();

    ElevatedButton continueButton() => tester.widget<ElevatedButton>(
          find.widgetWithText(ElevatedButton, strings.goldV2Continue),
        );

    Finder tileForTitle(String key) {
      final title = find.text(strings.localize(key));
      return find.ancestor(of: title, matching: find.byType(InkWell)).first;
    }

    expect(continueButton().onPressed, isNull);

    await tester.tap(tileForTitle('goldV2RoomCalmTitle'));
    await tester.pumpAndSettle();
    expect(continueButton().onPressed, isNull);

    await tester.tap(tileForTitle('goldV2RoomWarmTitle'));
    await tester.pumpAndSettle();
    expect(continueButton().onPressed, isNotNull);

    await tester
        .tap(find.widgetWithText(ElevatedButton, strings.goldV2Continue));
    await tester.pumpAndSettle();

    expect(find.text(strings.goldV2SofaTitle), findsOneWidget);
    expect(capturedSelections.single.length, 2);
  });

  testWidgets('option toggle callback emits select and deselect',
      (tester) async {
    final toggles = <String>[];

    await pumpFlow(
      tester,
      initialState: const OnboardingV2State(currentStep: 1),
      onOptionToggled: (stepName, optionId, selected) async {
        toggles.add('$stepName:$optionId:$selected');
      },
    );

    final calmTile = find.ancestor(
      of: find.text(strings.localize('goldV2RoomCalmTitle')),
      matching: find.byType(InkWell),
    );

    await tester.tap(calmTile.first);
    await tester.pumpAndSettle();
    await tester.tap(calmTile.first);
    await tester.pumpAndSettle();

    expect(
      toggles,
      equals([
        'room_vibes:calm_minimal:true',
        'room_vibes:calm_minimal:false',
      ]),
    );
  });

  testWidgets('resume and back navigation preserve selections', (tester) async {
    final visitedSteps = <int>[];
    await pumpFlow(
      tester,
      initialState: const OnboardingV2State(
        currentStep: 2,
        sceneArchetypes: ['calm_minimal', 'warm_organic'],
      ),
      onStepChanged: (step) async => visitedSteps.add(step),
    );

    expect(find.text(strings.goldV2SofaTitle), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text(strings.goldV2RoomTitle), findsOneWidget);

    final continueButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, strings.goldV2Continue),
    );
    expect(continueButton.onPressed, isNotNull);
    expect(visitedSteps, contains(1));
  });
}
