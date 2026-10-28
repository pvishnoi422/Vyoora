import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vyoora/models/analysis_outcome.dart';
import 'package:vyoora/result_screen.dart';
import 'package:vyoora/services/storage_service.dart';

Map<String, dynamic> completed() => {
  'status': 'success',
  'analysis_complete': true,
  'summary': 'One ingredient was read.',
  'ingredient_count': 1,
  'all_ingredients': ['Water'],
  'concerns': [],
  'smart_score': 100,
};

void main() {
  test(
    'completed zero concerns is distinct from missing or failed analysis',
    () {
      expect(AnalysisOutcome.fromJson(completed()).isSuccess, isTrue);
      for (final response in <Map<String, dynamic>>[
        {},
        {'concerns': [], 'smart_score': 100},
        {...completed(), 'status': 'error'},
        {...completed(), 'analysis_complete': false},
        {...completed(), 'ingredient_count': 0},
        {...completed(), 'ingredient_count': 2},
        {...completed(), 'concerns': null},
        {...completed(), 'summary': ''},
        {...completed(), 'smart_score': 101},
        {
          ...completed(),
          'concerns': [
            {'ingredient': 'Water'},
          ],
        },
      ]) {
        expect(AnalysisOutcome.fromJson(response).isSuccess, isFalse);
      }
    },
  );

  for (final payload in [
    {'summary': 'AI unavailable.', 'concerns': <dynamic>[], 'smart_score': 100},
    {...completed(), 'status': 'error'},
    {...completed(), 'concerns': 'malformed'},
  ]) {
    testWidgets(
      'unverified or failed result has no score or clear result: $payload',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(home: ResultScreen(result: payload)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Analysis unavailable'), findsOneWidget);
        expect(find.textContaining('No ingredient assessment'), findsOneWidget);
        expect(find.textContaining('No concerns were flagged'), findsNothing);
        expect(find.textContaining('No notable concerns'), findsNothing);
        expect(find.text('100'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'history never promotes an old or failed scan into a successful scan',
    () async {
      final legacy = ScanRecord(
        date: 'old',
        score: 100,
        ingredientCount: 1,
        concernCount: 0,
        summary: 'AI failed',
        fullResult: {'concerns': []},
      );
      final raw = jsonEncode(legacy.toJson());
      SharedPreferences.setMockInitialValues({
        'scan_history': [raw],
      });
      expect(await StorageService.getScanHistory(), isEmpty);
      expect(
        (await SharedPreferences.getInstance()).getStringList('scan_history'),
        [raw],
      );
      await expectLater(StorageService.addScan(legacy), throwsArgumentError);
      final result = completed();
      await StorageService.addScan(
        ScanRecord(
          date: 'new',
          score: 100,
          ingredientCount: 1,
          concernCount: 0,
          summary: 'Completed',
          fullResult: result,
        ),
      );
      expect((await StorageService.getScanHistory()).length, 1);
    },
  );

  test(
    'user-facing errors distinguish a usage pause and an unreadable label',
    () {
      expect(
        analysisRequestError(429, {'code': 'budget_exhausted'}),
        contains('usage limit'),
      );
      expect(
        analysisRequestError(422, {'code': 'no_ingredients'}),
        contains('clearer photo'),
      );
      expect(
        analysisRequestError(502, {}),
        contains('No ingredient assessment'),
      );
    },
  );
}
