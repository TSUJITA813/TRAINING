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
    expect(t, contains('・RPD：90kg×4回×2セット'));
    expect(t, isNot(contains('@')));
    expect(t, contains('サプリ：クレアチン'));
    // ignore: avoid_print
    print(t);
  });

  test('メニューのみのコピーは整形済みの内容だけ', () {
    final r = DayRecord(
        date: '2026-11-10', title: '試合期A',
        menu: '【試合期A】2026/11/10\nRPD 90@4 90@4 RPDW 45@5✕\nBSQ 130@2x3\n# 腰に張り',
        condition: '疲労度：3', weightKg: 88, steps: 8000);
    final t = buildMenuText(r);
    expect(t, '【試合期A】2026/11/10（火）\n'
        '・RPD：90kg×4回×2セット\n'
        '・RPDW：45kg×5回（失敗）\n'
        '・BSQ：130kg×2回×3セット\n'
        '※腰に張り');
    final r2 = DayRecord(date: '2026-11-12', title: 'B', menu: 'PSQ 175@2');
    expect(buildMenusText([r2, r]), startsWith('【試合期A】2026/11/10'));
  });

  testWidgets('整形表示が描画できる', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: WorkoutPreview(workout: parseWorkout('BSQ 130@2 130@2✕'))),
    ));
    expect(find.text('BSQ'), findsOneWidget);
    expect(find.textContaining('130'), findsWidgets);
  });
}
