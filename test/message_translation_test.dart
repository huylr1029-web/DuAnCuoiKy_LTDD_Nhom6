import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nhom6/services/translation_service.dart';
import 'package:nhom6/widgets/message_translation.dart';

void main() {
  testWidgets(
    'Translate on request, preserve original, hide and reuse result',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Text('Hello, how are you?'),
                MessageTranslation(
                  text: 'Hello, how are you?',
                  translate: (text, target) async {
                    calls++;
                    return const TranslationResult(
                      'Xin chào, bạn khỏe không?',
                      'en',
                      'vi',
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      expect(calls, 0);
      await tester.tap(find.text('Xem bản dịch'));
      await tester.pumpAndSettle();
      expect(find.text('Hello, how are you?'), findsOneWidget);
      expect(find.text('Xin chào, bạn khỏe không?'), findsOneWidget);
      await tester.tap(find.text('Ẩn bản dịch'));
      await tester.pump();
      expect(find.text('Xin chào, bạn khỏe không?'), findsNothing);
      await tester.tap(find.text('Xem bản dịch'));
      await tester.pump();
      expect(calls, 1);
    },
  );

  testWidgets(
    'Automatic translation runs for incoming messages and can retry errors',
    (tester) async {
      var fail = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageTranslation(
              text: 'Bonjour tout le monde',
              automatic: true,
              translate: (text, target) async {
                if (fail) throw StateError('Không có mạng');
                return const TranslationResult(
                  'Xin chào mọi người',
                  'fr',
                  'vi',
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Không có mạng'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Xem bản dịch'));
      await tester.pumpAndSettle();
      expect(find.text('Xin chào mọi người'), findsOneWidget);
    },
  );

  testWidgets('Reused list row ignores an old translation completing late', (
    tester,
  ) async {
    final old = Completer<TranslationResult>();
    Future<TranslationResult> translate(String text, String target) =>
        text == 'old'
        ? old.future
        : Future.value(const TranslationResult('mới', 'en', 'vi'));
    Widget screen(String text) => MaterialApp(
      home: Scaffold(
        body: MessageTranslation(
          key: const ValueKey('same-row'),
          text: text,
          automatic: true,
          translate: translate,
        ),
      ),
    );
    await tester.pumpWidget(screen('old'));
    await tester.pump();
    await tester.pumpWidget(screen('new'));
    await tester.pumpAndSettle();
    old.complete(const TranslationResult('cũ', 'en', 'vi'));
    await tester.pumpAndSettle();
    expect(find.text('mới'), findsOneWidget);
    expect(find.text('cũ'), findsNothing);
  });
}
