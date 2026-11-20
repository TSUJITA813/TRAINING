import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';
import 'package:training_memo/main.dart';
import 'package:training_memo/models.dart';
import 'package:training_memo/store.dart';

void main() {
  testWidgets('保存済みの日は閲覧モード → 編集 → 保存／破棄', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    final store = AppStore.instance;
    await tester.runAsync(() async {
      await initializeDateFormatting('ja_JP');
      await store.load(directory: await Directory.systemTemp.createTemp('tm'));
      store.stepSource = StepSource.manual;
    });
    selectedDay.value = DateTime(2026, 11, 10);
    await tester.pumpWidget(const TrainingMemoApp());
    await tester.pumpAndSettle();

    // 閲覧モード：入力欄はなく、編集ボタンがある
    expect(find.text('保存済み（閲覧中）'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'メニュー名'), findsNothing);

    await tester.tap(find.text('編集する'));
    await tester.pumpAndSettle();
    final menuField = find.byWidgetPredicate(
        (w) => w is TextField && w.keyboardType == TextInputType.multiline && w.minLines == 5);
    await tester.enterText(menuField, 'BSQ 140@2');
    await tester.pumpAndSettle();
    expect(find.text('未保存の変更があります'), findsOneWidget);
    // まだ記録には反映されていない（下書きのみ）
    expect(store.records['2026-11-10']!.menu, contains('RPD'));
    expect(store.drafts['2026-11-10']!['menu'], 'BSQ 140@2');

    // 破棄すると元に戻る
    await tester.tap(find.text('破棄'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('破棄する'));
    await tester.pumpAndSettle();
    expect(store.records['2026-11-10']!.menu, contains('RPD'));
    expect(store.drafts.containsKey('2026-11-10'), isFalse);
    expect(find.text('保存済み（閲覧中）'), findsOneWidget);

    // 編集して保存すると反映される
    await tester.tap(find.text('編集する'));
    await tester.pumpAndSettle();
    await tester.enterText(menuField, 'BSQ 140@2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存').first);
    await tester.pumpAndSettle();
    expect(store.records['2026-11-10']!.menu, 'BSQ 140@2');
    expect(store.drafts, isEmpty);
    expect(find.text('保存済み（閲覧中）'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
