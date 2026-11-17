import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:training_memo/models.dart';
import 'package:training_memo/parser.dart';
import 'package:training_memo/share_text.dart';
import 'package:training_memo/store.dart';
import 'package:training_memo/widgets.dart';

void main() {
  test('日報テキストに必要項目が含まれる', () {
    final s = AppStore.instance;
    final d = DateTime(2026, 11, 10);
    s.records['2026-11-10'] = DayRecord(
      date: '2026-11-10', title: '試合前A',
      menu: 'RPD 90@4 90@4 RPDW 45@5✕', condition: 'サプリ：クレアチン',
      weightKg: 88, steps: 8000);
    final t = buildShareText(d);
    expect(t, contains('2026/11/10（火）'));
    expect(t, contains('体重：88.0kg'));
    expect(t, contains('歩数：8,000歩'));
    expect(t, contains('RPD 90@4 90@4 RPDW 45@5✕'));
    expect(t, contains('サプリ：クレアチン'));
    // ignore: avoid_print
    print(t);
  });

  testWidgets('整形表示が描画できる', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WorkoutPreview(workout: parseWorkout('BSQ 130@2 130@2✕'))),
    ));
    expect(find.text('BSQ'), findsOneWidget);
    expect(find.textContaining('130'), findsWidgets);
  });
}
